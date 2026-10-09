import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:keybox/app.dart';
import 'package:keybox/core/vault_store.dart';

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
}
