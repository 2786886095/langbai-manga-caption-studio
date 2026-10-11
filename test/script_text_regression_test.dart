import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/page_collection.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _bcs(String text, {String shape = '旁白框'}) => '''
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px

[图片 1]
@原文件名=1.png
@原图尺寸=1216x832

@气泡ID=p1-b1
@矩形=56,48,400,116
@尾巴=右下
@气泡=$shape
@字体=Noto Sans SC
@字号=34
@颜色=#141518
@行距=1.25
@描边=2
@白底透明度=100
$text
''';

void main() {
  const screenshotText = '沈露是沈氏集团独女，家里管得极严：不夜归、不许有绯闻、连婚事都由父亲安排';

  test('BCS preserves the screenshot narration before the Chinese colon', () {
    final parsed = parseCaptionScript(_bcs(screenshotText));
    final caption = parsed.sections.single.captions.single;

    expect(parsed.warnings, isEmpty);
    expect(caption.text, screenshotText);
    expect(caption.speaker, isEmpty);
    expect(caption.bubbleId, 'p1-b1');
    expect(caption.layout!.x, 56);
  });

  for (final body in [
    '计划如下：先等待，再出发。',
    'The rule is: keep the entire sentence.',
    '09:30 开始，10:45 结束。',
    'https://example.com:8443/story?id=1',
    '她只说了一句话：\n不要回头。\nNote: stay here.',
    '角色：这仍然是作品正文，不是说话者元数据。',
  ]) {
    test('structured captions preserve literal punctuation: $body', () {
      final caption =
          parseCaptionScript(_bcs(body)).sections.single.captions.single;

      expect(caption.text, body);
      expect(caption.speaker, isEmpty);
    });
  }

  test('directive block under a legacy filename keeps the literal text', () {
    final parsed = parseCaptionScript('''
[001.png]
@气泡=旁白框
@字号=34
$screenshotText
次日09:30，https://example.com/story
''');
    final caption = parsed.byFile['001.png']!.single;

    expect(caption.text, '$screenshotText\n次日09:30，https://example.com/story');
    expect(caption.speaker, isEmpty);
  });

  test('sequential BCS text never falls back to implicit speaker parsing', () {
    final parsed = parseCaptionScript('''
[图片 1]
@原文件名=1.png
@原图尺寸=1216x832
$screenshotText
第二行：仍然保留。
''');

    expect(parsed.sections.single.captions.single.text,
        '$screenshotText\n第二行：仍然保留。');
    expect(parsed.sections.single.captions.single.speaker, isEmpty);
  });

  test('BCS declaration disables shorthand even under a filename section', () {
    final parsed = parseCaptionScript('''
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px
[001.png]
$screenshotText
第二行：仍然保留。
''');

    expect(parsed.byFile['001.png']!.single.text, '$screenshotText\n第二行：仍然保留。');
    expect(parsed.byFile['001.png']!.single.speaker, isEmpty);
  });

  test('explicit role metadata does not remove punctuation from the body', () {
    final parsed = parseCaptionScript('''
[001.png]
@角色=小雪
@气泡=对话气泡
答案是：不行。Time: 09:30.
''');
    final caption = parsed.byFile['001.png']!.single;

    expect(caption.speaker, '小雪');
    expect(caption.text, '答案是：不行。Time: 09:30.');
  });

  test(
      'legacy line-only input still accepts Chinese and English speaker labels',
      () {
    final parsed = parseCaptionScript('''
[001.png]
小雪：你好
Alice: Wait: do not go.
无说话者的一句正文
''');
    final captions = parsed.byFile['001.png']!;

    expect(captions, hasLength(3));
    expect(captions[0].speaker, '小雪');
    expect(captions[0].text, '你好');
    expect(captions[1].speaker, 'Alice');
    expect(captions[1].text, 'Wait: do not go.');
    expect(captions[2].speaker, isEmpty);
    expect(captions[2].text, '无说话者的一句正文');
  });

  test('legacy unassigned lines retain their speaker compatibility', () {
    final parsed = parseCaptionScript('小雪：你好\nAlice: Wait.');

    expect(parsed.unassigned, hasLength(2));
    expect(parsed.unassigned.first.speaker, '小雪');
    expect(parsed.unassigned.last.text, 'Wait.');
  });

  test(
      'applying and arranging BCS retains the complete caption in preview data',
      () {
    final incoming =
        parseCaptionScript(_bcs(screenshotText)).sections.single.captions;
    const oldCaption = CaptionLine(
      speaker: '沈露是沈氏集团独女，家里管得极严',
      text: '不夜归、不许有绯闻、连婚事都由父亲安排',
      bubbleId: 'p1-b1',
    );
    const existing = [
      BubblePlacement(
        caption: oldCaption,
        x: 56,
        y: 48,
        width: 400,
        height: 116,
      ),
    ];
    final generated = const LayoutEngine().arrange(
      incoming,
      imageWidth: 1216,
      imageHeight: 832,
    );
    final applied = preserveEditedPlacements(existing, generated, incoming);

    expect(applied.single.caption.text, screenshotText);
    expect(applied.single.caption.speaker, isEmpty);
    expect(applied.single.shape, BubbleShape.rounded);
  });

  for (final alias in ['纯文字', '无框文字', 'text', 'plainText']) {
    test('plain text BCS type accepts $alias', () {
      final parsed = parseCaptionScript(_bcs('文字：完整保留。', shape: alias));
      final caption = parsed.sections.single.captions.single;

      expect(parsed.warnings, isEmpty);
      expect(caption.layout!.shape, BubbleShape.plainText);
      expect(caption.text, '文字：完整保留。');
    });
  }

  for (final shape in [BubbleShape.thought, BubbleShape.plainText]) {
    test('a font-size-only script keeps manual geometry and $shape styling', () {
      final caption = parseCaptionScript('''
[001.png]
@气泡ID=p1-b1
@字号=40
修改后：保留全部正文和手工样式。
''').byFile['001.png']!.single;
      final layout = caption.layout!;
      expect(layout.shape, isNull);
      expect(layout.tailDirection, isNull);
      expect(layout.fontFamily, isNull);
      expect(layout.fontColorValue, isNull);
      expect(layout.lineHeight, isNull);
      expect(layout.strokeWidth, isNull);
      expect(layout.fillOpacity, isNull);
      final previous = BubblePlacement(
        caption: const CaptionLine(
          speaker: '',
          text: '原文字',
          bubbleId: 'p1-b1',
        ),
        x: 137,
        y: 91,
        width: 284,
        height: 123,
        shape: shape,
        tailDirection: TailDirection.upLeft,
        fontFamily: 'CustomFont',
        fontColorValue: 0xff123456,
        fontSize: 31,
        lineHeight: 1.7,
        strokeWidth: 6,
        fillOpacity: .45,
      );
      final generated = const LayoutEngine().arrange(
        [caption],
        imageWidth: 1216,
        imageHeight: 832,
      );
      final updated =
          preserveEditedPlacements([previous], generated, [caption]).single;

      expect(updated.caption.text, '修改后：保留全部正文和手工样式。');
      expect(updated.x, previous.x);
      expect(updated.y, previous.y);
      expect(updated.width, previous.width);
      expect(updated.height, previous.height);
      expect(updated.shape, shape);
      expect(updated.tailDirection, previous.tailDirection);
      expect(updated.fontFamily, previous.fontFamily);
      expect(updated.fontColorValue, previous.fontColorValue);
      expect(updated.lineHeight, previous.lineHeight);
      expect(updated.strokeWidth, previous.strokeWidth);
      expect(updated.fillOpacity, previous.fillOpacity);
      expect(updated.fontSize, 40);
    });
  }

  test('explicitly invalid shape and tail keep diagnostic fallback behavior', () {
    final parsed = parseCaptionScript('''
[001.png]
@气泡=不存在的样式
@尾巴=不存在的方向
正文：完整保留。
''');
    final caption = parsed.byFile['001.png']!.single;

    expect(parsed.warnings, hasLength(2));
    expect(caption.layout!.shape, BubbleShape.ellipse);
    expect(caption.layout!.tailDirection, TailDirection.downRight);
    expect(caption.text, '正文：完整保留。');
  });
}
