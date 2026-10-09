import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';
import 'crypto_box.dart';
import 'record_validation.dart';
import 'dart:typed_data';

class VaultStore extends ChangeNotifier {
  VaultStore._(this.db);
  final Database db;
  final crypto = CryptoBox();
  final mutex = Lock(reentrant: true);
  VoidCallback? onMutation;
  Uint8List? pendingBackup;
  void stageBackup(Uint8List bytes) {
    pendingBackup = bytes;
    notifyListeners();
  }

  SecretKey? _key;
  Json? metadata;
  int epoch = 0;
  List<Json> _records = [];
  bool get unlocked => _key != null;
  bool get configured => metadata != null;
  List<Json> get records => List.unmodifiable(_records);
  String get vaultId => metadata!['vault_id'] as String;

  static Future<VaultStore> open(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, version INTEGER NOT NULL, deleted INTEGER NOT NULL, payload TEXT, pending INTEGER NOT NULL, operation_id TEXT)',
    );
    final store = VaultStore._(db);
    final header = await store.config('metadata');
    if (header != null) {
      store.metadata = Json.from(jsonDecode(header) as Map);
      CryptoBox.validateMetadata(store.metadata!);
    }
    return store;
  }

  Future<String?> config(String key) async {
    final rows = await db.query('config', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setConfig(
    String key,
    String? value, {
    DatabaseExecutor? transaction,
  }) async {
    final target = transaction ?? db;
    if (value == null) {
      await target.delete('config', where: 'key = ?', whereArgs: [key]);
    } else {
      await target.insert('config', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  void check(int generation) {
    if (!unlocked || epoch != generation) throw StateError('密码箱已锁定，请重新解锁');
  }

  void lock() {
    epoch++;
    _key?.destroy();
    _key = null;
    _records = [];
    notifyListeners();
  }

  Future<void> initialize(VaultSetup setup) => mutex.synchronized(() async {
    try {
      final generation = epoch;
      if (configured) throw StateError('密码箱已经初始化');
      await db.transaction((txn) async {
        await setConfig(
          'metadata',
          jsonEncode(setup.metadata),
          transaction: txn,
        );
        await setConfig('metadata_version', '0', transaction: txn);
        await setConfig(
          'metadata_operation',
          const Uuid().v4(),
          transaction: txn,
        );
      });
      metadata = setup.metadata;
      if (generation != epoch) {
        setup.key.destroy();
        notifyListeners();
        throw StateError('设置已保存，请重新解锁');
      }
      _key = setup.key;
      epoch++;
      notifyListeners();
    } catch (_) {
      if (identical(_key, setup.key)) {
        lock();
      } else {
        setup.key.destroy();
      }
      rethrow;
    }
  });

  Future<void> unlock(String password) => mutex.synchronized(() async {
    final generation = epoch;
    final key = await crypto.unlock(metadata!, password);
    if (generation != epoch) {
      key.destroy();
      throw StateError('解锁已取消，请重试');
    }
    _key = key;
    try {
      await reload();
    } catch (_) {
      lock();
      rethrow;
    }
  });

  Future<Json> decryptRecord(String id, Json envelope) async {
    final generation = epoch;
    check(generation);
    final data = await crypto.decrypt(
      _key!,
      envelope,
      vaultId: vaultId,
      purpose: id,
    );
    check(generation);
    validateRecord(data);
    return {...data, 'id': id};
  }

  Future<Json> encryptRecord(String id, Json data) async {
    validateRecord(data);
    final generation = epoch;
    check(generation);
    final envelope = await crypto.encrypt(
      _key!,
      Json.from(data)..remove('id'),
      vaultId: vaultId,
      purpose: id,
    );
    check(generation);
    return envelope;
  }

  Future<void> reload() => mutex.synchronized(() async {
    final generation = epoch;
    check(generation);
    final rows = await db.query(
      'items',
      where: 'deleted = 0',
      orderBy: 'rowid DESC',
    );
    final records = <Json>[];
    for (final row in rows) {
      records.add(
        await decryptRecord(
          row['id'] as String,
          Json.from(jsonDecode(row['payload'] as String) as Map),
        ),
      );
    }
    check(generation);
    _records = records;
    notifyListeners();
  });

  Future<String> save(String kind, Json data, {String? id}) =>
      mutex.synchronized(() async {
        final generation = epoch;
        check(generation);
        id ??= const Uuid().v4();
        final previous = await db.query(
          'items',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (previous.isNotEmpty && previous.single['deleted'] == 1) {
          throw StateError('已删除条目不可覆盖，请另存为新条目');
        }
        final value = {...data, 'kind': kind}..remove('id');
        validateRecord(value);
        final payload = await crypto.encrypt(
          _key!,
          value,
          vaultId: vaultId,
          purpose: id!,
        );
        check(generation);
        await db.insert('items', {
          'id': id,
          'version': previous.isEmpty ? 0 : previous.single['version'],
          'deleted': 0,
          'payload': jsonEncode(payload),
          'pending': 1,
          'operation_id': const Uuid().v4(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await reload();
        onMutation?.call();
        return id!;
      });

  Future<void> delete(String id) => mutex.synchronized(() async {
    check(epoch);
    await db.update(
      'items',
      {
        'deleted': 1,
        'payload': null,
        'pending': 1,
        'operation_id': const Uuid().v4(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await reload();
    onMutation?.call();
  });

  Future<VaultSetup> prepareChange(
    String currentPassword,
    String newPassword,
  ) => mutex.synchronized(() async {
    final generation = epoch;
    check(generation);
    final verified = await crypto.unlock(metadata!, currentPassword);
    SecretKey? copy;
    try {
      copy = CryptoBox.secureKey(await verified.extractBytes());
      final setup = await crypto.create(
        newPassword,
        key: copy,
        vaultId: vaultId,
      );
      check(generation);
      return setup;
    } catch (_) {
      copy?.destroy();
      rethrow;
    } finally {
      verified.destroy();
    }
  });

  Future<VaultSetup> prepareRecovery(
    String recovery,
    String newPassword,
  ) async {
    final key = await crypto.recover(metadata!, recovery);
    try {
      return await crypto.create(newPassword, key: key, vaultId: vaultId);
    } catch (_) {
      key.destroy();
      rethrow;
    }
  }

  Future<void> applyChange(VaultSetup setup) => mutex.synchronized(() async {
    try {
      final generation = epoch;
      if (setup.metadata['vault_id'] != vaultId) throw StateError('密码箱身份不一致');
      await db.transaction((txn) async {
        await setConfig(
          'metadata',
          jsonEncode(setup.metadata),
          transaction: txn,
        );
        await setConfig(
          'metadata_operation',
          const Uuid().v4(),
          transaction: txn,
        );
      });
      metadata = setup.metadata;
      if (generation != epoch) {
        setup.key.destroy();
        notifyListeners();
        throw StateError('修改已保存，请重新解锁');
      }
      _key?.destroy();
      _key = setup.key;
      epoch++;
      await reload();
      onMutation?.call();
    } catch (_) {
      if (identical(_key, setup.key)) {
        lock();
      } else {
        setup.key.destroy();
      }
      rethrow;
    }
  });

  Future<void> adoptRemote(
    Json remoteMetadata,
    List<Json> remoteItems,
    SecretKey remoteKey, {
    required bool mergeLocal,
    required int version,
    bool metadataPending = false,
  }) => mutex.synchronized(() async {
    try {
      final generation = epoch;
      check(generation);
      CryptoBox.validateMetadata(remoteMetadata);
      final local = mergeLocal ? List<Json>.from(records) : <Json>[];
      final imported = <Json>[];
      final remoteId = remoteMetadata['vault_id'] as String;
      for (final item in remoteItems) {
        if (item['deleted'] != true) {
          final decrypted = await crypto.decrypt(
            remoteKey,
            Json.from(item['payload'] as Map),
            vaultId: remoteId,
            purpose: item['id'] as String,
          );
          validateRecord(decrypted);
        }
        imported.add({
          'id': item['id'],
          'version': item['version'],
          'deleted': item['deleted'] == true ? 1 : 0,
          'payload': item['payload'] == null
              ? null
              : jsonEncode(item['payload']),
          'pending': 0,
          'operation_id': null,
        });
      }
      for (final data in local) {
        final id = const Uuid().v4();
        final payload = await crypto.encrypt(
          remoteKey,
          Json.from(data)..remove('id'),
          vaultId: remoteId,
          purpose: id,
        );
        imported.add({
          'id': id,
          'version': 0,
          'deleted': 0,
          'payload': jsonEncode(payload),
          'pending': 1,
          'operation_id': const Uuid().v4(),
        });
      }
      check(generation);
      await db.transaction((txn) async {
        await txn.delete('items');
        for (final row in imported) {
          await txn.insert('items', row);
        }
        await setConfig(
          'metadata',
          jsonEncode(remoteMetadata),
          transaction: txn,
        );
        await setConfig('metadata_version', '$version', transaction: txn);
        await setConfig(
          'metadata_operation',
          metadataPending ? const Uuid().v4() : null,
          transaction: txn,
        );
      });
      metadata = remoteMetadata;
      if (generation != epoch) {
        remoteKey.destroy();
        notifyListeners();
        throw StateError('密码箱已切换，请重新解锁');
      }
      _key?.destroy();
      _key = remoteKey;
      epoch++;
      await reload();
    } catch (_) {
      if (identical(_key, remoteKey)) {
        lock();
      } else {
        remoteKey.destroy();
      }
      rethrow;
    }
  });
}

class VaultScope extends InheritedNotifier<VaultStore> {
  const VaultScope({super.key, required VaultStore store, required super.child})
    : super(notifier: store);
  static VaultStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VaultScope>()!.notifier!;
  static VaultStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VaultScope>()!.notifier!;
}
