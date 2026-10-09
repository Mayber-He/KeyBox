import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keybox/core/crypto_box.dart';
import 'package:keybox/core/vault_store.dart';
import 'package:keybox/sync/api_client.dart';
import 'package:keybox/sync/sync_service.dart';

class FakeServer {
  Json? metadata;
  int metadataVersion = 0;
  final items = <String, Json>{};
  final operations = <String, Json>{};
  bool offline = false, loseReply = false;
  http.Client client() => MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    final data = request.body.isEmpty
        ? <String, dynamic>{}
        : Json.from(jsonDecode(request.body) as Map);
    if (request.url.path.endsWith('/login')) {
      return http.Response(
        jsonEncode({
          'access_token': 'access',
          'refresh_token': 'refresh',
          'device_id': 'device',
        }),
        200,
      );
    }
    if (request.method == 'GET') {
      return http.Response(
        jsonEncode({
          'metadata': metadata,
          'metadata_version': metadataVersion,
          'items': items.values.toList(),
        }),
        200,
      );
    }
    final op = data['operation_id'] as String;
    Json result;
    if (operations.containsKey(op)) {
      result = operations[op]!;
    } else if (request.url.path.endsWith('/metadata')) {
      if (data['base_version'] != metadataVersion) {
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'conflict',
              'current': {'payload': metadata, 'version': metadataVersion},
            },
          }),
          409,
        );
      }
      metadata = Json.from(data['payload'] as Map);
      metadataVersion++;
      result = {'version': metadataVersion};
      operations[op] = result;
    } else {
      final id = request.url.pathSegments.last;
      final current = items[id];
      if (data['base_version'] != (current?['version'] ?? 0) ||
          (current?['deleted'] == true && data['deleted'] != true)) {
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'conflict',
              'current':
                  current ??
                  {
                    'id': id,
                    'version': 0,
                    'deleted': false,
                    'payload': null,
                    'updated_at': null,
                  },
            },
          }),
          409,
        );
      }
      result = {
        'id': id,
        'version': (current?['version'] ?? 0) + 1,
        'deleted': data['deleted'],
        'payload': data['payload'],
        'updated_at': '2026-10-09T00:00:00Z',
      };
      items[id] = result;
      operations[op] = result;
    }
    if (loseReply) {
      loseReply = false;
      throw http.ClientException('response lost');
    }
    return http.Response(jsonEncode(result), 200);
  });
}

