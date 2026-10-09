import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keybox/ui.dart';
import 'package:keybox/vault/vault_page.dart';

void main() {
  testWidgets('密码箱在上下边界拖动时保持内容比例，列表仍能滚动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: keyBoxTheme().copyWith(platform: TargetPlatform.android),
        home: const Scaffold(body: VaultPage()),
      ),
    );
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;

    Future<void> checkBoundary(Offset delta) async {
      final avatar = find.byType(ServiceAvatar).first;
      final box = tester.renderObject<RenderBox>(avatar);
      double paintedHeight() =>
          (box.localToGlobal(Offset(0, box.size.height)) -
                  box.localToGlobal(Offset.zero))
              .distance;
      final height = paintedHeight();
      final gesture = await tester.startGesture(const Offset(180, 350));
      await gesture.moveBy(Offset(0, delta.dy.sign * 30));
      await tester.pump();
      await gesture.moveBy(delta);
      await tester.pump(const Duration(milliseconds: 100));
      expect(paintedHeight(), closeTo(height, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await checkBoundary(const Offset(0, 200));
    await tester.drag(scrollable, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await checkBoundary(const Offset(0, -200));
    expect(tester.takeException(), isNull);
  });
}
