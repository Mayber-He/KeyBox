import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keybox/core/crypto_box.dart';
import 'package:keybox/core/vault_store.dart';
import 'package:keybox/sync/api_client.dart';
import 'package:keybox/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'sync_service_test.dart' as fixture;

Future<SyncService> device(http.Client client) async {
  final store = await VaultStore.open(
    await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    ),
  );
  const vaultId = '11111111-1111-4111-8111-111111111111';
  final key = CryptoBox.secureKey(List<int>.filled(32, 1));
  final wrappingKey = CryptoBox.secureKey(List<int>.filled(32, 2));
  final data = {'key': base64Encode(await key.extractBytes())};
  final metadata = <String, dynamic>{
    'format_version': 1,
    'vault_id': vaultId,
    'kdf': {
      'algorithm': 'argon2id',
      'memory_kib': 65536,
      'iterations': 3,
      'parallelism': 4,
      'salt': base64Encode(List<int>.filled(16, 3)),
    },
    'password_wrap': await store.crypto.encrypt(
      wrappingKey,
      data,
      vaultId: vaultId,
      purpose: 'password-key',
    ),
    'recovery_wrap': await store.crypto.encrypt(
      wrappingKey,
      data,
      vaultId: vaultId,
      purpose: 'recovery-key',
    ),
  };
  wrappingKey.destroy();
  CryptoBox.validateMetadata(metadata);
  await store.initialize(VaultSetup(metadata, key, 'fixture-only'));
  final api = ApiClient(
    Uri.parse('https://vault.example.com'),
    MemorySessionStorage(),
    client: client,
  );
  await api.login('user', 'sync-password');
  final service = SyncService(store, api: api);
  addTearDown(() async {
    service.dispose();
    store.lock();
    await store.db.close();
  });
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('保存后自动上传，无需手动同步', () async {
    final server = fixture.FakeServer();
    final service = await device(server.client());
    await service.store.save('password', {
      'name': 'Scheduled account',
      'password': 'scheduled-secret',
    });
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((server.items.isEmpty || service.busy) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(server.items, hasLength(1));
    expect((await service.store.db.query('items')).single['pending'], 0);
  });

  test('密码箱通知中的后台同步在锁释放后安全执行', () async {
    final server = fixture.FakeServer();
    final underlying = server.client();
    final entered = Completer<void>();
    final release = Completer<void>();
    var intercept = true;
    final client = MockClient((request) async {
      if (intercept && request.method == 'GET') {
        intercept = false;
        entered.complete();
        await release.future;
      }
      final forwarded = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
      return http.Response.fromStream(await underlying.send(forwarded));
    });
    final service = await device(client);
    final store = service.store;
    Future<void>? background;
    var started = false;
    void listener() {
      if (started) return;
      started = true;
      background = service.quietSync();
    }

    store.addListener(listener);
    addTearDown(() {
      store.removeListener(listener);
      underlying.close();
    });
    await store.mutex.synchronized(store.reload);
    await entered.future.timeout(const Duration(seconds: 5));
    release.complete();
    await background!.timeout(const Duration(seconds: 5));
    expect(service.status, startsWith('已同步'));
    expect(await store.config('metadata_operation'), isNull);
    expect(store.unlocked, isTrue);
  });
}
