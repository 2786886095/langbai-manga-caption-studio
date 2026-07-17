import 'dart:math' as math;
import 'models.dart';

class LayoutEngine {
  const LayoutEngine();

  List<BubblePlacement> arrange(
    List<CaptionLine> captions, {
    required int imageWidth,
    required int imageHeight,
  }) {
    if (captions.isEmpty) return const [];
    final margin = imageWidth * .045;
    final gap = imageHeight * .025;
    final columns = captions.length == 1 ? 1 : 2;
    final maxWidth = (imageWidth - margin * 2 - (columns - 1) * gap) / columns;
    final bubbleWidth = math.min(imageWidth * .42, maxWidth);
    final placements = <BubblePlacement>[];
    for (var i = 0; i < captions.length; i++) {
      final spec = captions[i].layout;
      final column = i % columns;
      final row = i ~/ columns;
      final estimatedLines = math.max(
        2,
        (captions[i].text.runes.length / 8).ceil(),
      );
      var height = math.min(
        imageHeight * .27,
        imageHeight * (.09 + estimatedLines * .035),
      );
      var width = bubbleWidth;
      if (spec?.width != null) width = spec!.width!;
      if (spec?.widthPercent != null) {
        width = imageWidth * spec!.widthPercent! / 100;
      }
      if (spec?.height != null) height = spec!.height!;
      if (spec?.heightPercent != null) {
        height = imageHeight * spec!.heightPercent! / 100;
      }
      var x = column == 0 ? margin : imageWidth - margin - width;
      var y = margin + row * (imageHeight * .22 + gap);
      if (spec?.positionPreset != null) {
        final preset = spec!.positionPreset!;
        if (preset.startsWith('左')) x = margin;
        if (preset.startsWith('中') || preset == '居中') {
          x = (imageWidth - width) / 2;
        }
        if (preset.startsWith('右')) x = imageWidth - margin - width;
        if (preset.endsWith('上')) y = margin;
        if (preset.endsWith('中') || preset == '居中') {
          y = (imageHeight - height) / 2;
        }
        if (preset.endsWith('下')) y = imageHeight - margin - height;
      }
      if (spec?.xPercent != null && spec?.yPercent != null) {
        x = imageWidth * spec!.xPercent! / 100;
        y = imageHeight * spec.yPercent! / 100;
      }
      if (spec?.x != null && spec?.y != null) {
        x = spec!.x!;
        y = spec.y!;
      }
      x = x.clamp(0, imageWidth - width);
      y = y.clamp(0, imageHeight - height);
      placements.add(
        BubblePlacement(
          caption: captions[i],
          x: x,
          y: y,
          width: width,
          height: height,
          tailX: .5,
          shape: spec?.shape ?? BubbleShape.ellipse,
          tailDirection: spec?.tailDirection ??
              (column == 0 ? TailDirection.downRight : TailDirection.downLeft),
          fontFamily: spec?.fontFamily ?? 'Microsoft YaHei',
          fontColorValue: spec?.fontColorValue ?? 0xff141518,
          fontSize: spec?.fontSize ?? 34,
          lineHeight: spec?.lineHeight ?? 1.25,
          strokeWidth: spec?.strokeWidth ?? 3,
        ),
      );
    }
    return placements;
  }
}
