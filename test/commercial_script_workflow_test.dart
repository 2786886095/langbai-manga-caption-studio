import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/app_theme.dart';
import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/project_store.dart';
import 'package:bubble_caption_studio/src/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Only the test's fresh temporary directory is reachable through path_provider.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'draft applies text and coordinates atomically; bound images survive whole-project undo/redo',
      (tester) async {
    const projectId = 'commercial-script-move-fixture';
    await _bootFixture(tester, projectId);
    final original = _current(tester).page.placements.single;
    await _expectBoundImage(tester, _current(tester).page, x: 120, y: 120);
    final editor = await _openDraft(tester);
    final draft = tester.widget<TextField>(editor).controller!.text;
    expect(draft, contains('@矩形=100,100,200,100'));
    expect(draft, contains('@字号模式=固定'));
    expect(draft, contains('[图片 2]'));
    expect(draft, isNot(contains('sticker')));
    await tester.enterText(
        editor,
        draft
            .replaceFirst('@矩形=100,100,200,100', '@矩形=150,100,200,100')
            .replaceFirst('SCRIPT_BEFORE', 'SCRIPT_AFTER')
            .replaceFirst('SECOND_BEFORE', 'SECOND_AFTER'));
    await tester.tap(find.text('应用字幕变更'));
    await _waitForEdits(tester, projectId, text: 'SCRIPT_AFTER', x: 150);
    await _drive(tester);

    final applied = _current(tester).page;
    final bubble = applied.placements.single;
    expect(bubble.caption.text, 'SCRIPT_AFTER');
    expect(applied.captions.single.text, 'SCRIPT_AFTER');
    expect(bubble.x, 150);
    expect(bubble.y, 100);
    expect(bubble.width, 200);
    expect(bubble.height, 100);
    expect(bubble.textSizeMode, TextSizeMode.fixed);
    expect(bubble.fontSize, original.fontSize);
    expect(bubble.fontFamily, original.fontFamily);
    expect(bubble.shape, original.shape);
    await _expectBoundImage(tester, applied, x: 170, y: 120);
    await _selectPage(tester, '2.png');
    expect(
        _current(tester).page.placements.single.caption.text, 'SECOND_AFTER');
    await _expectBoundImage(tester, _current(tester).page, x: 30, y: 35);

    await _tapHistory(tester, Icons.undo);
    final undone = _current(tester).page;
    expect(undone.name, '1.png');
    expect(undone.placements.single.caption.text, 'SCRIPT_BEFORE');
    expect(undone.placements.single.x, 100);
    expect(undone.placements.single.shape, original.shape);
    expect(undone.placements.single.textSizeMode, TextSizeMode.fixed);
    await _expectBoundImage(tester, undone, x: 120, y: 120);
    await _selectPage(tester, '2.png');
    expect(
        _current(tester).page.placements.single.caption.text, 'SECOND_BEFORE');
    await _expectBoundImage(tester, _current(tester).page, x: 30, y: 35);
    await _waitForEdits(tester, projectId, text: 'SCRIPT_BEFORE', x: 100);

    await _tapHistory(tester, Icons.redo);
    final redone = _current(tester).page;
    expect(redone.name, '1.png');
    expect(redone.placements.single.caption.text, 'SCRIPT_AFTER');
    expect(redone.placements.single.x, 150);
    expect(redone.placements.single.shape, original.shape);
    expect(redone.placements.single.textSizeMode, TextSizeMode.fixed);
    await _expectBoundImage(tester, redone, x: 170, y: 120);
    await _selectPage(tester, '2.png');
    expect(
        _current(tester).page.placements.single.caption.text, 'SECOND_AFTER');
    await _expectBoundImage(tester, _current(tester).page, x: 30, y: 35);
    await _waitForEdits(tester, projectId, text: 'SCRIPT_AFTER', x: 150);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'conflicting linked-style draft rejects every page before live text geometry or image mutation',
      (tester) async {
    const projectId = 'commercial-script-conflict-fixture';
    final originalManifest =
        await _bootFixture(tester, projectId, linked: true);
    final firstPage = _current(tester).page;
    final editor = await _openDraft(tester);
    final originalDraft = tester.widget<TextField>(editor).controller!.text;
    final sections = originalDraft.split('[图片 2]');
    expect(sections.length, 2);
    final conflict = '${sections[0].replaceFirst('@字号=28', '@字号=32')}'
        '[图片 2]${sections[1].replaceFirst('@字号=28', '@字号=40')}';
    await tester.enterText(
        editor,
        conflict
            .replaceFirst('@矩形=100,100,200,100', '@矩形=150,100,200,100')
            .replaceFirst('SCRIPT_BEFORE', 'MUST_NOT_APPLY')
            .replaceFirst('SECOND_BEFORE', 'ALSO_MUST_NOT_APPLY'));
    await tester.tap(find.text('应用字幕变更'));
    await _until(
        tester, () => find.text('脚本未应用，当前项目保持不变').evaluate().isNotEmpty);
    expect(find.textContaining('有多个不同定义'), findsOneWidget);
    expect(identical(_current(tester).page, firstPage), isTrue);
    expect(firstPage.placements.single.caption.text, 'SCRIPT_BEFORE');
    expect(firstPage.placements.single.x, 100);
    expect(firstPage.placements.single.fontSize, 28);
    await _expectBoundImage(tester, firstPage, x: 120, y: 120);
    await tester.tap(find.text('返回修改'));
    await _drive(tester);

    final reopened = await _openDraft(tester);
    // The draft regenerated from every live page must be byte-for-byte unchanged.
    expect(tester.widget<TextField>(reopened).controller!.text, originalDraft);
    await tester.tap(find.text('取消'));
    await _drive(tester);
    await _selectPage(tester, '2.png');
    final secondPage = _current(tester).page;
    expect(secondPage.placements.single.caption.text, 'SECOND_BEFORE');
    expect(secondPage.placements.single.fontSize, 28);
    expect(secondPage.placements.single.styleId, 'shared-style');
    await _expectBoundImage(tester, secondPage, x: 30, y: 35);
    final manifest =
        await tester.runAsync(() => loadLocalProjectManifest(projectId));
    expect(manifest, originalManifest);
    expect(
        await tester.runAsync(() => loadLocalProjectEdits(projectId)), isNull);
    expect(tester.takeException(), isNull);
  });
}

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

