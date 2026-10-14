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
import 'package:bubble_caption_studio/src/app_localization.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/bubble_text_editor.dart';
import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/page_collection.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/project_store.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/text_layout_service.dart';
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
  test('manual and automatic controls and feedback have localized labels', () {
    expect(tr('手动挡', languageCode: 'en'), 'Manual');
    expect(tr('自动挡', languageCode: 'en'), 'Auto');
    expect(tr('自动挡', languageCode: 'ja'), '自動');
    expect(tr('手动挡', languageCode: 'ko'), '수동');
    expect(tr('自动挡', languageCode: 'zh_TW'), '自動檔');
    expect(
        trArgs('自动挡 · 上限 {limit} · 实际字号 {size}', {'limit': 200, 'size': '38.5'},
            languageCode: 'en'),
        'Auto · maximum 200 · actual size 38.5');
    expect(
        trArgs('自动挡：最小字号 {min} 仍超框，请扩大文字框或精简文字', {'min': 8},
            languageCode: 'en'),
        contains('minimum size 8'));
  });
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
      expect(current().page.placements.single.fontSize, 200);
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fit);
      expect(current().selectedIndex, 0);
      if (portrait) {
        await tester.tap(find.byTooltip('元素属性'));
        await pumpUi();
      }
      expect(find.text('文字属性'), findsWidgets);
      expect(find.text('描边粗细'), findsNothing);
      expect(find.text('白底透明度'), findsNothing);
      expect(find.text('手动挡'), findsOneWidget);
      expect(find.text('自动挡'), findsOneWidget);
      expect(find.text('字体大小'), findsNothing);
      final editor = find.descendant(
          of: find.byType(BubbleTextEditor), matching: find.byType(TextField));
      const text = '纯文字测试：冒号前后全部保留';
      await tester.enterText(editor, text);
      await tester.pump();
      expect(current().page.placements.single.caption.text, text);
      expect(buildBcsScript([current().page]), contains('@气泡=纯文字'));
      final automaticLayout =
          const TextLayoutService().layout(current().page.placements.single);
      final visibleSize = automaticLayout.effectiveFontSize;
      automaticLayout.dispose();
      await tester.ensureVisible(find.text('手动挡'));
      await tester.tap(find.text('手动挡'));
      await tester.pump();
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fixed);
      expect(current().page.placements.single.fontSize,
          closeTo(visibleSize, .001));
      final fontRow = find
          .ancestor(of: find.text('字体大小'), matching: find.byType(Row))
          .first;
      final fontSlider = tester.widget<Slider>(
          find.descendant(of: fontRow, matching: find.byType(Slider)));
      fontSlider.onChangeStart?.call(42);
      fontSlider.onChanged!(42);
      fontSlider.onChangeEnd?.call(42);
      await tester.pump();
      expect(current().page.placements.single.fontSize, 42);
      await tester.ensureVisible(fontRow);
      await tester.tap(find.descendant(of: fontRow, matching: find.text('42')));
      await tester.pump();
      final numericDialog = find.byType(AlertDialog);
      await tester.enterText(
          find.descendant(of: numericDialog, matching: find.byType(TextField)),
          '37');
      await tester.tap(find.descendant(
          of: numericDialog,
          matching: find.widgetWithText(FilledButton, '应用')));
      await pumpUi();
      expect(current().page.placements.single.fontSize, 37);
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fixed);
      // Existing Reset still rearranges geometry; it must not reset manual size.
      await tester.ensureVisible(find.text('重置'));
      await tester.tap(find.text('重置'));
      await tester.pump();
      expect(current().page.placements.single.fontSize, 37);
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fixed);
      await tester.ensureVisible(find.text('自动挡'));
      await tester.tap(find.text('自动挡'));
      await tester.pump();
      expect(current().page.placements.single.fontSize, 200);
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fit);
      expect(find.text('字体大小'), findsNothing);
      final unchangedScript = buildBcsScript([current().page]);
      final modes = tester.widget<SegmentedButton<TextSizeMode>>(
          find.byType(SegmentedButton<TextSizeMode>));
      modes.onSelectionChanged!({TextSizeMode.fit});
      modes.onSelectionChanged!({TextSizeMode.fit});
      await tester.pump();
      expect(buildBcsScript([current().page]), unchangedScript);
      // One Undo must undo the mode change, not a repeated no-op selection.
      final undo = tester.widget<IconButton>(find
          .byWidgetPredicate((widget) =>
              widget is IconButton &&
              (widget.tooltip?.startsWith('撤销') ?? false))
          .first);
      undo.onPressed!();
      await tester.pump();
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fixed);
      expect(current().page.placements.single.fontSize, 37);
      final redo = tester.widget<IconButton>(find
          .byWidgetPredicate((widget) =>
              widget is IconButton &&
              (widget.tooltip?.startsWith('重做') ?? false))
          .first);
      redo.onPressed!();
      await tester.pump();
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fit);
      expect(current().page.placements.single.fontSize, 200);
      if (portrait) {
        // Undo/redo clears selection, so the empty sheet has no inspector Close
        // button. Dismiss through its normal outside barrier in that state.
        if (find.byTooltip('关闭属性面板').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('关闭属性面板').last);
        } else {
          await tester.tapAt(Offset(size.width / 2, 8));
        }
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
      expect(current().page.placements.single.textSizeMode, TextSizeMode.fit);
      expect(current().page.placements.single.fontSize, 200);
      if (find.byTooltip('添加气泡或文字').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('添加气泡或文字'));
        await pumpUi();
        await tester.tap(find.text('添加气泡').last);
      } else {
        await tester.tap(find.text('添加气泡').first);
      }
      await pumpUi();
      expect(current().page.placements.last.shape, BubbleShape.ellipse);
      expect(current().page.placements.last.fontSize, 200);
      expect(current().page.placements.last.textSizeMode, TextSizeMode.fit);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
