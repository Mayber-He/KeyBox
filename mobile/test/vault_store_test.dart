import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keybox/core/vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('密文持久化、锁定清空内存、重启解锁及删除待同步', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final store = await VaultStore.open(db);
    final setup = await store.crypto.create('a long master password');
    await store.initialize(setup);
    final id = await store.save('password', {
      'name': 'private-name',
      'password': 'private-password',
    });
    final rows = await db.query('items');
    expect(rows.toString(), isNot(contains('private-password')));
    expect(rows.toString(), isNot(contains('private-name')));
    expect(store.records.single['id'], id);
    store.lock();
    expect(store.records, isEmpty);
    expect(store.unlocked, isFalse);
    final restarted = await VaultStore.open(db);
    await expectLater(
      restarted.unlock('wrong-master-password'),
      throwsA(isA<Exception>()),
    );
    await restarted.unlock('a long master password');
    expect(restarted.records.single['password'], 'private-password');
    final changed = await restarted.prepareChange(
      'a long master password',
      'another master password',
    );
    await restarted.applyChange(changed);
    expect(restarted.records.single['password'], 'private-password');
    restarted.lock();
    await expectLater(
      restarted.unlock('a long master password'),
      throwsA(isA<Exception>()),
    );
    final recovered = await restarted.prepareRecovery(
      changed.recoveryKey,
      'recovered master password',
    );
    await restarted.applyChange(recovered);
    expect(restarted.records.single['password'], 'private-password');
    await expectLater(
      restarted.crypto.recover(restarted.metadata!, changed.recoveryKey),
      throwsA(isA<Exception>()),
    );
    await restarted.delete(id);
    expect(restarted.records, isEmpty);
    expect((await db.query('items')).single['deleted'], 1);
    expect((await db.query('items')).single['pending'], 1);
    restarted.lock();
    await db.close();
  });
}
