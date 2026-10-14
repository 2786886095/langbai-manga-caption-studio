import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/text_layout_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _completeText = '沈露是沈氏集团独女，家里管得极严：不夜归、不许有绯闻、连婚事都由父亲安排';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plain text appends its enum value without changing old shape indices',
      () {
    expect(BubbleShape.ellipse.index, 0);
    expect(BubbleShape.rounded.index, 1);
    expect(BubbleShape.shout.index, 2);
    expect(BubbleShape.thought.index, 3);
    expect(BubbleShape.whisper.index, 4);
    expect(BubbleShape.plainText.index, 5);
    expect(bcsShapeName(BubbleShape.plainText), '纯文字');
  });

  test('plain text has a rectangular hit area but no pointer or outline', () {
    final bubble = _plainBubble();
    final rect = Rect.fromLTWH(
      bubble.x,
      bubble.y,
      bubble.width,
      bubble.height,
    );
    expect(bubbleHasPointer(bubble.shape), isFalse);
    expect(bubbleOutlinePath(rect, bubble).computeMetrics(), isEmpty);
    expect(
        bubbleContainsPoint(bubble, rect.topLeft + const Offset(1, 1)), isTrue);
    expect(bubbleContainsPoint(bubble, rect.center), isTrue);
    expect(bubbleContainsPoint(bubble, rect.bottomRight + const Offset(1, 1)),
        isFalse);
    expect(hitTestBubble([bubble], rect.center), 0);
    expect(bubbleResizeHandles(rect), hasLength(8));
  });

  test('plain text BCS round trip preserves the complete text and style',
      () async {
    final page = await _transparentPage();
    addTearDown(page.dispose);
    final bubble = _plainBubble().copyWith(textSizeMode: TextSizeMode.fixed);
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];

    final script = buildBcsScript([page]);
    expect(script, contains('@气泡=纯文字\n'));
    expect(script, contains('@颜色=#D12A45\n'));
    expect(script, contains('@字号=34\n'));
    expect(script, contains('@字号模式=固定\n'));
    expect(script, contains(_completeText));
    final parsed = parseCaptionScript(script);
    expect(parsed.warnings, isEmpty);
    final caption = parsed.sections.single.captions.single;
    expect(caption.text, _completeText);
    expect(caption.speaker, isEmpty);
    expect(caption.layout!.shape, BubbleShape.plainText);
    final restored = const LayoutEngine().arrange(
      [caption],
      imageWidth: page.originalWidth,
      imageHeight: page.originalHeight,
    ).single;
    expect(restored.shape, BubbleShape.plainText);
    expect(restored.fontColorValue, bubble.fontColorValue);
    expect(restored.fontFamily, bubble.fontFamily);
    expect(restored.fontSize, bubble.fontSize);
    expect(restored.textSizeMode, TextSizeMode.fixed);
    expect(restored.lineHeight, bubble.lineHeight);
    expect(restored.x, bubble.x);
    expect(restored.y, bubble.y);
    expect(restored.width, bubble.width);
    expect(restored.height, bubble.height);
  });

  test('packed, manifest and edits preserve plain text and changed captions',
      () async {
    final page = await _transparentPage();
    addTearDown(page.dispose);
    final bubble = _plainBubble();
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];
    final script = buildBcsScript([page]);
    final packed = encodeProject([page], script);
    final packedRoot = jsonDecode(utf8.decode(packed)) as Map<String, dynamic>;
    expect((packedRoot['pages'] as List).single['placements'][0]['shape'],
        'plainText');
    final restoredPacked = await decodeProject(packed);
    addTearDown(restoredPacked.pages.single.dispose);
    _expectSavedText(restoredPacked.pages.single, _completeText);

    final manifest = encodeProjectManifest([page], script);
    final restoredManifest = await decodeProjectManifest(
      manifest,
      (pageId) async {
        expect(pageId, page.pageId);
        return page.bytes;
      },
    );
    addTearDown(restoredManifest.pages.single.dispose);
    _expectSavedText(restoredManifest.pages.single, _completeText);

    const editedText = '修改后：全文仍然保存，不会把冒号前的文字误当作说话者。';
    final edited = bubble.caption.copyWith(text: editedText);
    page
      ..captions = [edited]
      ..placements = [bubble.copyWith(caption: edited)];
    final result = await applyProjectEdits(
      encodeProjectEdits([page], buildBcsScript([page])),
      restoredManifest.pages,
    );
    expect(result.script, contains(editedText));
    _expectSavedText(restoredManifest.pages.single, editedText);
  });

  test('plain text paints only glyphs, with no fill, frame or tail', () async {
    final page = await _transparentPage();
    addTearDown(page.dispose);
    final empty = _plainBubble().copyWith(
      caption: const CaptionLine(speaker: '', text: '', bubbleId: 'p1-b1'),
    );
    for (final direction in TailDirection.values) {
      page.placements = [empty.copyWith(tailDirection: direction)];
      final pixels = await _render(page);
      expect(_visiblePixelCount(pixels), 0,
          reason: 'Plain text must not paint a frame or $direction tail.');
    }

    page.placements = [
      _plainBubble().copyWith(
        caption: const CaptionLine(
          speaker: '',
          text: 'VISIBLE TEXT',
          bubbleId: 'p1-b1',
        ),
      ),
    ];
    final pixels = await _render(page);
    expect(_visiblePixelCount(pixels), greaterThan(0));
    for (var offset = 0; offset < pixels.length; offset += 4) {
      if (pixels[offset + 3] == 0) continue;
      // Raw RGBA is premultiplied: colored glyphs still retain this ordering.
      expect(pixels[offset], greaterThan(pixels[offset + 1]));
      expect(pixels[offset], greaterThan(pixels[offset + 2]));
    }
    expect(_alphaAt(pixels, 24, 24), 0);
    expect(_alphaAt(pixels, 264, 144), 0);

    final selectedPixels = await _render(page, selected: true);
    expect(_visiblePixelCount(selectedPixels),
        greaterThan(_visiblePixelCount(pixels)));
    expect(_alphaAt(selectedPixels, 24, 24), greaterThan(0));
  });

  test('long captions fit sufficient height without truncating at six lines',
      () {
    final text = List.generate(12, (index) => '完整第${index + 1}行').join('\n');
    for (final shape in BubbleShape.values) {
      final bubble = _plainBubble().copyWith(
        shape: shape,
        width: 220,
        height: 300,
        textSizeMode: TextSizeMode.fit,
        caption: CaptionLine(speaker: '', text: text),
      );
      final painter = layoutBubbleText(bubble);
      expect(painter.text!.toPlainText(), text);
      expect(painter.maxLines, isNull);
      expect(painter.ellipsis, isNull);
      expect(painter.didExceedMaxLines, isFalse);
      expect(painter.computeLineMetrics(), hasLength(12));
      expect((painter.text! as TextSpan).style!.fontSize,
          inInclusiveRange(8.0, 200.0));
      expect(
          painter.height,
          lessThanOrEqualTo(
              const TextLayoutService().textArea(bubble).height + .0001));
      painter.dispose();
    }
  });

  test(
      'twelve lines in a short box retain full text at 8 px and report overflow',
      () {
    final text = List.generate(12, (index) => '完整第${index + 1}行').join('\n');
    for (final shape in BubbleShape.values) {
      final bubble = _plainBubble().copyWith(
          shape: shape,
          width: 220,
          height: 100,
          textSizeMode: TextSizeMode.fit,
          caption: CaptionLine(speaker: '', text: text));
      final result = const TextLayoutService().layout(bubble);
      expect(result.effectiveFontSize, 8);
      expect(result.overflow, isTrue);
      expect(result.painter.height, greaterThan(result.availableRect.height));
      expect(result.painter.text!.toPlainText(), text);
      expect(result.painter.maxLines, isNull);
      expect(result.painter.ellipsis, isNull);
      expect(result.painter.didExceedMaxLines, isFalse);
      expect(result.painter.computeLineMetrics(), hasLength(12));
      result.dispose();
    }
  });

  test('narrow text fitting keeps font and color and every script character',
      () {
    final bubble = _plainBubble().copyWith(width: 32, height: 160);
    final painter = layoutBubbleText(bubble);
    expect(painter.text!.toPlainText(), _completeText);
    expect(painter.height, lessThanOrEqualTo(bubble.height));
    expect(painter.computeLineMetrics().every((line) => line.width <= 32.001),
        isTrue);
    final style = (painter.text! as TextSpan).style!;
    expect(style.fontFamily, bubble.fontFamily);
    expect(style.color, Color(bubble.fontColorValue));
    expect(style.fontSize, lessThan(bubble.fontSize));
    painter.dispose();
  });
}

