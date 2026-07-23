import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_localization.dart';
import 'app_theme.dart';
import 'bubble_painter.dart';
import 'models.dart';

enum BubblePresetCategory { dialogue, narration, thought, whisper, shout }

extension BubblePresetCategoryLabel on BubblePresetCategory {
  String get label => switch (this) {
        BubblePresetCategory.dialogue => '对话',
        BubblePresetCategory.narration => '旁白',
        BubblePresetCategory.thought => '心理',
        BubblePresetCategory.whisper => '耳语',
        BubblePresetCategory.shout => '惊喊',
      };
}

class BubbleStylePreset {
  const BubbleStylePreset({
    required this.id,
    required this.label,
    required this.category,
    required this.shape,
    required this.widthFraction,
    required this.heightFraction,
    this.strokeWidth = 3,
  });

  final String id;
  final String label;
  final BubblePresetCategory category;
  final BubbleShape shape;
  final double widthFraction;
  final double heightFraction;
  final double strokeWidth;

  double get aspectRatio => widthFraction / heightFraction;

  BubblePlacement applyTo(BubblePlacement bubble, ImagePage page) {
    final pageWidth = page.originalWidth.toDouble();
    final pageHeight = page.originalHeight.toDouble();
    final minimumWidth = math.min(80.0, pageWidth);
    final minimumHeight = math.min(56.0, pageHeight);
    final width = (pageWidth * widthFraction).clamp(minimumWidth, pageWidth);
    final height =
        (pageHeight * heightFraction).clamp(minimumHeight, pageHeight);
    final centerX = bubble.x + bubble.width / 2;
    final centerY = bubble.y + bubble.height / 2;
    final x = (centerX - width / 2).clamp(0.0, pageWidth - width);
    final y = (centerY - height / 2).clamp(0.0, pageHeight - height);

    return bubble.copyWith(
      x: x,
      y: y,
      width: width,
      height: height,
      shape: shape,
      strokeWidth: strokeWidth,
    );
  }

  bool matches(BubblePlacement bubble, Size imageSize) {
    if (bubble.shape != shape ||
        (bubble.strokeWidth - strokeWidth).abs() > .25) {
      return false;
    }
    final targetWidth = imageSize.width * widthFraction;
    final targetHeight = imageSize.height * heightFraction;
    return (bubble.width - targetWidth).abs() / math.max(1, targetWidth) <
            .05 &&
        (bubble.height - targetHeight).abs() / math.max(1, targetHeight) < .05;
  }
}

const bubbleStylePresets = <BubbleStylePreset>[
  BubbleStylePreset(
    id: 'dialogue-classic',
    label: '经典',
    category: BubblePresetCategory.dialogue,
    shape: BubbleShape.ellipse,
    widthFraction: .34,
    heightFraction: .17,
  ),
  BubbleStylePreset(
    id: 'dialogue-compact',
    label: '紧凑',
    category: BubblePresetCategory.dialogue,
    shape: BubbleShape.ellipse,
    widthFraction: .26,
    heightFraction: .15,
  ),
  BubbleStylePreset(
    id: 'dialogue-wide',
    label: '横向',
    category: BubblePresetCategory.dialogue,
    shape: BubbleShape.ellipse,
    widthFraction: .48,
    heightFraction: .15,
  ),
  BubbleStylePreset(
    id: 'dialogue-vertical',
    label: '纵向',
    category: BubblePresetCategory.dialogue,
    shape: BubbleShape.ellipse,
    widthFraction: .18,
    heightFraction: .34,
  ),
  BubbleStylePreset(
    id: 'dialogue-light',
    label: '轻线',
    category: BubblePresetCategory.dialogue,
    shape: BubbleShape.ellipse,
    widthFraction: .38,
    heightFraction: .19,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'narration-classic',
    label: '标准',
    category: BubblePresetCategory.narration,
    shape: BubbleShape.rounded,
    widthFraction: .38,
    heightFraction: .16,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'narration-compact',
    label: '紧凑',
    category: BubblePresetCategory.narration,
    shape: BubbleShape.rounded,
    widthFraction: .28,
    heightFraction: .13,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'narration-wide',
    label: '横幅',
    category: BubblePresetCategory.narration,
    shape: BubbleShape.rounded,
    widthFraction: .52,
    heightFraction: .14,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'narration-caption',
    label: '窄条',
    category: BubblePresetCategory.narration,
    shape: BubbleShape.rounded,
    widthFraction: .44,
    heightFraction: .10,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'narration-vertical',
    label: '竖框',
    category: BubblePresetCategory.narration,
    shape: BubbleShape.rounded,
    widthFraction: .22,
    heightFraction: .28,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'thought-classic',
    label: '标准',
    category: BubblePresetCategory.thought,
    shape: BubbleShape.thought,
    widthFraction: .35,
    heightFraction: .20,
  ),
  BubbleStylePreset(
    id: 'thought-compact',
    label: '紧凑',
    category: BubblePresetCategory.thought,
    shape: BubbleShape.thought,
    widthFraction: .28,
    heightFraction: .17,
  ),
  BubbleStylePreset(
    id: 'thought-wide',
    label: '横向',
    category: BubblePresetCategory.thought,
    shape: BubbleShape.thought,
    widthFraction: .49,
    heightFraction: .18,
  ),
  BubbleStylePreset(
    id: 'thought-vertical',
    label: '纵向',
    category: BubblePresetCategory.thought,
    shape: BubbleShape.thought,
    widthFraction: .22,
    heightFraction: .32,
  ),
  BubbleStylePreset(
    id: 'whisper-classic',
    label: '标准',
    category: BubblePresetCategory.whisper,
    shape: BubbleShape.whisper,
    widthFraction: .34,
    heightFraction: .17,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'whisper-compact',
    label: '短句',
    category: BubblePresetCategory.whisper,
    shape: BubbleShape.whisper,
    widthFraction: .27,
    heightFraction: .15,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'whisper-wide',
    label: '低声',
    category: BubblePresetCategory.whisper,
    shape: BubbleShape.whisper,
    widthFraction: .47,
    heightFraction: .15,
    strokeWidth: 2,
  ),
  BubbleStylePreset(
    id: 'shout-classic',
    label: '标准',
    category: BubblePresetCategory.shout,
    shape: BubbleShape.shout,
    widthFraction: .34,
    heightFraction: .19,
  ),
  BubbleStylePreset(
    id: 'shout-compact',
    label: '短促',
    category: BubblePresetCategory.shout,
    shape: BubbleShape.shout,
    widthFraction: .27,
    heightFraction: .18,
  ),
  BubbleStylePreset(
    id: 'shout-wide',
    label: '爆发',
    category: BubblePresetCategory.shout,
    shape: BubbleShape.shout,
    widthFraction: .48,
    heightFraction: .18,
  ),
  BubbleStylePreset(
    id: 'shout-vertical',
    label: '纵向',
    category: BubblePresetCategory.shout,
    shape: BubbleShape.shout,
    widthFraction: .23,
    heightFraction: .31,
  ),
];

