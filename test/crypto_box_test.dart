import 'package:flutter_test/flutter_test.dart';
import 'package:keybox/core/crypto_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实主密码解锁、恢复密钥、身份绑定及篡改拒绝', () async {
    final box = CryptoBox();
    final setup = await box.create('a long master password');
    final key = await box.unlock(setup.metadata, 'a long master password');
    final recovered = await box.recover(setup.metadata, setup.recoveryKey);
    final envelope = await box.encrypt(
      key,
      {'password': 'private-password'},
      vaultId: setup.metadata['vault_id'] as String,
      purpose: 'item-id',
    );
    expect(
      await box.decrypt(
        recovered,
        envelope,
        vaultId: setup.metadata['vault_id'] as String,
        purpose: 'item-id',
      ),
      {'password': 'private-password'},
    );
    await expectLater(
      box.unlock(setup.metadata, 'incorrect-password'),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      box.decrypt(
        key,
        envelope,
        vaultId: setup.metadata['vault_id'] as String,
        purpose: 'other-id',
      ),
      throwsA(isA<Exception>()),
    );
    final changed = Map<String, dynamic>.from(envelope)
      ..['tag'] = 'AAAAAAAAAAAAAAAAAAAAAA==';
    await expectLater(
      box.decrypt(
        key,
        changed,
        vaultId: setup.metadata['vault_id'] as String,
        purpose: 'item-id',
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      (await box.encrypt(
        key,
        {'password': 'private-password'},
        vaultId: setup.metadata['vault_id'] as String,
        purpose: 'item-id',
      ))['nonce'],
      isNot(envelope['nonce']),
    );
    final bad = Map<String, dynamic>.from(setup.metadata);
    bad['kdf'] = {...(bad['kdf'] as Map), 'memory_kib': 1 << 30};
    await expectLater(
      box.unlock(bad, 'a long master password'),
      throwsFormatException,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
