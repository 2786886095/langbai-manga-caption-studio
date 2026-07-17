import 'package:bubble_caption_studio/src/text_context_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  });

  testWidgets(
    'web right-click opens the Flutter text editing menu',
    (tester) async {
      final controller = TextEditingController(text: '浏览器右键测试');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              contextMenuBuilder: buildAppTextContextMenu,
            ),
          ),
        ),
      );

      final location = tester.getCenter(find.byType(TextField));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: location);
      await gesture.down(location);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(BrowserContextMenu.enabled, isFalse);
      expect(find.text('剪切'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('粘贴'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
    },
    skip: !kIsWeb,
  );
}
