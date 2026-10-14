import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/exporter.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/text_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _service = TextLayoutService();

BubblePlacement _auto(
        {String text = 'A',
        double width = 400,
        double height = 200,
        double requested = 200}) =>
    BubblePlacement(
        caption: CaptionLine(speaker: '', text: text, bubbleId: 'p1-b1'),
        x: 12,
        y: 14,
        width: width,
        height: height,
        fontSize: requested,
        textSizeMode: TextSizeMode.fit,
        shape: BubbleShape.plainText);

String _script(String properties) => '''@格式=BCS顺序字幕脚本
@版本=3
@坐标单位=px
[图片 1]
@原文件名=001.png
@原图尺寸=1000x1000
@气泡ID=p1-b1
@矩形=10,10,400,200
@气泡=纯文字
$properties@正文行数=1
完整正文
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('model and new layout default to 200 automatic sizing', () {
    const bubble = BubblePlacement(
        caption: CaptionLine(speaker: '', text: 'A'),
        x: 0,
        y: 0,
        width: 200,
        height: 100);
    expect(bubble.fontSize, 200);
    expect(bubble.textSizeMode, TextSizeMode.fit);
    final generated = const LayoutEngine().arrange(
        [const CaptionLine(speaker: '', text: 'A')],
        imageWidth: 1000, imageHeight: 1000).single;
    expect(generated.fontSize, 200);
    expect(generated.textSizeMode, TextSizeMode.fit);
  });

  test(
      'BCS3 new objects get 200auto defaults at layout generation, not parsing',
      () {
    final parsed = parseCaptionScript(_script(''));
    expect(parsed.errors, isEmpty);
    expect(parsed.warnings, isEmpty);
    final bubble = const LayoutEngine()
        .arrange(parsed.sections.single.captions,
            imageWidth: 1000, imageHeight: 1000)
        .single;
    expect(bubble.fontSize, 200);
    expect(bubble.textSizeMode, TextSizeMode.fit);
    expect(bubble.caption.text, '完整正文');
  });

  test('explicit manual 34 stays fixed as rectangles grow', () {
    final parsed = parseCaptionScript(_script('@字号=34\n@字号模式=固定\n'));
    final bubble = const LayoutEngine()
        .arrange(parsed.sections.single.captions,
            imageWidth: 1000, imageHeight: 1000)
        .single;
    expect(bubble.fontSize, 34);
    expect(bubble.textSizeMode, TextSizeMode.fixed);
    for (final size in [const ui.Size(80, 40), const ui.Size(800, 800)]) {
      final result = _service
          .layout(bubble.copyWith(width: size.width, height: size.height));
      expect(result.effectiveFontSize, 34);
      expect(result.painter.text!.toPlainText(), '完整正文');
      result.dispose();
    }
  });

  test('old auto requested 34 is no longer an upper bound and grows with box',
      () {
    final small = _service.layout(_auto(width: 60, height: 40, requested: 34));
    final large =
        _service.layout(_auto(width: 600, height: 300, requested: 34));
    expect(large.effectiveFontSize, greaterThan(34));
    expect(large.effectiveFontSize, greaterThan(small.effectiveFontSize));
    expect(small.overflow, isFalse);
    expect(large.overflow, isFalse);
    small.dispose();
    large.dispose();
  });

  test('width and height independently increase the maximum fitting size', () {
    for (final pair in [
      (const ui.Size(40, 800), const ui.Size(160, 800)),
      (const ui.Size(800, 40), const ui.Size(800, 160)),
    ]) {
      final small =
          _service.layout(_auto(width: pair.$1.width, height: pair.$1.height));
      final large =
          _service.layout(_auto(width: pair.$2.width, height: pair.$2.height));
      expect(large.effectiveFontSize, greaterThan(small.effectiveFontSize));
      expect(small.overflow, isFalse);
      expect(large.overflow, isFalse);
      small.dispose();
      large.dispose();
    }
  });

  test(
      'automatic sizing chooses the largest fitting value, not any small value',
      () {
    final bubble = _auto(text: 'ABCDEFGHIJ', width: 240, height: 80);
    final result = _service.layout(bubble);
    expect(result.overflow, isFalse);
    expect(result.effectiveFontSize, inInclusiveRange(8.0, 199.9));
    final larger = _service.layout(bubble.copyWith(
        textSizeMode: TextSizeMode.fixed,
        fontSize: result.effectiveFontSize + .1));
    expect(larger.overflow, isTrue,
        reason:
            'A larger fitting size would mean auto did not find the maximum');
    expect(result.painter.text!.toPlainText(), 'ABCDEFGHIJ');
    result.dispose();
    larger.dispose();
  });

  test(
      'automatic sizing never exceeds 200 even with large boxes or old large requests',
      () {
    for (final requested in [34.0, 200.0, 999.0]) {
      final result = _service
          .layout(_auto(width: 5000, height: 5000, requested: requested));
      expect(result.effectiveFontSize, 200);
      expect(result.overflow, isFalse);
      result.dispose();
    }
  });

  test('8 px minimum reports overflow rather than shrinking or truncating text',
      () {
    const text = '第一行完整正文\n第二行：不得丢字\n@这是正文\n结束';
    final result = _service.layout(_auto(text: text, width: 1, height: 1));
    expect(result.effectiveFontSize, 8);
    expect(result.overflow, isTrue);
    expect(result.painter.text!.toPlainText(), text);
    expect(result.painter.maxLines, isNull);
    expect(result.painter.ellipsis, isNull);
    result.dispose();
  });

  test(
      'horizontal vertical and extreme rectangles have stable bounded auto sizes',
      () {
    for (final shape in BubbleShape.values) {
      for (final size in [
        const ui.Size(1200, 60),
        const ui.Size(60, 1200),
        const ui.Size(10000, .5),
        const ui.Size(.5, 10000)
      ]) {
        final bubble =
            _auto(text: 'WIDE', width: size.width, height: size.height)
                .copyWith(shape: shape);
        final first = _service.layout(bubble), second = _service.layout(bubble);
        expect(first.effectiveFontSize.isFinite, isTrue);
        expect(first.effectiveFontSize, inInclusiveRange(8.0, 200.0));
        expect(second.effectiveFontSize, first.effectiveFontSize);
        expect(first.painter.text!.toPlainText(), 'WIDE');
        if (size.width < 1 || size.height < 1) {
          expect(first.effectiveFontSize, 8);
          expect(first.overflow, isTrue);
        }
        first.dispose();
        second.dispose();
      }
    }
  });

  test(
      'empty text remains deterministic and bounded without inventing characters',
      () {
    for (final size in [const ui.Size(1, 1), const ui.Size(400, 200)]) {
      final bubble = _auto(text: '', width: size.width, height: size.height);
      final first = _service.layout(bubble), second = _service.layout(bubble);
      expect(first.effectiveFontSize.isFinite, isTrue);
      expect(first.effectiveFontSize, inInclusiveRange(8.0, 200.0));
      expect(second.effectiveFontSize, first.effectiveFontSize);
      expect(first.painter.text!.toPlainText(), '');
      expect(first.painter.maxLines, isNull);
      expect(first.painter.ellipsis, isNull);
      first.dispose();
      second.dispose();
    }
  });

  test('BCS3 auto exports canonical 200 and round trips manual 34 separately',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    page.placements = [_auto(requested: 34)];
    final autoScript = buildBcsScript([page]);
    expect(autoScript, contains('@字号=200\n'));
    expect(autoScript, contains('@字号模式=自动适配\n'));
    final restored = const LayoutEngine()
        .arrange(parseCaptionScript(autoScript).sections.single.captions,
            imageWidth: 400, imageHeight: 300)
        .single;
    expect(restored.fontSize, 200);
    expect(restored.textSizeMode, TextSizeMode.fit);
    page.placements = [
      _auto(requested: 34).copyWith(textSizeMode: TextSizeMode.fixed)
    ];
    final manualScript = buildBcsScript([page]);
    expect(manualScript, contains('@字号=34\n'));
    expect(manualScript, contains('@字号模式=固定\n'));
  });

  test(
      'preview and PNG export use identical growing-auto layout and text pixels',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    page.placements = [
      _auto(text: 'HI', width: 240, height: 130, requested: 34)
    ];
    final layout = _service.layout(page.placements.single);
    expect(layout.effectiveFontSize, greaterThan(34));
    layout.dispose();
    final recorder = ui.PictureRecorder();
    PagePainter(page: page).paint(ui.Canvas(recorder), const ui.Size(400, 300));
    final picture = recorder.endRecording();
    final preview = await picture.toImage(400, 300);
    picture.dispose();
    final expected =
        (await preview.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    preview.dispose();
    final exported = await renderPageForExport(page, 0);
    final codec = await ui.instantiateImageCodec(exported.bytes);
    final image = (await codec.getNextFrame()).image;
    final actual = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    image.dispose();
    codec.dispose();
    expect(actual, expected);
  });
}

Future<ImagePage> _page() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 300);
  picture.dispose();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  return ImagePage(
      name: '001.png', bytes: bytes, image: image, pageId: 'auto-size-page');
}
