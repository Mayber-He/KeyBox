import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keybox/core/vault_store.dart';
import 'package:keybox/sync/api_client.dart';
import 'package:keybox/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Opt in with a fresh isolated server/account: sync-live-test and syncPassword.
// Example: flutter test --no-pub test/sync_live_test.dart
//   --dart-define=KEYBOX_TEST_SERVER=http://127.0.0.1:18765
const serverAddress = String.fromEnvironment('KEYBOX_TEST_SERVER');
const syncPassword = 'fictional-sync-password-2026';
const masterPassword = 'fictional-master-password-2026';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This opt-in suite deliberately exercises a local HTTP server.
  HttpOverrides.global = null;
  sqfliteFfiInit();

  test(
    '真实 HTTP 双客户端同步、离线重连、冲突、刷新及设备撤销',
    () async {
      final services = <SyncService>[];
      addTearDown(() async {
        for (final service in services) {
          service.dispose();
          service.store.lock();
          await service.store.db.close();
        }
      });

      Future<SyncService> device() async {
        final store = await VaultStore.open(
          await databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(singleInstance: false),
          ),
        );
        await store.initialize(await store.crypto.create(masterPassword));
        final api = ApiClient(
          Uri.parse(serverAddress),
          MemorySessionStorage(),
          allowLocalHttp: true,
        );
        await api.login('sync-live-test', syncPassword);
        final service = SyncService(store, api: api);
        // Explicit sync barriers make the concurrency assertions deterministic.
        store.onMutation = null;
        services.add(service);
        return service;
      }

      final first = await device(), second = await device();
      final id = await first.store.save('password', {
        'name': 'LIVE_PRIVATE_ACCOUNT_62',
        'password': 'LIVE_PRIVATE_PASSWORD_62',
      });
      await first.sync();
      await second.mergeRemote(
        masterPassword,
        recovery: false,
        mergeLocal: false,
      );
      await second.sync();
      expect(
        second.store.records.single['password'],
        'LIVE_PRIVATE_PASSWORD_62',
      );

      final otpId = await second.store.save('otp', {
        'name': 'LIVE_PRIVATE_OTP_62',
        'account': 'LIVE_PRIVATE_OTP_ACCOUNT_62',
        'secret': 'JBSWY3DPEHPK3PXP',
      });
      await second.sync();
      await first.sync();
      expect(
        first.store.records.singleWhere((row) => row['id'] == otpId)['secret'],
        'JBSWY3DPEHPK3PXP',
      );
      await second.store.save('password', {
        'name': 'LIVE_PRIVATE_ACCOUNT_62',
        'password': 'LIVE_PRIVATE_EDIT_62',
      }, id: id);
      await second.sync();
      await first.sync();
      expect(
        first.store.records.singleWhere((row) => row['id'] == id)['password'],
        'LIVE_PRIVATE_EDIT_62',
      );

      // Closing the transport exercises a real offline request without a mock server.
      first.api!.close();
      final offlineId = await first.store.save('password', {
        'name': 'LIVE_PRIVATE_OFFLINE_62',
        'password': 'LIVE_PRIVATE_OFFLINE_PASSWORD_62',
      });
      await expectLater(first.sync(), throwsA(isA<Exception>()));
      final pending = await first.store.db.query(
        'items',
        where: 'id = ?',
        whereArgs: [offlineId],
      );
      expect(pending.single['pending'], 1);
      expect(pending.single['operation_id'], isNotNull);
      final reconnected = ApiClient(
        Uri.parse(serverAddress),
        MemorySessionStorage(),
        allowLocalHttp: true,
      );
      await reconnected.login('sync-live-test', syncPassword);
      first.api = reconnected;
      await first.sync();
      await second.sync();
      expect(
        second.store.records.singleWhere(
          (row) => row['id'] == offlineId,
        )['password'],
        'LIVE_PRIVATE_OFFLINE_PASSWORD_62',
      );

      await first.store.save('password', {
        'name': 'LIVE_PRIVATE_ACCOUNT_62',
        'password': 'LIVE_PRIVATE_CONFLICT_A_62',
      }, id: id);
      await second.store.save('password', {
        'name': 'LIVE_PRIVATE_ACCOUNT_62',
        'password': 'LIVE_PRIVATE_CONFLICT_B_62',
      }, id: id);
      await Future.wait([first.sync(), second.sync()]);
      final loser = first.conflicts.isNotEmpty ? first : second;
      expect(first.conflicts.length + second.conflicts.length, 1);
      await loser.resolve(id, ConflictChoice.both);
      await loser.sync();
      await first.sync();
      await second.sync();
      for (final service in services) {
        expect(
          service.store.records.map((row) => row['password']),
          containsAll([
            'LIVE_PRIVATE_CONFLICT_A_62',
            'LIVE_PRIVATE_CONFLICT_B_62',
          ]),
        );
      }

      await first.store.delete(otpId);
      await first.sync();
      await second.sync();
      expect(second.store.records.any((row) => row['id'] == otpId), isFalse);
      await second.store.delete(offlineId);
      await second.sync();
      await first.sync();
      expect(first.store.records.any((row) => row['id'] == offlineId), isFalse);

      final previousSession = await first.api!.storage.read();
      final deviceId = first.api!.deviceId;
      final restored = ApiClient(
        Uri.parse(serverAddress),
        first.api!.storage,
        allowLocalHttp: true,
      );
      first.api!.close();
      await restored.restore();
      first.api = restored;
      await first
          .sync(); // An unloaded access token forces actual server refresh.
      expect(restored.deviceId, deviceId);
      expect(
        jsonDecode((await restored.storage.read())!)['refresh_token'],
        isNot(jsonDecode(previousSession!)['refresh_token']),
      );
      final devices = await second.api!.request('GET', '/devices') as List;
      expect(devices.any((row) => row['id'] == deviceId), isTrue);
      await second.api!.request('DELETE', '/devices/$deviceId');
      await expectLater(
        first.sync(),
        throwsA(isA<ApiError>().having((error) => error.status, 'status', 401)),
      );
      expect(first.connected, isFalse);
      expect(first.store.records, isNotEmpty);
    },
    skip: serverAddress.isEmpty,
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
