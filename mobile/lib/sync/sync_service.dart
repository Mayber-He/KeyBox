import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto_box.dart';
import '../core/vault_store.dart';
import 'api_client.dart';

enum ConflictChoice { local, cloud, both }

class SyncConflict {
  SyncConflict(this.local, this.remote);
  final Json local, remote;
  String get id => local['id'] as String;
}

class RemoteVaultRequired implements Exception {}

class MetadataConflict implements Exception {}

class RemoteRecovery {
  RemoteRecovery(this.setup, this.version);
  final VaultSetup setup;
  final int version;
}

class SyncService extends ChangeNotifier {
  SyncService(this.store, {this.api, SessionStorage? storage})
    : storage = storage ?? SecureSessionStorage() {
    store.onMutation = _schedule;
    store.addListener(_storeChanged);
  }
  final VaultStore store;
  // Store notifications can run inside its reentrant mutex. Background work
  // must enter from the service's original zone instead of borrowing that lock.
  final Zone _zone = Zone.current;
  final SessionStorage storage;
  ApiClient? api;
  Timer? _timer;
  Future<void>? _running;
  bool busy = false;
  String status = '未连接';
  List<SyncConflict> conflicts = [];
  Json? remoteVault, metadataConflict;
  bool get connected => api?.authenticated ?? false;

