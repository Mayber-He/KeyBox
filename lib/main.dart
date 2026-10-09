import 'package:flutter/material.dart';
import 'app.dart';
import 'core/vault_store.dart';
import 'package:sqflite/sqflite.dart';
import 'sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await openDatabase('${await getDatabasesPath()}/keybox.db');
    final store = await VaultStore.open(db);
    final sync = SyncService(store);
    await sync.load();
    runApp(KeyBoxApp(store: store, sync: sync));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('无法打开本地密码箱。请保留应用数据，检查存储空间后重试。'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
