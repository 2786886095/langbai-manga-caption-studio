import 'dart:typed_data';
import 'dart:ui' as ui;

import 'app_localization.dart';

// Append new shapes so persisted or external references to old indices stay valid.
enum BubbleShape { ellipse, rounded, shout, thought, whisper, plainText }

enum TailDirection { upLeft, upRight, downLeft, downRight }

enum TextSizeMode { fixed, fit }

// Shared by the inspector, BCS parser and layout engine (original-image pixels).
abstract final class TextStyleLimits {
  static const minFontSize = 8.0;
  static const maxFontSize = 200.0;
  static const minLineHeight = .8;
  static const maxLineHeight = 3.0;
  static const minStrokeWidth = 0.0;
  static const maxStrokeWidth = 20.0;
  static const minLetterSpacing = -10.0;
  static const maxLetterSpacing = 50.0;
}

enum PlacedImageFit { contain, cover }

enum PlacedImageLayer { behindBubbles, aboveBubbles }

const _keepBubbleBinding = Object();

class PlacedImage {
  const PlacedImage({
    required this.id,
    required this.name,
    required this.bytes,
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.opacity = 1,
    this.fit = PlacedImageFit.contain,
    this.cropX = .5,
    this.cropY = .5,
    this.layer = PlacedImageLayer.aboveBubbles,
    this.bubbleId,
  });

  final String id;
  final String name;
  final Uint8List bytes;
  final ui.Image image;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double opacity;
  final PlacedImageFit fit;
  final double cropX;
  final double cropY;
  final PlacedImageLayer layer;
  final String? bubbleId;

  bool get isInsideBubble => bubbleId != null;

  PlacedImage copyWith({
    String? id,
    String? name,
    Uint8List? bytes,
    ui.Image? image,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? opacity,
    PlacedImageFit? fit,
    double? cropX,
    double? cropY,
    PlacedImageLayer? layer,
    Object? bubbleId = _keepBubbleBinding,
  }) =>
      PlacedImage(
        id: id ?? this.id,
        name: name ?? this.name,
        bytes: bytes ?? this.bytes,
        image: image ?? this.image,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        fit: fit ?? this.fit,
        cropX: cropX ?? this.cropX,
        cropY: cropY ?? this.cropY,
        layer: layer ?? this.layer,
        bubbleId: identical(bubbleId, _keepBubbleBinding)
            ? this.bubbleId
            : bubbleId as String?,
      );
}

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
    this.textSizeMode,
    this.textStrokeWidth,
    this.textStrokeColorValue,
    this.letterSpacing,
    this.textAlign,
    this.fontAssetId,
    this.fontDisplayName,
    this.styleId,
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
  final TextSizeMode? textSizeMode;
  final double? textStrokeWidth;
  final int? textStrokeColorValue;
  final double? letterSpacing;
  final ui.TextAlign? textAlign;
  final String? fontAssetId;
  final String? fontDisplayName;
  final String? styleId;
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
    this.fontSize = TextStyleLimits.maxFontSize,
    // New objects use global 8–200 auto sizing. Explicit saved manual values
    // are restored by the codec rather than replaced by these defaults.
    this.textSizeMode = TextSizeMode.fit,
    this.textStrokeWidth = 0,
    this.textStrokeColorValue = 0xff000000,
    this.letterSpacing = 0,
    this.textAlign = ui.TextAlign.center,
    this.fontAssetId,
    this.fontDisplayName,
    this.styleId,
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
  final TextSizeMode textSizeMode;
  final double textStrokeWidth;
  final int textStrokeColorValue;
  final double letterSpacing;
  final ui.TextAlign textAlign;
  final String? fontAssetId;
  final String? fontDisplayName;
  final String? styleId;
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
    TextSizeMode? textSizeMode,
    double? textStrokeWidth,
    int? textStrokeColorValue,
    double? letterSpacing,
    ui.TextAlign? textAlign,
    Object? fontAssetId = _keepBubbleBinding,
    Object? fontDisplayName = _keepBubbleBinding,
    Object? styleId = _keepBubbleBinding,
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
        textSizeMode: textSizeMode ?? this.textSizeMode,
        textStrokeWidth: textStrokeWidth ?? this.textStrokeWidth,
        textStrokeColorValue: textStrokeColorValue ?? this.textStrokeColorValue,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        textAlign: textAlign ?? this.textAlign,
        fontAssetId: identical(fontAssetId, _keepBubbleBinding)
            ? this.fontAssetId
            : fontAssetId as String?,
        fontDisplayName: identical(fontDisplayName, _keepBubbleBinding)
            ? this.fontDisplayName
            : fontDisplayName as String?,
        styleId: identical(styleId, _keepBubbleBinding)
            ? this.styleId
            : styleId as String?,
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
  List<PlacedImage> placedImages = [];
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
      // Auto sizing ignores the stored manual size; its actual overflow is
      // measured by TextLayoutService, not this fixed-size approximation.
      if (bubble.textSizeMode == TextSizeMode.fixed &&
          estimatedLines * bubble.fontSize * bubble.lineHeight >
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

  void dispose() {
    image.dispose();
    for (final placed in placedImages) {
      placed.image.dispose();
    }
  }
}

int _pageIdCounter = 0;
String _newPageId() =>
    'page-${DateTime.now().microsecondsSinceEpoch}-${_pageIdCounter++}';

int _placedImageIdCounter = 0;
String newPlacedImageId() =>
    'asset-${DateTime.now().microsecondsSinceEpoch}-${_placedImageIdCounter++}';