Future<Uint8List> _bootFixture(WidgetTester tester, String projectId,
    {bool linked = false}) async {
  const size = Size(1440, 900);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousPaths = PathProviderPlatform.instance;
  final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bcs-commercial-script-widget-')))!;
  PathProviderPlatform.instance = _IsolatedPaths(directory.path);
  addTearDown(() => PathProviderPlatform.instance = previousPaths);
  final manifest = (await tester.runAsync(() async {
    final source = await _raster(400, 300, Colors.grey);
    final sticker = await _raster(80, 60, Colors.deepOrange);
    final sourceBytes =
        (await source.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    final stickerBytes =
        (await sticker.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    final pages = <ImagePage>[];
    for (var i = 0; i < 2; i++) {
      final id = 'p${i + 1}-b1';
      final caption = CaptionLine(
          speaker: '',
          text: i == 0 ? 'SCRIPT_BEFORE' : 'SECOND_BEFORE',
          bubbleId: id);
      final page = ImagePage(
          name: '${i + 1}.png',
          pageId: 'fixture-page-${i + 1}',
          bytes: sourceBytes,
          image: source.clone());
      page.captions = [caption];
      page.placements = [
        BubblePlacement(
            caption: caption,
            x: i == 0 ? 100 : 20,
            y: i == 0 ? 100 : 20,
            width: i == 0 ? 200 : 180,
            height: i == 0 ? 100 : 90,
            shape: i == 0 ? BubbleShape.ellipse : BubbleShape.rounded,
            fontFamily: 'ZCOOL XiaoWei',
            fontSize: 28,
            textSizeMode: TextSizeMode.fixed,
            styleId: linked ? 'shared-style' : null)
      ];
      page.placedImages = [
        PlacedImage(
            id: 'sticker-${i + 1}',
            name: 'sticker.png',
            bytes: stickerBytes,
            image: sticker.clone(),
            x: i == 0 ? 120 : 30,
            y: i == 0 ? 120 : 35,
            width: i == 0 ? 80 : 40,
            height: i == 0 ? 60 : 30,
            bubbleId: id)
      ];
      pages.add(page);
      await saveLocalProjectImage(projectId, page.pageId, sourceBytes);
      await saveLocalProjectAsset(
          projectId, page.placedImages.single.id, stickerBytes);
    }
    try {
      final encoded =
          encodeProjectManifest(pages, buildBcsScript(pages), revision: 7);
      await saveLocalProjectManifest(projectId, '商业脚本集成测试', encoded,
          revision: 7);
      return encoded;
    } finally {
      for (final page in pages) {
        page.dispose();
      }
      source.dispose();
      sticker.dispose();
    }
  }))!;
  await tester.runAsync(() => tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: WorkspaceScreen(
          projectId: projectId,
          projectName: '商业脚本集成测试',
          onExitToProjects: () {}))));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await _until(tester, () => _canvas.evaluate().isNotEmpty);
  expect(_current(tester).page.originalWidth, 400);
  expect(_current(tester).page.originalHeight, 300);
  expect(tester.takeException(), isNull);
  return manifest;
}

