import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bubble_caption_studio/src/project_document.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/script_merge.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DocumentAssetPool assets;
  late ImagePage page;
  setUp(() async {
    assets = DocumentAssetPool();
    final r = ui.PictureRecorder();
    Canvas(r).drawColor(Colors.grey, BlendMode.src);
    final picture = r.endRecording();
    final image = await picture.toImage(400, 300);
    picture.dispose();
    page = ImagePage(
        pageId: 'page',
        name: '1.png',
        bytes: (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List(),
        image: image);
    const c = CaptionLine(speaker: '', text: 'BEFORE', bubbleId: 'p1-b1');
    page.captions = [c];
    page.placements = [
      BubblePlacement(
          caption: c,
          x: 10.25,
          y: 20.75,
          width: 220,
          height: 90,
          fontSize: 34,
          textSizeMode: TextSizeMode.fixed,
          shape: BubbleShape.plainText)
    ];
  });
  tearDown(() {
    page.dispose();
    assets.dispose();
  });
  ProjectDocument capture([int revision = 0]) =>
      ProjectDocument.capture([page], assets,
          revision: revision,
          script: buildBcsScript([page]),
          selectedPage: 0,
          selectedBubble: 0);

  test(
      'immutable document retains pixels while disposable projection is released',
      () {
    final doc = capture();
    final projection = doc.toPages();
    projection.single.placements.clear();
    projection.single.dispose();
    expect(doc.pages.single.elements.length, 1);
    final again = doc.toPages();
    expect(again.single.image.width, 400);
    again.single.dispose();
  });
  test(
      'restoring identical asset IDs reuses retained bytes and raster across decodes',
      () {
    final first = capture();
    final decoded = ImagePage(
        pageId: page.pageId,
        name: page.name,
        bytes: Uint8List.fromList(page.bytes),
        image: page.image.clone());
    final second = ProjectDocument.capture([decoded], assets,
        revision: 1, script: '', selectedPage: 0, selectedBubble: 0);
    expect(
        identical(first.pages.single.bytes, second.pages.single.bytes), true);
    expect(
        identical(first.pages.single.image, second.pages.single.image), true);
    decoded.dispose();
    final restored = first.toPages();
    expect(restored.single.image.width, 400);
    restored.single.dispose();
  });
  test('no-op does not clear redo and grouped input undoes as one operation',
      () {
    final history = EditorHistory();
    final a = capture();
    page.placements = [
      page.placements.single
          .copyWith(caption: page.captions.single.copyWith(text: 'FIRST'))
    ];
    final b = capture(1);
    history.record(a, b, '文字', group: 'text:1');
    page.placements = [
      page.placements.single
          .copyWith(caption: page.captions.single.copyWith(text: 'FINAL'))
    ];
    final c = capture(2);
    history.record(b, c, '文字', group: 'text:1');
    expect(history.undoEntries.length, 1);
    expect(history.undo()!.pages.single.elements.single.text, 'BEFORE');
    expect(history.record(a, a, '点击'), false);
    expect(history.redoEntries.length, 1);
    expect(history.redo()!.pages.single.elements.single.text, 'FINAL');
  });
  test('subpixel geometry is recorded even when serialization rounds numbers',
      () {
    final history = EditorHistory();
    final a = capture();
    page.placements = [page.placements.single.copyWith(x: 10.26)];
    expect(history.record(a, capture(1), '移动'), true);
  });
  test('111-page history retains project-wide edit and source asset identity',
      () {
    final pages = <ImagePage>[];
    for (var i = 0; i < 111; i++) {
      final clone = ImagePage(
          pageId: 'p$i',
          name: '$i.png',
          bytes: page.bytes,
          image: page.image.clone(),
          originalWidth: 400,
          originalHeight: 300);
      clone.placements = [
        page.placements.single.copyWith(
            caption: page.captions.single.copyWith(bubbleId: 'p$i-b1'))
      ];
      clone.captions = clone.placements.map((b) => b.caption).toList();
      pages.add(clone);
    }
    final before = ProjectDocument.capture(pages, assets,
        revision: 0,
        script: buildBcsScript(pages),
        selectedPage: 0,
        selectedBubble: 0);
    pages.last.placements = [
      pages.last.placements.single.copyWith(fontSize: 72)
    ];
    final after = ProjectDocument.capture(pages, assets,
        revision: 1,
        script: buildBcsScript(pages),
        selectedPage: 110,
        selectedBubble: 0);
    final h = EditorHistory();
    h.record(before, after, '批量');
    h.finishGroup();
    expect(h.undo()!.pages.last.elements.single.placement.fontSize, 34);
    expect(h.redo()!.pages.last.elements.single.placement.fontSize, 72);
    for (final p in pages) {
      p.dispose();
    }
  });
  test('text-only script merge preserves manual subpixel geometry and styles',
      () {
    final old = page.placements.single;
    final baseline =
        parseCaptionScript(buildBcsScript([page])).sections.single.captions;
    final incoming =
        parseCaptionScript(buildBcsScript([page]).replaceAll('BEFORE', 'NEW'))
            .sections
            .single
            .captions;
    final generated = const LayoutEngine()
        .arrange(incoming, imageWidth: 400, imageHeight: 300);
    final merged = mergeScriptPlacements([old], generated, baseline).single;
    expect(merged.caption.text, 'NEW');
    expect(merged.x, 10.25);
    expect(merged.y, 20.75);
    expect(merged.shape, BubbleShape.plainText);
  });
  test('unchanged draft fields do not overwrite concurrent document changes',
      () {
    final baseline =
        parseCaptionScript(buildBcsScript([page])).sections.single.captions;
    final incoming =
        parseCaptionScript(buildBcsScript([page]).replaceAll('BEFORE', 'NEW'))
            .sections
            .single
            .captions;
    final manual = page.placements.single.copyWith(fontSize: 72, x: 150);
    final merged = mergeScriptPlacements(
            [manual],
            const LayoutEngine()
                .arrange(incoming, imageWidth: 400, imageHeight: 300),
            baseline)
        .single;
    expect(merged.fontSize, 72);
    expect(merged.x, 150);
    expect(merged.caption.text, 'NEW');
  });
}
