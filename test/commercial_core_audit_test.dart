import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/bubble_text_editor.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/project_document.dart';
import 'package:bubble_caption_studio/src/script_merge.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'font name change clears stale unchanged asset ID but explicit new ID wins',
      () {
    const caption = CaptionLine(speaker: '', text: 'A', bubbleId: 'p1-b1');
    const old = BubblePlacement(
        caption: caption,
        x: 10,
        y: 20,
        width: 100,
        height: 70,
        fontFamily: 'Noto Sans SC',
        fontAssetId: 'old-hash-id',
        fontDisplayName: '思源黑体');
    const baseline = CaptionLine(
        speaker: '',
        text: 'A',
        bubbleId: 'p1-b1',
        layout: CaptionLayoutSpec(
            fontFamily: 'Noto Sans SC', fontAssetId: 'old-hash-id'));
    for (final newId in ['old-hash-id', 'new-hash-id']) {
      final nextCaption = CaptionLine(
          speaker: '',
          text: 'A',
          bubbleId: 'p1-b1',
          layout: CaptionLayoutSpec(
              fontFamily: 'Ma Shan Zheng',
              fontAssetId: newId,
              fontDisplayName: '马善政毛笔体'));
      final incoming = old.copyWith(
          caption: nextCaption,
          fontFamily: 'Ma Shan Zheng',
          fontAssetId: newId,
          fontDisplayName: '马善政毛笔体');
      final result =
          mergeScriptPlacements([old], [incoming], [baseline]).single;
      expect(result.fontFamily, 'Ma Shan Zheng');
      expect(result.fontAssetId, newId == 'old-hash-id' ? null : newId);
    }
  });

  test(
      'one imported linked-style change propagates atomically without changing text or geometry',
      () {
    const caption = CaptionLine(speaker: '', text: 'A', bubbleId: 'p1-b1');
    const first = BubblePlacement(
        caption: caption,
        x: 10,
        y: 20,
        width: 100,
        height: 70,
        styleId: 'shared',
        fontSize: 34);
    final second = first.copyWith(
        x: 200, caption: caption.copyWith(text: 'B', bubbleId: 'p1-b2'));
    final result = mergeLinkedStyleChanges([first, second],
        [first.copyWith(fontSize: 72, textStrokeWidth: 3), second]);
    expect(result.map((b) => b.fontSize), [72, 72]);
    expect(result.map((b) => b.textStrokeWidth), [3, 3]);
    expect(result.map((b) => b.caption.text), ['A', 'B']);
    expect(result.map((b) => b.x), [10, 200]);
    expect(first.fontSize, 34);
    expect(second.fontSize, 34);
  });

  test(
      'conflicting linked-style imports are rejected before changing the document',
      () {
    const caption = CaptionLine(speaker: '', text: 'A', bubbleId: 'p1-b1');
    const first = BubblePlacement(
        caption: caption,
        x: 10,
        y: 20,
        width: 100,
        height: 70,
        styleId: 'shared',
        textSizeMode: TextSizeMode.fixed,
        fontSize: 34);
    final second = first.copyWith(caption: caption.copyWith(bubbleId: 'p1-b2'));
    expect(
        () => mergeLinkedStyleChanges([first, second],
            [first.copyWith(fontSize: 70), second.copyWith(fontSize: 90)]),
        throwsFormatException);
    expect(first.fontSize, 34);
    expect(second.fontSize, 34);
    final textOnly = mergeLinkedStyleChanges([
      first,
      second
    ], [
      first.copyWith(fontSize: 70),
      second.copyWith(fontSize: 90)
    ], applyStyle: false);
    expect(textOnly.map((b) => b.fontSize), [70, 90]);
  });

  test('document projections preserve each page orderRank', () async {
    final pool = DocumentAssetPool();
    final page = await _page()
      ..orderRank = 17;
    final document = _capture(page, pool);
    final projected = document.toPages();
    expect(projected.single.orderRank, 17);
    projected.single.dispose();
    page.dispose();
    pool.dispose();
  });

  test(
      'disposing a save/export projection does not dispose active placed-image pixels',
      () async {
    final pool = DocumentAssetPool();
    final page = await _page();
    final image = await _raster(40, 40);
    final imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    page.placedImages = [
      PlacedImage(
          id: 'sticker-1',
          name: 'sticker.png',
          bytes: imageBytes,
          image: image,
          x: 10,
          y: 10,
          width: 40,
          height: 40)
    ];
    addTearDown(() {
      page.dispose();
      pool.dispose();
    });
    final document = _capture(page, pool);
    final saveProjection = document.toPages();
    saveProjection.single.dispose();
    expect(
        await page.placedImages.single.image
            .toByteData(format: ui.ImageByteFormat.png),
        isNotNull);
    final exportProjection = document.toPages();
    expect(
        await exportProjection.single.placedImages.single.image
            .toByteData(format: ui.ImageByteFormat.png),
        isNotNull);
    exportProjection.single.dispose();
  });

  test(
      'history retains independent placed-image pixels after source page disposal',
      () async {
    final pool = DocumentAssetPool();
    final page = await _page();
    final image = await _raster(40, 40);
    page.placedImages = [
      PlacedImage(
          id: 'sticker-1',
          name: 'sticker.png',
          bytes: (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List(),
          image: image,
          x: 10,
          y: 10,
          width: 40,
          height: 40)
    ];
    final document = _capture(page, pool);
    page.dispose();
    final first = document.toPages();
    expect(
        await first.single.placedImages.single.image
            .toByteData(format: ui.ImageByteFormat.png),
        isNotNull);
    first.single.dispose();
    final second = document.toPages();
    expect(
        await second.single.placedImages.single.image
            .toByteData(format: ui.ImageByteFormat.png),
        isNotNull);
    second.single.dispose();
    pool.dispose();
  });

  for (final entry in const {
    '@坐标=50%,40%\n@尺寸=25%,20%': (200.0, 120.0, 100.0, 60.0),
    '@位置=右下': (242.0, 212.0, 140.0, 70.0),
  }.entries) {
    test('three-way script merge applies legacy geometry ${entry.key}', () {
      const caption =
          CaptionLine(speaker: '', text: 'BEFORE', bubbleId: 'p1-b1');
      const old = BubblePlacement(
          caption: caption, x: 10, y: 20, width: 140, height: 70, fontSize: 34);
      final baseline = CaptionLine(
          speaker: '',
          text: 'BEFORE',
          bubbleId: 'p1-b1',
          layout:
              const CaptionLayoutSpec(x: 10, y: 20, width: 140, height: 70));
      final incoming = parseCaptionScript('[001.png]\n@气泡ID=p1-b1\n'
              '${entry.key}\n${entry.key.startsWith('@位置') ? '@尺寸=35%,23.3333333333333%\n' : ''}正文')
          .byFile['001.png']!
          .single;
      final generated = const LayoutEngine()
          .arrange([incoming], imageWidth: 400, imageHeight: 300);
      final result = mergeScriptPlacements([old], generated, [baseline]).single;
      expect(result.x, closeTo(entry.value.$1, .01));
      expect(result.y, closeTo(entry.value.$2, .01));
      expect(result.width, closeTo(entry.value.$3, .01));
      expect(result.height, closeTo(entry.value.$4, .01));
    });
  }

  testWidgets(
      'focused bubble editor delegates Ctrl-Z/Ctrl-Y to project callbacks',
      (tester) async {
    var text = 'BEFORE';
    var undoCount = 0;
    var redoCount = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: StatefulBuilder(
          builder: (context, setState) => CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                        () => setState(() {
                              redoCount++;
                              text = 'AFTER';
                            }),
                    const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                        () => setState(() {
                              undoCount++;
                              text = 'BEFORE';
                            }),
                  },
                  child: Scaffold(
                      body: BubbleTextEditor(
                    editorId: 'editor-1',
                    text: text,
                    compact: false,
                    onChanged: (value) => setState(() => text = value),
                    onUndo: () => setState(() {
                      undoCount++;
                      text = 'BEFORE';
                    }),
                    onRedo: () => setState(() {
                      redoCount++;
                      text = 'AFTER';
                    }),
                  )))),
    ));
    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'AFTER');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(undoCount, 1);
    expect(text, 'BEFORE');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(redoCount, 1);
    expect(text, 'AFTER');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(undoCount, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(redoCount, 2);
    expect(text, 'AFTER');
  });
}

ProjectDocument _capture(ImagePage page, DocumentAssetPool pool) =>
    ProjectDocument.capture([page], pool,
        revision: 1,
        script: buildBcsScript([page]),
        selectedPage: 0,
        selectedBubble: 0);

Future<ui.Image> _raster(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(Colors.grey, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ImagePage> _page() async {
  final image = await _raster(400, 300);
  return ImagePage(
      pageId: 'page-1',
      name: '1.png',
      image: image,
      bytes: (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List());
}
