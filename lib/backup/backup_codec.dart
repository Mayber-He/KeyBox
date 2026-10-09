import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../core/crypto_box.dart';
import '../core/record_validation.dart';
import '../core/vault_store.dart';

class BackupCodec {
  BackupCodec(this.store);
  final VaultStore store;
  static const maxContent = 16 * 1024 * 1024;
  static const maxFile = 24 * 1024 * 1024;
  Future<Uint8List> export(String password) =>
      store.mutex.synchronized(() async {
        if (password.length < 12) throw const FormatException('备份密码至少 12 个字符');
        final generation = store.epoch;
        store.check(generation);
        final id = const Uuid().v4();
        final kdf = <String, dynamic>{
          'algorithm': 'argon2id',
          'memory_kib': 65536,
          'iterations': 3,
          'parallelism': 4,
          'salt': base64Encode(CryptoBox.randomBytes(16)),
        };
        final data = {
          'records': store.records
              .map((row) => Json.from(row)..remove('id'))
              .toList(),
        };
        final key = await store.crypto.derive(password, kdf);
        try {
          final payload = await store.crypto.encrypt(
            key,
            data,
            vaultId: id,
            purpose: 'backup',
            maximum: maxContent,
          );
          store.check(generation);
          return Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'format': 'keybox-backup',
                'version': 1,
                'id': id,
                'kdf': kdf,
                'payload': payload,
              }),
            ),
          );
        } finally {
          key.destroy();
        }
      });
  Future<int> import(List<int> file, String password) =>
      store.mutex.synchronized(() async {
        final generation = store.epoch;
        store.check(generation);
        if (file.length > maxFile) throw const FormatException('备份文件过大');
        final decoded = Json.from(jsonDecode(utf8.decode(file)) as Map);
        if (decoded['format'] != 'keybox-backup' ||
            decoded['version'] != 1 ||
            !Uuid.isValidUUID(fromString: decoded['id'] as String? ?? '')) {
          throw const FormatException('不支持的备份格式');
        }
        if (decoded['kdf'] is! Map || decoded['payload'] is! Map) {
          throw const FormatException('备份格式错误');
        }
        final key = await store.crypto.derive(
          password,
          Json.from(decoded['kdf'] as Map),
        );
        try {
          final content = await store.crypto.decrypt(
            key,
            Json.from(decoded['payload'] as Map),
            vaultId: decoded['id'] as String,
            purpose: 'backup',
            maximum: maxContent,
          );
          final records = (content['records'] as List)
              .map((row) => Json.from(row as Map))
              .toList();
          final prepared = <Json>[];
          for (final record in records) {
            validateRecord(record);
            final id = const Uuid().v4();
            final payload = await store.encryptRecord(id, record);
            prepared.add({
              'id': id,
              'version': 0,
              'deleted': 0,
              'payload': jsonEncode(payload),
              'pending': 1,
              'operation_id': const Uuid().v4(),
            });
          }
          store.check(generation);
          await store.db.transaction((txn) async {
            for (final row in prepared) {
              await txn.insert('items', row);
            }
          });
          await store.reload();
          store.onMutation?.call();
          return records.length;
        } finally {
          key.destroy();
        }
      });
}
