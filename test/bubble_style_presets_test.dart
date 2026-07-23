import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/app_localization.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/bubble_style_presets.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('narration bubble uses a true square-corner rectangle', () {
    const rect = Rect.fromLTWH(20, 30, 260, 120);
    const bubble = BubblePlacement(
      caption: CaptionLine(speaker: '', text: '旁白'),
      x: 20,
      y: 30,
      width: 260,
      height: 120,
      shape: BubbleShape.rounded,
    );

    final path = bubbleOutlinePath(rect, bubble);

    expect(path.contains(const Offset(21, 31)), isTrue);
    expect(path.contains(const Offset(279, 149)), isTrue);
    expect(path.contains(const Offset(19, 31)), isFalse);
  });

  test('preset catalog has unique ids and covers every bubble category', () {
    expect(
      bubbleStylePresets.map((preset) => preset.id).toSet(),
      hasLength(bubbleStylePresets.length),
    );
    for (final category in BubblePresetCategory.values) {
      expect(
        bubbleStylePresets.where((preset) => preset.category == category),
        isNotEmpty,
      );
    }
    expect(
      bubbleStylePresets
          .where((preset) => preset.category == BubblePresetCategory.narration)
          .every((preset) => preset.shape == BubbleShape.rounded),
      isTrue,
    );
  });

  test('preset controls are translated for every non-Simplified locale', () {
    for (final language in const ['en', 'ja', 'ko', 'zh_TW']) {
      expect(
        tr('气泡预设', languageCode: language),
        isNot('气泡预设'),
        reason: '气泡预设 should be translated for $language.',
      );
      expect(
        tr('基础类型', languageCode: language),
        isNot('基础类型'),
        reason: '基础类型 should be translated for $language.',
      );
    }
  });

  test('applying a preset stays inside the image and preserves text styling',
      () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final page = ImagePage(
      name: '001.png',
      bytes: Uint8List.fromList(png),
      image: frame.image,
      originalWidth: 832,
      originalHeight: 1216,
    );
    const source = BubblePlacement(
      caption: CaptionLine(
        speaker: '',
        text: '保留我的文字',
        bubbleId: 'p1-b1',
      ),
      x: 760,
      y: 1100,
      width: 70,
      height: 80,
      fontFamily: 'Ma Shan Zheng',
      fontColorValue: 0xff356db5,
      fontSize: 41,
      lineHeight: 1.4,
      fillOpacity: .66,
      tailDirection: TailDirection.upLeft,
    );
    final preset = bubbleStylePresets.firstWhere(
      (item) => item.id == 'narration-wide',
    );

    final result = preset.applyTo(source, page);

    expect(result.shape, BubbleShape.rounded);
    expect(result.strokeWidth, 2);
    expect(result.x, greaterThanOrEqualTo(0));
    expect(result.y, greaterThanOrEqualTo(0));
    expect(result.x + result.width, lessThanOrEqualTo(page.originalWidth));
    expect(result.y + result.height, lessThanOrEqualTo(page.originalHeight));
    expect(result.caption.text, '保留我的文字');
    expect(result.fontFamily, 'Ma Shan Zheng');
    expect(result.fontColorValue, 0xff356db5);
    expect(result.fontSize, 41);
    expect(result.lineHeight, 1.4);
    expect(result.fillOpacity, .66);
    expect(result.tailDirection, TailDirection.upLeft);
    expect(preset.matches(result, const Size(832, 1216)), isTrue);
    expect(
      preset.matches(
        result.copyWith(width: result.width * .7),
        const Size(832, 1216),
      ),
      isFalse,
    );
    page.dispose();
  });

  testWidgets('preset preview renders at a stable compact size',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BubblePresetPreview(
            preset: BubbleStylePreset(
              id: 'preview',
              label: '预览',
              category: BubblePresetCategory.narration,
              shape: BubbleShape.rounded,
              widthFraction: .4,
              heightFraction: .15,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preset catalog switches categories and dispatches a preset',
      (tester) async {
    var category = BubblePresetCategory.dialogue;
    BubbleStylePreset? selectedPreset;
    const bubble = BubblePlacement(
      caption: CaptionLine(speaker: '', text: '字幕'),
      x: 20,
      y: 20,
      width: 280,
      height: 140,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 360,
              child: BubblePresetCatalog(
                selectedCategory: category,
                bubble: bubble,
                imageSize: const Size(832, 1216),
                onCategoryChanged: (value) => setState(() => category = value),
                onPresetSelected: (value) => selectedPreset = value,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('旁白'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('bubble-preset-narration-wide')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('bubble-preset-narration-wide')),
    );
    await tester.pump();
    expect(selectedPreset?.id, 'narration-wide');
    expect(tester.takeException(), isNull);
  });
}
