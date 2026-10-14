import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/script_merge.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bubble = BubblePlacement(
      caption: CaptionLine(speaker: '', text: 'A', bubbleId: 'p1-b1'),
      x: 10,
      y: 20,
      width: 300,
      height: 200,
      fontSize: 34,
      textSizeMode: TextSizeMode.fit,
      styleId: 'shared');
  test('global auto cap makes retained manual-size memories equivalent', () {
    expect(linkedTextStyleKey(bubble),
        linkedTextStyleKey(bubble.copyWith(fontSize: 200)));
    expect(
        linkedTextStyleKey(bubble.copyWith(textSizeMode: TextSizeMode.fixed)),
        isNot(linkedTextStyleKey(
            bubble.copyWith(textSizeMode: TextSizeMode.fixed, fontSize: 200))));
    final second = bubble.copyWith(
        caption: bubble.caption.copyWith(bubbleId: 'p1-b2'), fontSize: 200);
    expect(() => mergeLinkedStyleChanges([bubble, second], [bubble, second]),
        returnsNormally);
  });

  test('BCS3 body-only import keeps an existing same-ID manual34 unchanged',
      () {
    final manual = bubble.copyWith(textSizeMode: TextSizeMode.fixed);
    final baseline = parseCaptionScript(
            _v3('@矩形=10,20,300,200\n@字号=34\n@字号模式=固定\n', text: 'A'))
        .sections
        .single
        .captions;
    final parsed = parseCaptionScript(_v3(''));
    expect(parsed.errors, isEmpty);
    expect(parsed.warnings, isEmpty);
    final generated = _layoutPage(parsed.sections.single.captions);
    final merged = mergeScriptPlacements([manual], generated, baseline).single;
    expect(merged.caption.bubbleId, 'p1-b1');
    expect(merged.caption.text, 'B');
    expect(merged.fontSize, 34,
        reason: 'Missing @字号 is not a request to overwrite a manual size');
    expect(merged.textSizeMode, TextSizeMode.fixed,
        reason: 'Missing @字号模式 is not an explicit switch to automatic');
    expect((merged.x, merged.y, merged.width, merged.height),
        (manual.x, manual.y, manual.width, manual.height));
    expect(manual.caption.text, 'A');
    expect(manual.fontSize, 34);
  });

  test('BCS3 omitted typography gets 200fit for a genuinely new object', () {
    final parsed = parseCaptionScript(_v3(''));
    expect(parsed.errors, isEmpty);
    final generated = _layoutPage(parsed.sections.single.captions);
    expect(generated.single.fontSize, 200);
    expect(generated.single.textSizeMode, TextSizeMode.fit);
    final added = mergeScriptPlacements([], generated, []).single;
    expect(added.caption.text, 'B');
    expect(added.fontSize, 200);
    expect(added.textSizeMode, TextSizeMode.fit);
  });

  test('BCS3 explicit manual typography still changes the requested size', () {
    final manual = bubble.copyWith(textSizeMode: TextSizeMode.fixed);
    final baseline = parseCaptionScript(_v3('@字号=34\n@字号模式=固定\n', text: 'A'))
        .sections
        .single
        .captions;
    final parsed = parseCaptionScript(_v3('@字号=48\n@字号模式=固定\n'));
    final merged = mergeScriptPlacements(
            [manual], _layoutPage(parsed.sections.single.captions), baseline)
        .single;
    expect(merged.caption.text, 'B');
    expect(merged.fontSize, 48);
    expect(merged.textSizeMode, TextSizeMode.fixed);
  });

  test(
      'BCS3 explicit auto request switches an existing manual object to 200fit',
      () {
    final manual = bubble.copyWith(textSizeMode: TextSizeMode.fixed);
    final baseline = parseCaptionScript(_v3('@字号=34\n@字号模式=固定\n', text: 'A'))
        .sections
        .single
        .captions;
    final parsed = parseCaptionScript(_v3('@字号=200\n@字号模式=自动适配\n'));
    final merged = mergeScriptPlacements(
            [manual], _layoutPage(parsed.sections.single.captions), baseline)
        .single;
    expect(merged.caption.text, 'B');
    expect(merged.fontSize, 200);
    expect(merged.textSizeMode, TextSizeMode.fit);
  });

  test('BCS3 size-only import does not implicitly switch manual mode to auto',
      () {
    final manual = bubble.copyWith(textSizeMode: TextSizeMode.fixed);
    final baseline = parseCaptionScript(_v3('@字号=34\n@字号模式=固定\n', text: 'A'))
        .sections
        .single
        .captions;
    final parsed = parseCaptionScript(_v3('@字号=48\n'));
    final merged = mergeScriptPlacements(
            [manual], _layoutPage(parsed.sections.single.captions), baseline)
        .single;
    expect(merged.caption.text, 'B');
    expect(merged.fontSize, 48);
    expect(merged.textSizeMode, TextSizeMode.fixed);
  });
}

// Production's page generation API is LayoutEngine.arrange; this helper keeps
// every regression on the actual parse -> page layout -> three-way merge path.
List<BubblePlacement> _layoutPage(List<CaptionLine> captions) =>
    const LayoutEngine().arrange(captions, imageWidth: 1000, imageHeight: 1000);

String _v3(String fields, {String text = 'B'}) => '''@格式=BCS顺序字幕脚本
@版本=3
@坐标单位=px
[图片 1]
@原文件名=001.png
@原图尺寸=1000x1000
@气泡ID=p1-b1
$fields@正文行数=1
$text
''';