  void _storeChanged() {
    if (!store.unlocked) {
      _timer?.cancel();
      conflicts = [];
      status = '已锁定';
      notifyListeners();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (connected && store.unlocked) {
      _timer = _zone.run(
        () => Timer(const Duration(milliseconds: 500), quietSync),
      );
    }
  }

  Future<void> load() async {
    try {
      final raw = await storage.read();
      if (raw == null) return;
      final data = Json.from(jsonDecode(raw) as Map);
      api = ApiClient(Uri.parse(data['url'] as String), storage);
      await api!.restore();
      status = '等待解锁后同步';
    } catch (_) {
      api?.close();
      api = null;
      try {
        await storage.write(null);
      } catch (_) {
        /* Local vault remains available. */
      }
      status = '登录信息无法读取，请重新连接';
    }
  }

  Future<void> connect(String address, String username, String password) async {
    if (busy) throw StateError('正在同步，请稍后连接');
    final candidate = ApiClient(Uri.parse(address.trim()), storage);
    try {
      await candidate.login(username.trim(), password);
    } catch (_) {
      candidate.close();
      rethrow;
    }
    api?.close();
    api = candidate;
    await store.setConfig('sync_url', candidate.base.toString());
    await store.setConfig('sync_username', username.trim());
    status = '已连接';
    notifyListeners();
    await sync();
  }

  Future<void> quietSync() async {
    if (!connected || !store.unlocked) return;
    try {
      await sync();
    } catch (_) {
      /* Status is surfaced in settings. */
    }
  }

  Future<void> sync() => _zone.run(() {
    if (_running != null) return _running!;
    final future = _perform().whenComplete(() => _running = null);
    _running = future;
    return future;
  });

  Future<Json> _snapshot() async =>
      Json.from(await api!.request('GET', '/vault') as Map);
  Future<void> _perform() => store.mutex.synchronized(() async {
    if (!connected) throw ApiError(401, 'login_required');
    final generation = store.epoch;
    store.check(generation);
    busy = true;
    status = '正在同步…';
    notifyListeners();
    try {
      var snapshot = await _snapshot();
      store.check(generation);
      final header = snapshot['metadata'];
      if (header != null && (header as Map)['vault_id'] != store.vaultId) {
        remoteVault = snapshot;
        throw RemoteVaultRequired();
      }
      if (header == null) {
        // A new server may replace a previous server; versions belong to that server.
        await store.db.transaction((txn) async {
          await store.setConfig('metadata_version', '0', transaction: txn);
          await store.setConfig(
            'metadata_operation',
            const Uuid().v4(),
            transaction: txn,
          );
          final rows = await txn.query('items');
          for (final row in rows) {
            await txn.update(
              'items',
              {'version': 0, 'pending': 1, 'operation_id': const Uuid().v4()},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        });
      }
      final metadataOperation = await store.config('metadata_operation');
      if (metadataOperation != null) {
        try {
          final result = Json.from(
            await api!.request(
                  'PUT',
                  '/vault/metadata',
                  body: {
                    'base_version': int.parse(
                      await store.config('metadata_version') ?? '0',
                    ),
                    'operation_id': metadataOperation,
                    'payload': store.metadata,
                  },
                )
                as Map,
          );
          store.check(generation);
          await store.db.transaction((txn) async {
            await store.setConfig(
              'metadata_version',
              '${result['version']}',
              transaction: txn,
            );
            await store.setConfig('metadata_operation', null, transaction: txn);
          });
          snapshot = await _snapshot();
          store.check(generation);
        } on ApiError catch (error) {
          if (error.status != 409 || error.current == null) rethrow;
          metadataConflict = error.current;
          throw MetadataConflict();
        }
      }
      final version = snapshot['metadata_version'] as int;
      final localVersion = int.parse(
        await store.config('metadata_version') ?? '0',
      );
      if (version > localVersion) {
        final remote = Json.from(snapshot['metadata'] as Map);
        CryptoBox.validateMetadata(remote);
        await store.db.transaction((txn) async {
          await store.setConfig(
            'metadata',
            jsonEncode(remote),
            transaction: txn,
          );
          await store.setConfig(
            'metadata_version',
            '$version',
            transaction: txn,
          );
        });
        store.metadata = remote;
      }
      conflicts = [];
      final pending = await store.db.query('items', where: 'pending = 1');
      for (final row in pending) {
        store.check(generation);
        try {
          final result = Json.from(
            await api!.request(
                  'PUT',
                  '/items/${row['id']}',
                  body: {
                    'vault_id': store.vaultId,
                    'base_version': row['version'],
                    'operation_id': row['operation_id'],
                    'deleted': row['deleted'] == 1,
                    'payload': row['payload'] == null
                        ? null
                        : jsonDecode(row['payload'] as String),
                  },
                )
                as Map,
          );
          store.check(generation);
          await _accept(result);
        } on ApiError catch (error) {
          if (error.status != 409 || error.current == null) rethrow;
          conflicts.add(SyncConflict(Json.from(row), error.current!));
        }
      }
      snapshot = await _snapshot();
      store.check(generation);
      final incoming = (snapshot['items'] as List)
          .map((item) => Json.from(item as Map))
          .toList();
      // Authenticate all received content before changing the local cache.
      for (final item in incoming) {
        if (item['deleted'] != true) {
          await store.decryptRecord(
            item['id'] as String,
            Json.from(item['payload'] as Map),
          );
        }
      }
      store.check(generation);
      await store.db.transaction((txn) async {
        for (final item in incoming) {
          final local = await txn.query(
            'items',
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          if (local.isNotEmpty &&
              (local.single['pending'] == 1 ||
                  (local.single['version'] as int) >
                      (item['version'] as int))) {
            continue;
          }
          await _accept(item, transaction: txn);
        }
      });
      await store.reload();
      remoteVault = null;
      metadataConflict = null;
      status = conflicts.isEmpty
          ? '已同步 · ${DateTime.now().toLocal().toString().substring(11, 16)}'
          : '${conflicts.length} 个条目需要解决冲突';
    } on RemoteVaultRequired {
      status = '云端已有密码箱，请解锁后合并';
      rethrow;
    } on MetadataConflict {
      status = '主密码设置发生冲突，请选择保留的设置';
      rethrow;
    } catch (error) {
      status = !store.unlocked
          ? '已锁定'
          : error is ApiError && error.status == 401
          ? '登录已失效，请重新连接'
          : '同步失败，本地修改已保留，可稍后重试';
      if (connected && store.unlocked) {
        _timer = _zone.run(() => Timer(const Duration(seconds: 30), quietSync));
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  });
  Future<void> _accept(Json item, {DatabaseExecutor? transaction}) async {
    await (transaction ?? store.db).insert('items', {
      'id': item['id'],
      'version': item['version'],
      'deleted': item['deleted'] == true ? 1 : 0,
      'payload': item['payload'] == null ? null : jsonEncode(item['payload']),
      'pending': 0,
      'operation_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> mergeRemote(
    String credential, {
    required bool recovery,
    required bool mergeLocal,
    RemoteRecovery? recoverySetup,
  }) => store.mutex.synchronized(() async {
    var key = recoverySetup?.setup.key;
    var adopted = false;
    try {
      final generation = store.epoch;
      store.check(generation);
      if (!mergeLocal && store.records.isNotEmpty) {
        throw StateError('请保留并合并现有本地条目');
      }
      final snapshot = await _snapshot();
      final metadata = Json.from(snapshot['metadata'] as Map);
      if (recovery && recoverySetup == null) {
        throw StateError('请先设置新的主密码并保存恢复密钥');
      }
      if (recoverySetup != null &&
          (recoverySetup.version != snapshot['metadata_version'] ||
              recoverySetup.setup.metadata['vault_id'] !=
                  metadata['vault_id'])) {
        throw StateError('云端设置已改变，请重新恢复');
      }
      key ??= await store.crypto.unlock(metadata, credential);
      store.check(generation);
      await store.adoptRemote(
        recoverySetup?.setup.metadata ?? metadata,
        (snapshot['items'] as List).map((i) => Json.from(i as Map)).toList(),
        key,
        mergeLocal: mergeLocal,
        version: snapshot['metadata_version'] as int,
        metadataPending: recoverySetup != null,
      );
      adopted = true;
    } catch (_) {
      if (!adopted) key?.destroy();
      rethrow;
    }
    remoteVault = null;
    status = '合并完成，等待同步';
    notifyListeners();
  });
  Future<RemoteRecovery> prepareRemoteRecovery(
    String recovery,
    String newPassword,
  ) => store.mutex.synchronized(() async {
    final generation = store.epoch;
    store.check(generation);
    final snapshot = await _snapshot();
    final metadata = Json.from(snapshot['metadata'] as Map);
    final key = await store.crypto.recover(metadata, recovery);
    try {
      final setup = await store.crypto.create(
        newPassword,
        key: key,
        vaultId: metadata['vault_id'] as String,
      );
      store.check(generation);
      return RemoteRecovery(setup, snapshot['metadata_version'] as int);
    } catch (_) {
      key.destroy();
      rethrow;
    }
  });
  Future<void> resolve(String id, ConflictChoice choice) =>
      store.mutex.synchronized(() async {
        store.check(store.epoch);
        final conflict = conflicts.firstWhere((item) => item.id == id);
        final rows = await store.db.query(
          'items',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isEmpty) throw StateError('本地条目已改变，请重新同步');
        final local = Json.from(rows.single), remote = conflict.remote;
        if (local['operation_id'] != conflict.local['operation_id']) {
          conflicts[conflicts.indexOf(conflict)] = SyncConflict(local, remote);
          notifyListeners();
          throw StateError('本地条目已再次修改，请确认最新版本后重试');
        }
        final missing = remote['version'] == 0 && remote['payload'] == null;
        Json? localData, remoteData;
        if (local['deleted'] != 1) {
          localData = await store.decryptRecord(
            id,
            Json.from(jsonDecode(local['payload'] as String) as Map),
          );
        }
        if (remote['deleted'] != true && !missing) {
          remoteData = await store.decryptRecord(
            id,
            Json.from(remote['payload'] as Map),
          );
        }
        if (choice == ConflictChoice.cloud) {
          if (missing) {
            await store.db.delete('items', where: 'id = ?', whereArgs: [id]);
          } else {
            await _accept(remote);
          }
        } else if (missing) {
          await store.db.update(
            'items',
            {'version': 0, 'pending': 1, 'operation_id': const Uuid().v4()},
            where: 'id = ?',
            whereArgs: [id],
          );
        } else if (choice == ConflictChoice.both || remote['deleted'] == true) {
          final copy = localData ?? remoteData;
          final cloneId = const Uuid().v4();
          final envelope = copy == null
              ? null
              : await store.encryptRecord(cloneId, copy);
          await store.db.transaction((txn) async {
            await _accept(remote, transaction: txn);
            if (envelope != null) {
              await txn.insert('items', {
                'id': cloneId,
                'version': 0,
                'deleted': 0,
                'payload': jsonEncode(envelope),
                'pending': 1,
                'operation_id': const Uuid().v4(),
              });
            }
            if (choice == ConflictChoice.both &&
                local['deleted'] == 1 &&
                remote['deleted'] != true) {
              await txn.update(
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
            }
          });
        } else {
          await store.db.update(
            'items',
            {
              'version': remote['version'],
              'pending': 1,
              'operation_id': const Uuid().v4(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        conflicts.removeWhere((item) => item.id == id);
        await store.reload();
        _schedule();
        notifyListeners();
      });
  Future<void> resolveMetadata(bool keepLocal) =>
      store.mutex.synchronized(() async {
        store.check(store.epoch);
        final current = metadataConflict!;
        final remote = Json.from(current['payload'] as Map);
        CryptoBox.validateMetadata(remote);
        if (remote['vault_id'] != store.vaultId) throw RemoteVaultRequired();
        await store.db.transaction((txn) async {
          await store.setConfig(
            'metadata_version',
            '${current['version']}',
            transaction: txn,
          );
          await store.setConfig(
            'metadata_operation',
            keepLocal ? const Uuid().v4() : null,
            transaction: txn,
          );
          if (!keepLocal) {
            await store.setConfig(
              'metadata',
              jsonEncode(remote),
              transaction: txn,
            );
          }
        });
        if (!keepLocal) store.metadata = remote;
        metadataConflict = null;
        status = '设置冲突已处理';
        notifyListeners();
        _schedule();
      });
  Future<void> disconnect({bool revoke = true}) async {
    if (busy) throw StateError('正在同步，请稍后退出');
    _timer?.cancel();
    try {
      if (revoke) {
        await api?.logout();
      } else {
        await api?.clearSession();
      }
    } finally {
      api?.close();
      api = null;
      status = '未连接';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    store.onMutation = null;
    store.removeListener(_storeChanged);
    api?.close();
    super.dispose();
  }
}

class SyncScope extends InheritedNotifier<SyncService> {
  const SyncScope({
    super.key,
    required SyncService service,
    required super.child,
  }) : super(notifier: service);
  static SyncService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()?.notifier;
}
