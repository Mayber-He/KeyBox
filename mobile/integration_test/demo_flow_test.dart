import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:keybox/app.dart';
import 'package:keybox/core/vault_store.dart';
import 'package:keybox/sync/api_client.dart';
import 'package:keybox/backup/backup_codec.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => binding.testTextInput.register());
  tearDown(() => binding.testTextInput.unregister());
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(finder, findsWidgets);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final ancestors = find.ancestor(
      of: finder,
      matching: find.byType(Scrollable),
    );
    for (
      var i = 0;
      i < 8 &&
          finder.hitTestable().evaluate().isEmpty &&
          ancestors.evaluate().isNotEmpty;
      i++
    ) {
      await tester.drag(ancestors.first, const Offset(0, -100));
      await tester.pumpAndSettle();
    }
    expect(finder.hitTestable(), findsWidgets);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<VaultStore> fixture() async {
    final db = await openDatabase(inMemoryDatabasePath);
    final store = await VaultStore.open(db);
    await store.initialize(await store.crypto.create('test-master-password'));
    return store;
  }

  testWidgets('真实设置、加密保存、详情复制、后台锁定与重新解锁', (tester) async {
    final db = await openDatabase(inMemoryDatabasePath);
    final store = await VaultStore.open(db);
    addTearDown(() async {
      store.lock();
      await db.close();
    });
    await tester.pumpWidget(KeyBoxApp(store: store));
    await tester.pumpAndSettle();
    await tap(tester, find.text('设置主密码').last);
    await tap(tester, find.text('生成恢复密钥'));
    expect(find.text('主密码至少 12 个字符'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test-master-password',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'test-master-password',
    );
    await tap(tester, find.text('生成恢复密钥'));
    await waitFor(tester, find.text('我已保存恢复密钥'));
    expect(find.byType(SelectableText), findsOneWidget);
    await tap(tester, find.byType(CheckboxListTile));
    await tap(tester, find.text('完成设置'));
    await waitFor(tester, find.byTooltip('添加密码'));
    await tap(tester, find.byTooltip('添加密码'));
    await tester.enterText(find.byType(TextFormField).at(0), 'PrivateTest');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'account@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'Secret-Test-123');
    await tap(tester, find.text('保存条目'));
    await waitFor(tester, find.text('PrivateTest'));
    expect(
      (await db.query('items')).toString(),
      isNot(contains('Secret-Test-123')),
    );
    await tap(tester, find.text('PrivateTest'));
    await tap(tester, find.byTooltip('显示密码'));
    expect(find.text('Secret-Test-123'), findsOneWidget);
    await tap(tester, find.byTooltip('复制密码'));
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      'Secret-Test-123',
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(store.unlocked, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Secret-Test-123'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'wrong-password');
    await tap(tester, find.text('解锁密码箱'));
    await waitFor(tester, find.text('主密码不正确，或加密数据无法验证'));
    await tester.enterText(find.byType(TextFormField), 'test-master-password');
    await tap(tester, find.text('解锁密码箱'));
    await waitFor(tester, find.text('PrivateTest'));
    await tap(tester, find.text('PrivateTest'));
    await tap(tester, find.text('删除条目'));
    await tap(tester, find.text('取消'));
    await tap(tester, find.text('删除条目'));
    await tap(tester, find.text('删除').last);
    await waitFor(tester, find.byTooltip('添加密码'));
    expect(store.records, isEmpty);
  });
  testWidgets('320dp 双倍字体、真实验证码表单与搜索标签状态', (tester) async {
    final store = await fixture();
    addTearDown(() async {
      store.lock();
      await store.db.close();
    });
    await binding.setSurfaceSize(const Size(320, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await binding.setSurfaceSize(null);
    });
    await store.save('otp', {
      'name': 'GitHub',
      'account': 'test@example.com',
      'secret': 'JBSWY3DPEHPK3PXP',
      'digits': 8,
      'algorithm': 'SHA256',
      'period': 30,
    });
    await tester.pumpWidget(KeyBoxApp(store: store));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'no-result');
    await tap(tester, find.text('验证码').last);
    expect(find.text('GitHub'), findsOneWidget);
    await tap(tester, find.text('GitHub'));
    await tap(tester, find.text('保存条目'));
    await waitFor(tester, find.text('GitHub'));
    expect(find.text('编辑验证码'), findsNothing);
    await tap(tester, find.byTooltip('复制验证码'));
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      matches(RegExp(r'^\d{8}$')),
    );
    await tap(tester, find.text('密码箱').last);
    expect(find.text('no-result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Android 安全存储与加密备份恢复', (tester) async {
    final storage = SecureSessionStorage();
    await storage.write('{"refresh_token":"fictional-test-token"}');
    expect(await storage.read(), contains('fictional-test-token'));
    await storage.write(null);
    expect(await storage.read(), isNull);
    final store = await fixture();
    addTearDown(() async {
      store.lock();
      await store.db.close();
    });
    await store.save('password', {
      'name': 'RestoreTest',
      'password': 'fictional-backup-password',
    });
    final codec = BackupCodec(store);
    final encrypted = await codec.export('fictional-export-password');
    store.lock();
    await store.unlock('test-master-password');
    expect(await codec.import(encrypted, 'fictional-export-password'), 1);
    expect(store.records, hasLength(2));
    expect(store.records.map((item) => item['id']).toSet(), hasLength(2));
    await tester.pumpWidget(KeyBoxApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('RestoreTest'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