Future<SyncService> device(FakeServer server) async {
  final store = await VaultStore.open(
    await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    ),
  );
  await store.initialize(await store.crypto.create('test-master-password'));
  final api = ApiClient(
    Uri.parse('https://vault.example.com'),
    MemorySessionStorage(),
    client: server.client(),
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
  test('双客户端离线冲突、保留两份、响应丢失重试与删除传播', () async {
    final server = FakeServer();
    final first = await device(server), second = await device(server);
    final id = await first.store.save('password', {
      'name': 'Account',
      'password': 'initial',
    });
    await first.sync();
    await second.mergeRemote(
      'test-master-password',
      recovery: false,
      mergeLocal: false,
    );
    await second.sync();
    expect(second.store.records.single['password'], 'initial');
    server.offline = true;
    await first.store.save('password', {
      'name': 'Account',
      'password': 'local-edit',
    }, id: id);
    await expectLater(first.sync(), throwsA(isA<Exception>()));
    expect((await first.store.db.query('items')).single['pending'], 1);
    await second.store.save('password', {
      'name': 'Account',
      'password': 'other-edit',
    }, id: id);
    server.offline = false;
    await second.sync();
    await first.sync();
    expect(first.conflicts, hasLength(1));
    await first.resolve(id, ConflictChoice.both);
    await first.sync();
    await second.sync();
    expect(
      second.store.records.map((r) => r['password']),
      containsAll(['local-edit', 'other-edit']),
    );
    final newId = await first.store.save('password', {
      'name': 'Retry',
      'password': 'retry',
    });
    server.loseReply = true;
    await expectLater(first.sync(), throwsA(isA<Exception>()));
    await first.sync();
    expect(server.items[newId]!['version'], 1);
    await first.store.delete(id);
    await first.sync();
    await second.sync();
    expect(second.store.records.any((r) => r['id'] == id), isFalse);
    expect(server.items[id]!['deleted'], isTrue);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('冲突后再次编辑需重新确认，保留两份保存最新本地内容', () async {
    final server = FakeServer();
    final service = await device(server);
    final store = service.store;
    final id = await store.save('password', {
      'name': 'Account',
      'password': 'initial',
    });
    await service.sync();
    server.items[id] = {
      ...server.items[id]!,
      'version': 2,
      'payload': await store.encryptRecord(id, {
        'kind': 'password',
        'name': 'Account',
        'password': 'cloud-edit',
      }),
    };
    await store.save('password', {
      'name': 'Account',
      'password': 'local-edit',
    }, id: id);
    await service.sync();
    expect(service.conflicts, hasLength(1));
    await store.save('password', {
      'name': 'Account',
      'password': 'newest-local-edit',
    }, id: id);
    await expectLater(
      service.resolve(id, ConflictChoice.both),
      throwsStateError,
    );
    expect(store.records.single['password'], 'newest-local-edit');
    expect(service.conflicts, hasLength(1));
    await service.resolve(id, ConflictChoice.both);
    await service.sync();
    expect(
      store.records.map((row) => row['password']),
      containsAll(['newest-local-edit', 'cloud-edit']),
    );
    expect(
      store.records.map((row) => row['password']),
      isNot(contains('local-edit')),
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  for (final choice in ConflictChoice.values) {
    test(
      '缺失云端条目 version0/payloadnull 冲突可处理：${choice.name}',
      () async {
        final server = FakeServer();
        final service = await device(server);
        final store = service.store;
        final id = await store.save('password', {
          'name': 'Account',
          'password': 'initial',
        });
        await service.sync();
        server.items.remove(id);
        await store.save('password', {
          'name': 'Account',
          'password': 'preserved-local',
        }, id: id);
        await service.sync();
        expect(service.conflicts.single.remote, {
          'id': id,
          'version': 0,
          'deleted': false,
          'payload': null,
          'updated_at': null,
        });
        await service.resolve(id, choice);
        await service.sync();
        expect(service.conflicts, isEmpty);
        if (choice == ConflictChoice.cloud) {
          expect(store.records, isEmpty);
          expect(server.items, isEmpty);
        } else {
          expect(store.records.single['password'], 'preserved-local');
          expect(server.items[id]!['version'], 1);
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }

  test('恢复元数据与待上传操作原子保存，失败全部回滚', () async {
    final service = await device(FakeServer());
    final store = service.store;
    final previousMetadata = await store.config('metadata');
    final previousVersion = await store.config('metadata_version');
    final previousOperation = await store.config('metadata_operation');
    final setup = await store.prepareChange(
      'test-master-password',
      'new-recovery-password',
    );
    await store.db.execute("""
      CREATE TRIGGER reject_metadata_operation BEFORE INSERT ON config
      WHEN NEW.key = 'metadata_operation'
      BEGIN SELECT RAISE(ABORT, 'injected persistence failure'); END
    """);
    try {
      await expectLater(
        store.adoptRemote(
          setup.metadata,
          [],
          setup.key,
          mergeLocal: false,
          version: 7,
          metadataPending: true,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.config('metadata'), previousMetadata);
      expect(await store.config('metadata_version'), previousVersion);
      expect(await store.config('metadata_operation'), previousOperation);
      await store.db.execute('DROP TRIGGER reject_metadata_operation');
      final fresh = await store.prepareChange(
        'test-master-password',
        'new-recovery-password',
      );
      await store.save('password', {
        'name': 'Recovery validation',
        'password': 'preserved-secret',
      });
      await store.adoptRemote(
        fresh.metadata,
        [],
        fresh.key,
        mergeLocal: true,
        version: 7,
        metadataPending: true,
      );
      final reopened = await VaultStore.open(store.db);
      expect(await reopened.config('metadata'), jsonEncode(fresh.metadata));
      await reopened.unlock('new-recovery-password');
      expect(reopened.records.single['password'], 'preserved-secret');
      reopened.lock();
      expect(await reopened.config('metadata_version'), '7');
      expect(await reopened.config('metadata_operation'), isNotNull);
      expect(
        await reopened.config('metadata_operation'),
        isNot(previousOperation),
      );
    } catch (_) {
      setup.key.destroy();
      rethrow;
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('修改主密码触发 onMutation 并保留待上传元数据', () async {
    final server = FakeServer();
    final service = await device(server);
    await service.sync();
    var mutations = 0;
    service.store.onMutation = () => mutations++;
    final setup = await service.store.prepareChange(
      'test-master-password',
      'new-master-password',
    );
    await service.store.applyChange(setup);
    expect(mutations, 1);
    expect(await service.store.config('metadata_operation'), isNotNull);
    await service.sync();
    expect(server.metadata, setup.metadata);
    expect(server.metadataVersion, 2);
    expect(await service.store.config('metadata_operation'), isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('恢复合并的网络失败销毁尚未接管的密钥，保留本地密码箱', () async {
    final server = FakeServer();
    final service = await device(server);
    await service.sync();
    final previous = await service.store.config('metadata');
    final setup = await service.store.prepareChange(
      'test-master-password',
      'new-recovery-password',
    );
    server.offline = true;
    await expectLater(
      service.mergeRemote(
        '',
        recovery: true,
        mergeLocal: false,
        recoverySetup: RemoteRecovery(setup, 1),
      ),
      throwsA(isA<Exception>()),
    );
    expect(setup.key.isDestroyed, isTrue);
    expect(service.store.unlocked, isTrue);
    expect(await service.store.config('metadata'), previous);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