class BubblePresetCatalog extends StatelessWidget {
  const BubblePresetCatalog({
    super.key,
    required this.selectedCategory,
    required this.bubble,
    required this.imageSize,
    required this.onCategoryChanged,
    required this.onPresetSelected,
    this.compact = false,
  });

  final BubblePresetCategory selectedCategory;
  final BubblePlacement bubble;
  final Size imageSize;
  final ValueChanged<BubblePresetCategory> onCategoryChanged;
  final ValueChanged<BubbleStylePreset> onPresetSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final presets = bubbleStylePresets
        .where((preset) => preset.category == selectedCategory)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in BubblePresetCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: LText(category.label),
                    selected: category == selectedCategory,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onCategoryChanged(category),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in presets)
              _BubblePresetButton(
                bubble: bubble,
                imageSize: imageSize,
                preset: preset,
                width: compact ? 72 : 82,
                onPressed: () => onPresetSelected(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _BubblePresetButton extends StatelessWidget {
  const _BubblePresetButton({
    required this.bubble,
    required this.imageSize,
    required this.preset,
    required this.width,
    required this.onPressed,
  });

  final BubblePlacement bubble;
  final Size imageSize;
  final BubbleStylePreset preset;
  final double width;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final selected = preset.matches(bubble, imageSize);
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.category.label}${preset.label}预设',
      child: Material(
        color: selected ? AppColors.blush : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.pink : AppColors.line,
          ),
        ),
        child: InkWell(
          key: ValueKey('bubble-preset-${preset.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: width,
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BubblePresetPreview(
                  preset: preset,
                  color: selected ? AppColors.pink : AppColors.ink,
                ),
                const SizedBox(height: 2),
                LText(
                  preset.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.pink : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BubblePresetPreview extends StatelessWidget {
  const BubblePresetPreview({
    super.key,
    required this.preset,
    this.color = const Color(0xff17181b),
  });

  final BubbleStylePreset preset;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _BubblePresetPreviewPainter(preset: preset, color: color),
        size: const Size(54, 32),
      );
}

class _BubblePresetPreviewPainter extends CustomPainter {
  const _BubblePresetPreviewPainter({
    required this.preset,
    required this.color,
  });

  final BubbleStylePreset preset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ratio = preset.aspectRatio;
    final maxWidth = size.width - 6;
    final maxHeight = size.height - 6;
    var width = maxWidth;
    var height = width / ratio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: math.max(8, width),
      height: math.max(8, height),
    );
    final bubble = BubblePlacement(
      caption: const CaptionLine(speaker: '', text: ''),
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      shape: preset.shape,
      strokeWidth: preset.strokeWidth,
      tailDirection: TailDirection.downLeft,
    );
    final path = bubbleOutlinePath(rect, bubble);
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = preset.strokeWidth.clamp(1.3, 2.4);
    canvas.drawPath(path, fill);
    if (preset.shape == BubbleShape.whisper) {
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          canvas.drawPath(
            metric.extractPath(
              distance,
              math.min(distance + 3, metric.length),
            ),
            stroke,
          );
          distance += 5;
        }
      }
    } else {
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePresetPreviewPainter oldDelegate) =>
      preset != oldDelegate.preset || color != oldDelegate.color;
}
