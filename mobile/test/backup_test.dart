import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keybox/core/vault_store.dart';
import 'package:keybox/backup/backup_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('独立备份密码、错误密码不导入、恢复使用新 ID 并保留原数据', () async {
    final store = await VaultStore.open(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    addTearDown(() async {
      store.lock();
      await store.db.close();
    });
    await store.initialize(await store.crypto.create('test-master-password'));
    final original = await store.save('password', {
      'name': 'Backup account',
      'password': 'backup-secret',
    });
    final backup = BackupCodec(store);
    final data = await backup.export('independent-backup-password');
    expect(String.fromCharCodes(data), isNot(contains('backup-secret')));
    await expectLater(
      backup.import(data, 'wrong-password'),
      throwsA(isA<Exception>()),
    );
    expect(store.records, hasLength(1));
    expect(await backup.import(data, 'independent-backup-password'), 1);
    expect(store.records, hasLength(2));
    expect(store.records.map((r) => r['id']).toSet(), hasLength(2));
    expect(store.records.any((r) => r['id'] == original), isTrue);
    final tampered = data.toList();
    tampered[tampered.length ~/ 2] ^= 1;
    await expectLater(
      backup.import(tampered, 'independent-backup-password'),
      throwsA(isA<Exception>()),
    );
    expect(store.records, hasLength(2));
  });
}
