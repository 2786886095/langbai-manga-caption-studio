import 'dart:typed_data';
import 'dart:ui' as ui;

import 'app_localization.dart';

enum BubbleShape { ellipse, rounded, shout, thought, whisper }

enum TailDirection { upLeft, upRight, downLeft, downRight }

const defaultBubbleFontFamily = 'Noto Sans SC';

String normalizeBubbleFontFamily(String? family) {
  final value = family?.trim() ?? '';
  return switch (value) {
    '' ||
    'Microsoft YaHei' ||
    '微软雅黑' ||
    'SimHei' ||
    '黑体' ||
    'Noto Sans CJK SC' ||
    'Noto Sans' =>
      defaultBubbleFontFamily,
    'SimSun' || '宋体' => 'ZCOOL XiaoWei',
    'KaiTi' || '楷体' => 'Ma Shan Zheng',
    _ => value,
  };
}

class CaptionLayoutSpec {
  const CaptionLayoutSpec({
    this.x,
    this.y,
    this.width,
    this.height,
    this.xPercent,
    this.yPercent,
    this.widthPercent,
    this.heightPercent,
    this.positionPreset,
    this.shape,
    this.tailDirection,
    this.tailPosition,
    this.fontFamily,
    this.fontColorValue,
    this.fontSize,
    this.lineHeight,
    this.strokeWidth,
    this.fillOpacity,
  });

  final double? x;
  final double? y;
  final double? width;
  final double? height;
  final double? xPercent;
  final double? yPercent;
  final double? widthPercent;
  final double? heightPercent;
  final String? positionPreset;
  final BubbleShape? shape;
  final TailDirection? tailDirection;
  final double? tailPosition;
  final String? fontFamily;
  final int? fontColorValue;
  final double? fontSize;
  final double? lineHeight;
  final double? strokeWidth;
  final double? fillOpacity;

  bool get hasExplicitPosition =>
      (x != null && y != null) ||
      (xPercent != null && yPercent != null) ||
      positionPreset != null;
}

class CaptionLine {
  const CaptionLine({
    required this.speaker,
    required this.text,
    this.layout,
    this.bubbleId = '',
  });
  final String speaker;
  final String text;
  final CaptionLayoutSpec? layout;
  final String bubbleId;

  CaptionLine copyWith({
    String? speaker,
    String? text,
    CaptionLayoutSpec? layout,
    String? bubbleId,
  }) =>
      CaptionLine(
        speaker: speaker ?? this.speaker,
        text: text ?? this.text,
        layout: layout ?? this.layout,
        bubbleId: bubbleId ?? this.bubbleId,
      );
}

class BubblePlacement {
  const BubblePlacement({
    required this.caption,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.shape = BubbleShape.ellipse,
    this.tailX = .5,
    this.tailY = 1.15,
    this.fontSize = 34,
    this.lineHeight = 1.25,
    this.strokeWidth = 3,
    this.fillOpacity = 1,
    this.fontFamily = defaultBubbleFontFamily,
    this.fontColorValue = 0xff141518,
    this.tailDirection = TailDirection.downRight,
  });
  final CaptionLine caption;
  final double x;
  final double y;
  final double width;
  final double height;
  final BubbleShape shape;
  final double tailX;
  final double tailY;
  final double fontSize;
  final double lineHeight;
  final double strokeWidth;
  final double fillOpacity;
  final String fontFamily;
  final int fontColorValue;
  final TailDirection tailDirection;

  BubblePlacement copyWith({
    CaptionLine? caption,
    double? x,
    double? y,
    double? width,
    double? height,
    BubbleShape? shape,
    double? tailX,
    double? tailY,
    double? fontSize,
    double? lineHeight,
    double? strokeWidth,
    double? fillOpacity,
    String? fontFamily,
    int? fontColorValue,
    TailDirection? tailDirection,
  }) =>
      BubblePlacement(
        caption: caption ?? this.caption,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        shape: shape ?? this.shape,
        tailX: tailX ?? this.tailX,
        tailY: tailY ?? this.tailY,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        fillOpacity: fillOpacity ?? this.fillOpacity,
        fontFamily: fontFamily ?? this.fontFamily,
        fontColorValue: fontColorValue ?? this.fontColorValue,
        tailDirection: tailDirection ?? this.tailDirection,
      );
}

class ImagePage {
  ImagePage({
    required this.name,
    required this.bytes,
    required this.image,
    int? originalWidth,
    int? originalHeight,
    String? pageId,
    this.orderRank = 0,
  })  : originalWidth = originalWidth ?? image.width,
        originalHeight = originalHeight ?? image.height,
        pageId = pageId ?? _newPageId();
  final String pageId;
  int orderRank;
  final String name;
  final Uint8List bytes;
  final ui.Image image;
  final int originalWidth;
  final int originalHeight;
  List<CaptionLine> captions = [];
  List<BubblePlacement> placements = [];
  bool approved = false;

  List<String> get validationIssues {
    final issues = <String>[];
    if (captions.length != placements.length) {
      issues.add('字幕与气泡数量不一致');
    }
    for (var i = 0; i < placements.length; i++) {
      final bubble = placements[i];
      if (bubble.caption.text.trim().isEmpty) issues.add('气泡 ${i + 1} 没有文字');
      if (bubble.width < 80 || bubble.height < 56) {
        issues.add('气泡 ${i + 1} 尺寸过小');
      }
      if (bubble.x < 0 ||
          bubble.y < 0 ||
          bubble.x + bubble.width > originalWidth ||
          bubble.y + bubble.height > originalHeight) {
        issues.add('气泡 ${i + 1} 超出图片边界');
      }
      final estimatedCharactersPerLine =
          (bubble.width / (bubble.fontSize * .9)).floor().clamp(1, 1000);
      final estimatedLines =
          (bubble.caption.text.runes.length / estimatedCharactersPerLine)
              .ceil()
              .clamp(1, 1000);
      if (estimatedLines * bubble.fontSize * bubble.lineHeight >
          bubble.height * .72) {
        issues.add('气泡 ${i + 1} 的文字可能溢出');
      }
      final rect = ui.Rect.fromLTWH(
        bubble.x,
        bubble.y,
        bubble.width,
        bubble.height,
      );
      for (var j = i + 1; j < placements.length; j++) {
        final other = placements[j];
        final otherRect = ui.Rect.fromLTWH(
          other.x,
          other.y,
          other.width,
          other.height,
        );
        final overlap = rect.intersect(otherRect);
        if (!overlap.isEmpty &&
            overlap.width * overlap.height >
                bubble.width * bubble.height * .08) {
          issues.add('气泡 ${i + 1} 与气泡 ${j + 1} 明显重叠');
        }
      }
    }
    if (placements.isEmpty) issues.add('没有匹配到字幕');
    return issues.map(tr).toList(growable: false);
  }

  int get issueCount {
    final count = validationIssues.length;
    if (approved && count == 0) return 0;
    return count == 0 ? 1 : count;
  }

  double get aspectRatio => originalWidth / originalHeight;

  void dispose() => image.dispose();
}

int _pageIdCounter = 0;
String _newPageId() =>
    'page-${DateTime.now().microsecondsSinceEpoch}-${_pageIdCounter++}';
