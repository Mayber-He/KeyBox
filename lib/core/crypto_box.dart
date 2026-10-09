import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;

class VaultSetup {
  VaultSetup(this.metadata, this.key, this.recoveryKey);
  final Json metadata;
  final SecretKey key;
  final String recoveryKey;
}

class CryptoBox {
  static SecretKey secureKey(List<int> bytes) =>
      SecretKeyData(Uint8List.fromList(bytes), overwriteWhenDestroyed: true);
  final _cipher = AesGcm.with256bits();
  static List<int> randomBytes(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(256));
  }

  static List<int> bytes(dynamic value, {int? length, int maximum = 1048576}) {
    if (value is! String || value.length > maximum * 2) {
      throw const FormatException('无效加密数据');
    }
    final result = base64.decode(base64.normalize(value));
    if ((length != null && result.length != length) ||
        result.length > maximum) {
      throw const FormatException('无效加密数据长度');
    }
    return result;
  }

  static void validateKdf(Json kdf) {
    if (kdf['algorithm'] != 'argon2id' ||
        kdf['memory_kib'] != 65536 ||
        kdf['iterations'] != 3 ||
        kdf['parallelism'] != 4) {
      throw const FormatException('不支持的密钥派生参数');
    }
    bytes(kdf['salt'], length: 16);
  }

  static void validateMetadata(Json metadata) {
    if (metadata['format_version'] != 1 ||
        !Uuid.isValidUUID(fromString: metadata['vault_id'] as String? ?? '')) {
      throw const FormatException('不支持的密码箱格式');
    }
    validateKdf(Json.from(metadata['kdf'] as Map));
    validateEnvelope(Json.from(metadata['password_wrap'] as Map));
    validateEnvelope(Json.from(metadata['recovery_wrap'] as Map));
  }

  static void validateEnvelope(Json envelope, {int maximum = 1048576}) {
    if (envelope['version'] != 1) {
      throw const FormatException('不支持的加密格式');
    }
    bytes(envelope['nonce'], length: 12);
    bytes(envelope['tag'], length: 16);
    bytes(envelope['ciphertext'], maximum: maximum);
  }

  Future<SecretKey> derive(String password, Json kdf) async {
    validateKdf(kdf);
    final input = secureKey(utf8.encode(password));
    try {
      final derived = await Argon2id(
        parallelism: 4,
        memory: 65536,
        iterations: 3,
        hashLength: 32,
      ).deriveKey(secretKey: input, nonce: bytes(kdf['salt'], length: 16));
      try {
        return secureKey(await derived.extractBytes());
      } finally {
        derived.destroy();
      }
    } finally {
      input.destroy();
    }
  }

  Future<Json> encrypt(
    SecretKey key,
    Json data, {
    required String vaultId,
    required String purpose,
    int maximum = 1048576,
  }) async {
    final plaintext = utf8.encode(jsonEncode(data));
    if (plaintext.length > maximum) throw const FormatException('加密内容过大');
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: randomBytes(12),
      aad: utf8.encode('keybox:v1:$vaultId:$purpose'),
    );
    return {
      'version': 1,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  Future<Json> decrypt(
    SecretKey key,
    Json envelope, {
    required String vaultId,
    required String purpose,
    int maximum = 1048576,
  }) async {
    validateEnvelope(envelope, maximum: maximum);
    final plaintext = await _cipher.decrypt(
      SecretBox(
        bytes(envelope['ciphertext'], maximum: maximum),
        nonce: bytes(envelope['nonce'], length: 12),
        mac: Mac(bytes(envelope['tag'], length: 16)),
      ),
      secretKey: key,
      aad: utf8.encode('keybox:v1:$vaultId:$purpose'),
    );
    return Json.from(jsonDecode(utf8.decode(plaintext)) as Map);
  }

  Future<VaultSetup> create(
    String password, {
    SecretKey? key,
    String? vaultId,
  }) async {
    if (password.length < 12) throw const FormatException('主密码至少 12 个字符');
    final ownsKey = key == null;
    key ??= secureKey(randomBytes(32));
    SecretKey? passwordKey;
    SecretKey? recoveryKey;
    try {
      vaultId ??= const Uuid().v4();
      final kdf = <String, dynamic>{
        'algorithm': 'argon2id',
        'memory_kib': 65536,
        'iterations': 3,
        'parallelism': 4,
        'salt': base64Encode(randomBytes(16)),
      };
      passwordKey = await derive(password, kdf);
      final recoveryBytes = randomBytes(32);
      final recovery = base64UrlEncode(recoveryBytes).replaceAll('=', '');
      final data = {'key': base64Encode(await key.extractBytes())};
      final passwordWrap = await encrypt(
        passwordKey,
        data,
        vaultId: vaultId,
        purpose: 'password-key',
      );
      recoveryKey = secureKey(recoveryBytes);
      final recoveryWrap = await encrypt(
        recoveryKey,
        data,
        vaultId: vaultId,
        purpose: 'recovery-key',
      );
      return VaultSetup(
        {
          'format_version': 1,
          'vault_id': vaultId,
          'kdf': kdf,
          'password_wrap': passwordWrap,
          'recovery_wrap': recoveryWrap,
        },
        key,
        recovery,
      );
    } catch (_) {
      if (ownsKey) key.destroy();
      rethrow;
    } finally {
      passwordKey?.destroy();
      recoveryKey?.destroy();
    }
  }

  Future<SecretKey> unlock(Json metadata, String password) async {
    validateMetadata(metadata);
    final wrappingKey = await derive(
      password,
      Json.from(metadata['kdf'] as Map),
    );
    try {
      final data = await decrypt(
        wrappingKey,
        Json.from(metadata['password_wrap'] as Map),
        vaultId: metadata['vault_id'] as String,
        purpose: 'password-key',
      );
      return secureKey(bytes(data['key'], length: 32));
    } finally {
      wrappingKey.destroy();
    }
  }

  Future<SecretKey> recover(Json metadata, String recovery) async {
    validateMetadata(metadata);
    final wrappingKey = secureKey(bytes(recovery.trim(), length: 32));
    try {
      final data = await decrypt(
        wrappingKey,
        Json.from(metadata['recovery_wrap'] as Map),
        vaultId: metadata['vault_id'] as String,
        purpose: 'recovery-key',
      );
      return secureKey(bytes(data['key'], length: 32));
    } finally {
      wrappingKey.destroy();
    }
  }
}
