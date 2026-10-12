import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only platform replacement isolates all writes from real user projects.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:bubble_caption_studio/src/app_theme.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/bubble_text_editor.dart';
import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/page_collection.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/project_store.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/workspace_screen.dart';

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explicit text-only style applies without changing manual geometry', () {
    final old = BubblePlacement(
        caption: const CaptionLine(speaker: '', text: '旧', bubbleId: 'p1-b1'),
        x: 80,
        y: 100,
        width: 400,
        height: 120);
    final captions = parseCaptionScript('''[图片 1]
@原图尺寸=1216x832
@气泡ID=p1-b1
@气泡=纯文字
@颜色=#FF0022
@字号=40
完整正文：保留前半句
''').sections.single.captions;
    final generated = const LayoutEngine()
        .arrange(captions, imageWidth: 1216, imageHeight: 832);
    final result = preserveEditedPlacements([old], generated, captions).single;
    expect(result.shape, BubbleShape.plainText);
    expect(result.fontColorValue, 0xffff0022);
    expect(result.fontSize, 40);
    expect(result.x, old.x);
    expect(result.y, old.y);
    expect(result.width, old.width);
    expect(result.height, old.height);
    expect(result.caption.text, '完整正文：保留前半句');
  });

  for (final size in const [
    Size(1920, 1080),
    Size(1440, 900),
    Size(390, 844),
    Size(844, 390)
  ]) {
    testWidgets('add edit deselect and save plain text at $size',
        (tester) async {
      Future<void> pumpUi() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousPaths = PathProviderPlatform.instance;
      final temp = await tester.runAsync(
          () => Directory.systemTemp.createTemp('bcs-plain-text-widget-'));
      PathProviderPlatform.instance = _IsolatedPaths(temp!.path);
      addTearDown(() {
        PathProviderPlatform.instance = previousPaths;
      });
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 1216, 832), Paint()..color = Colors.grey);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1216, 832);
        picture.dispose();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final page = ImagePage(
            name: '1.png', bytes: png!.buffer.asUint8List(), image: image);
        await saveLocalProjectImage(
            'plain-text-fixture', page.pageId, page.bytes);
        await saveLocalProjectManifest('plain-text-fixture', '纯文字测试',
            encodeProjectManifest([page], buildBcsScript([page])));
        page.dispose();
      });
      await tester.runAsync(() => tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: WorkspaceScreen(
              projectId: 'plain-text-fixture',
              projectName: '纯文字测试',
              onExitToProjects: () {}))));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(tester.takeException(), isNull);
      final isDesktop = size.width >= 1180;
      final portrait = size.height > size.width && !isDesktop;
      if (find.byTooltip('添加文字').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('添加文字'));
      } else {
        await tester.tap(find.byTooltip('添加气泡或文字'));
        await pumpUi();
        await tester.tap(find.text('添加文字').last);
      }
      await pumpUi();
      final canvas = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is PagePainter);
      PagePainter current() =>
          (tester.widget<CustomPaint>(canvas).painter! as PagePainter);
      expect(current().page.placements.single.shape, BubbleShape.plainText);
      expect(current().selectedIndex, 0);
      if (portrait) {
        await tester.tap(find.byTooltip('元素属性'));
        await pumpUi();
      }
      expect(find.text('文字属性'), findsWidgets);
      expect(find.text('描边粗细'), findsNothing);
      expect(find.text('白底透明度'), findsNothing);
      final editor = find.descendant(
          of: find.byType(BubbleTextEditor), matching: find.byType(TextField));
      const text = '纯文字测试：冒号前后全部保留';
      await tester.enterText(editor, text);
      await tester.pump();
      expect(current().page.placements.single.caption.text, text);
      expect(buildBcsScript([current().page]), contains('@气泡=纯文字'));
      if (portrait) {
        await tester.tap(find.byTooltip('关闭属性面板').last);
        await pumpUi();
      }
      final origin = tester.getTopLeft(canvas);
      final dimensions = tester.getSize(canvas);
      await tester
          .tapAt(origin + Offset(dimensions.width - 4, dimensions.height - 4));
      await tester.pump();
      expect(current().selectedIndex, isNull);
      final b = current().page.placements.single;
      await tester.tapAt(origin +
          Offset((b.x + b.width / 2) * dimensions.width / 1216,
              (b.y + b.height / 2) * dimensions.height / 832));
      await tester.pump();
      expect(current().selectedIndex, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      // Native IO completions resume in the widget test's fake-async zone. Each
      // atomic write/history step may require another pump; a fixed 120-pump
      // allowance is not a durable-save deadline. Drive those microtasks while
      // polling the exact on-disk text, with a bounded real-time deadline.
      Uint8List? edits;
      final saveDeadline = Stopwatch()..start();
      while (saveDeadline.elapsed < const Duration(seconds: 15)) {
        for (var round = 0; round < 10; round++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        edits = await tester.runAsync<Uint8List?>(
            () => loadLocalProjectEdits('plain-text-fixture'));
        if (edits != null && utf8.decode(edits).contains(text)) break;
      }
      expect(edits, isNotNull);
      expect(utf8.decode(edits!), contains('plainText'));
      expect(utf8.decode(edits), contains(text));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Reopen through the real manifest + edits loading path rather than only
      // proving that the serialized file contains the edited text.
      await tester.runAsync(() => tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: WorkspaceScreen(
              projectId: 'plain-text-fixture',
              projectName: '纯文字测试',
              onExitToProjects: () {}))));
      final reopenDeadline = Stopwatch()..start();
      while (canvas.evaluate().isEmpty &&
          reopenDeadline.elapsed < const Duration(seconds: 15)) {
        for (var round = 0; round < 10; round++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
      }
      expect(canvas, findsOneWidget);
      expect(current().page.placements.single.caption.text, text);
      expect(current().page.placements.single.shape, BubbleShape.plainText);
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fixed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
