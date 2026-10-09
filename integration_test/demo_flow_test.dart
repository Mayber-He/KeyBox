import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybox/app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Keep platform IME updates from overwriting text injected by enterText.
  setUp(() => binding.testTextInput.register());
  tearDown(() => binding.testTextInput.unregister());

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
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const KeyBoxApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'demo');
    await tap(tester, find.text('解锁密码箱'));
  }

  testWidgets('演示密码与验证码完成新增编辑删除，标签保留搜索，配置不连接服务器', (tester) async {
    await tester.pumpWidget(const KeyBoxApp());
    await tester.pumpAndSettle();
    await tap(tester, find.text('解锁密码箱'));
    expect(find.text('请输入任意非空内容以进入演示'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'demo');
    await tap(tester, find.text('解锁密码箱'));

    await tap(tester, find.byTooltip('添加密码'));
    await tap(tester, find.text('保存条目'));
    expect(find.text('请填写名称'), findsOneWidget);
    expect(find.text('请填写密码'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'DemoTest');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'demo@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'Demo-Test-123');
    await tap(tester, find.text('保存条目'));
    expect(find.text('7 个账号 · 仅用于演示'), findsOneWidget);
    await tap(tester, find.text('DemoTest'));
    await tap(tester, find.byTooltip('显示密码'));
    expect(find.text('Demo-Test-123'), findsOneWidget);
    await tap(tester, find.byTooltip('复制密码'));
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      'Demo-Test-123',
    );
    await tap(tester, find.text('编辑'));
    await tester.enterText(find.byType(TextFormField).first, 'DemoEdited');
    await tap(tester, find.text('保存条目'));
    expect(find.text('DemoEdited'), findsOneWidget);
    expect(find.text('Demo-Test-123'), findsNothing);
    await tap(tester, find.text('删除条目'));
    await tap(tester, find.text('取消'));
    expect(find.text('DemoEdited'), findsOneWidget);
    await tap(tester, find.text('删除条目'));
    await tap(tester, find.text('删除'));
    expect(find.text('DemoEdited'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('6 个账号 · 仅用于演示'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'GitHub');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'GitHub',
      ),
      findsOneWidget,
    );
    expect(find.text('Gmail'), findsNothing);
    await tap(tester, find.text('验证码').last);
    await tap(tester, find.text('密码箱').last);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'GitHub',
    );
    await tester.enterText(find.byType(TextField), 'not-a-real-entry');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关条目'), findsOneWidget);
    await tap(tester, find.byTooltip('清除搜索'));

    await tap(tester, find.text('验证码').last);
    await tap(tester, find.byTooltip('添加验证码'));
    await tap(tester, find.text('扫描二维码'));
    expect(find.text('扫码功能尚未接入'), findsOneWidget);
    await tap(tester, find.text('保存条目'));
    expect(find.text('请填写服务名称'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'DemoOtp');
    await tester.enterText(find.byType(TextFormField).at(1), 'otp@example.com');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'DEMO_SECRET_ONLY',
    );
    await tap(tester, find.text('保存条目'));
    expect(find.text('DemoOtp'), findsOneWidget);
    await tap(tester, find.byTooltip('复制验证码').first);
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      matches(r'^\d{6}$'),
    );
    await tap(tester, find.byTooltip('验证码操作').first);
    await tap(tester, find.text('编辑'));
    await tester.enterText(find.byType(TextFormField).first, 'DemoOtpEdited');
    await tap(tester, find.text('保存条目'));
    expect(find.text('DemoOtpEdited'), findsOneWidget);
    await tap(tester, find.byTooltip('验证码操作').first);
    await tap(tester, find.text('删除'));
    await tap(tester, find.text('删除'));
    expect(find.text('DemoOtpEdited'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not-a-real-token');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关条目'), findsOneWidget);
    await tap(tester, find.byTooltip('清除搜索'));

    await tap(tester, find.text('设置').last);
    await tap(tester, find.text('连接自己的服务器'));
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, '');
    await tap(tester, find.text('确认演示配置'));
    expect(find.text('请填写完整的 HTTPS 地址'), findsOneWidget);
    expect(find.text('请填写演示令牌'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'demo-token');
    await tap(tester, find.text('确认演示配置'));
    expect(find.text('演示配置已确认，未连接服务器'), findsOneWidget);
    await tap(tester, find.text('连接自己的服务器'));
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller
          ?.text,
      'https://vault.example.com',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller
          ?.text,
      'demo-token-only',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('320dp 小屏与双倍字体可显示验证码和编辑表单', (tester) async {
    await binding.setSurfaceSize(const Size(320, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() => binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await unlock(tester);
    await tap(tester, find.text('验证码').last);
    expect(find.byTooltip('复制验证码'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tap(tester, find.byTooltip('添加验证码'));
    await tester.enterText(find.byType(TextFormField).at(0), 'SmallScreen');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'demo@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'DEMO_SECRET_ONLY',
    );
    await tap(tester, find.text('保存条目'));
    expect(find.text('SmallScreen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