Finder get _canvas => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is PagePainter);
PagePainter _current(WidgetTester tester) =>
    tester.widget<CustomPaint>(_canvas).painter! as PagePainter;

Future<Finder> _openDraft(WidgetTester tester) async {
  await tester.tap(find.text('匹配字幕').hitTestable().first);
  await _drive(tester);
  expect(find.text('当前字幕 / 导入草稿'), findsOneWidget);
  final editor = find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));
  expect(editor, findsOneWidget);
  return editor;
}

Future<void> _selectPage(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).hitTestable().first);
  await _drive(tester);
  expect(_current(tester).page.name, name);
}

Future<void> _tapHistory(WidgetTester tester, IconData icon) async {
  final button = find
      .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
      .hitTestable()
      .first;
  expect(tester.widget<IconButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await _drive(tester);
}

Future<void> _expectBoundImage(WidgetTester tester, ImagePage page,
    {required double x, required double y}) async {
  final placed = page.placedImages.single;
  expect(placed.bubbleId, page.placements.single.caption.bubbleId);
  expect(placed.x, x);
  expect(placed.y, y);
  expect(placed.width, page.name == '1.png' ? 80 : 40);
  expect(placed.height, page.name == '1.png' ? 60 : 30);
  expect(placed.bytes, isNotEmpty);
  // Actually use the native raster handle, not merely persisted descriptors.
  final encoded = await tester
      .runAsync(() => placed.image.toByteData(format: ui.ImageByteFormat.png));
  expect(encoded, isNotNull);
  expect(encoded!.buffer.asUint8List(), placed.bytes);
}

Future<ui.Image> _raster(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<void> _drive(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = Stopwatch()..start();
  while (!done() && deadline.elapsed < const Duration(seconds: 15)) {
    await _drive(tester);
  }
  expect(done(), isTrue, reason: 'bounded real IO/widget completion deadline');
}

Future<void> _waitForEdits(WidgetTester tester, String projectId,
    {required String text, required double x}) async {
  final deadline = Stopwatch()..start();
  bool saved = false;
  while (!saved && deadline.elapsed < const Duration(seconds: 20)) {
    await _drive(tester);
    final bytes = await tester.runAsync(() => loadLocalProjectEdits(projectId));
    if (bytes == null) continue;
    final page =
        (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['pages'][0];
    saved =
        page['captions'][0]['text'] == text && page['placements'][0]['x'] == x;
  }
  expect(saved, isTrue, reason: 'expected durable edits text=$text x=$x');
}