BubblePlacement _plainBubble() => const BubblePlacement(
      caption: CaptionLine(speaker: '', text: _completeText, bubbleId: 'p1-b1'),
      x: 24,
      y: 24,
      width: 240,
      height: 120,
      shape: BubbleShape.plainText,
      fontColorValue: 0xffd12a45,
      fontSize: 34,
      lineHeight: 1.3,
      strokeWidth: 4,
      fillOpacity: 1,
    );

void _expectSavedText(ImagePage page, String text) {
  final bubble = page.placements.single;
  expect(page.captions.single.text, text);
  expect(bubble.caption.text, text);
  expect(bubble.shape, BubbleShape.plainText);
  expect(bubble.fontColorValue, 0xffd12a45);
  expect(bubble.width, 240);
  expect(bubble.height, 120);
}

Future<ImagePage> _transparentPage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  picture.dispose();
  final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
  return ImagePage(
    name: '001.png',
    bytes: encoded!.buffer.asUint8List(),
    image: image,
    pageId: 'plain-text-page',
  );
}

Future<Uint8List> _render(ImagePage page, {bool selected = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(page: page, selectedIndex: selected ? 0 : null)
      .paint(canvas, const Size(320, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!.buffer.asUint8List();
}

int _visiblePixelCount(Uint8List pixels) {
  var count = 0;
  for (var offset = 3; offset < pixels.length; offset += 4) {
    if (pixels[offset] > 0) count++;
  }
  return count;
}

int _alphaAt(Uint8List pixels, int x, int y) => pixels[(y * 320 + x) * 4 + 3];
