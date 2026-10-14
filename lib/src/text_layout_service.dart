import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'models.dart';

/// One source-image-pixel layout for the inspector, preview and PNG exporter.
/// Fixed mode never changes the chosen size or truncates the caption. Auto mode
/// independently chooses the largest fitting original-pixel size in 8–200.
/// Callers
/// may warn on [TextLayoutResult.overflow]; rendering is clipped only by the page.
class TextLayoutService {
  const TextLayoutService();

  TextLayoutResult layout(BubblePlacement bubble, {bool includeStroke = true}) {
    final availableRect = textArea(bubble);
    final availableWidth = math.max(.0001, availableRect.width);
    final availableHeight = math.max(.0001, availableRect.height);
    final requestedSize = bubble.fontSize.isFinite && bubble.fontSize > 0
        ? bubble.fontSize
        : TextStyleLimits.maxFontSize;

    TextPainter create(double size, {bool stroke = false}) {
      final outline = ui.Paint()
        ..color = ui.Color(bubble.textStrokeColorValue)
        ..style = ui.PaintingStyle.stroke
        ..strokeJoin = ui.StrokeJoin.round
        ..strokeWidth = bubble.textStrokeWidth;
      return TextPainter(
        text: TextSpan(
          text: bubble.caption.text,
          style: TextStyle(
            color: stroke ? null : ui.Color(bubble.fontColorValue),
            foreground: stroke ? outline : null,
            fontFamily: bubble.fontFamily,
            fontSize: size,
            height: bubble.lineHeight,
            letterSpacing: bubble.letterSpacing,
            fontWeight: ui.FontWeight.w600,
          ),
        ),
        textAlign: bubble.textAlign,
        textDirection: ui.TextDirection.ltr,
      )..layout(minWidth: availableWidth, maxWidth: availableWidth);
    }

    bool fits(TextPainter painter) =>
        painter.height <= availableHeight + .0001 &&
        painter.computeLineMetrics().every(
              (line) => line.width <= availableWidth + .0001,
            );

    var effectiveSize = bubble.textSizeMode == TextSizeMode.fit
        ? TextStyleLimits.maxFontSize
        : requestedSize;
    var painter = create(effectiveSize);
    if (bubble.textSizeMode == TextSizeMode.fit && !fits(painter)) {
      painter.dispose();
      effectiveSize = TextStyleLimits.minFontSize;
      painter = create(effectiveSize);
      // Keep the complete paragraph at 8 even if it still overflows. Never
      // shrink below the readable lower bound or replace text with ellipses.
      if (fits(painter)) {
        painter.dispose();
        var low = TextStyleLimits.minFontSize;
        var high = TextStyleLimits.maxFontSize;
        for (var attempt = 0; attempt < 20; attempt++) {
          final middle = (low + high) / 2;
          painter = create(middle);
          if (fits(painter)) {
            low = middle;
          } else {
            high = middle;
          }
          painter.dispose();
        }
        effectiveSize = low;
        painter = create(effectiveSize);
      }
    }
    final metrics = painter.computeLineMetrics();
    return TextLayoutResult(
      painter: painter,
      strokePainter: includeStroke && bubble.textStrokeWidth > 0
          ? create(effectiveSize, stroke: true)
          : null,
      effectiveFontSize: effectiveSize,
      overflow: !fits(painter),
      availableRect: availableRect,
      lineCount: metrics.length,
      paintOffset: ui.Offset(
        availableRect.left,
        availableRect.center.dy - painter.height / 2,
      ),
    );
  }

  /// The same interior margins previously used by auto-fit; plain text uses
  /// its complete rectangle. A text outline reserves its own half-stroke.
  ui.Rect textArea(BubblePlacement bubble) {
    final width = math.max(.0001, bubble.width);
    final height = math.max(.0001, bubble.height);
    final shortest = math.min(width, height);
    final thoughtInset = (shortest * .18).clamp(10.0, 34.0);
    final thoughtWidthFactor =
        ((width - thoughtInset * 2) / width).clamp(.42, .78);
    final thoughtHeightFactor =
        ((height - thoughtInset * 2) / height).clamp(.42, .68);
    final widthFactor = switch (bubble.shape) {
      BubbleShape.ellipse || BubbleShape.whisper => .78,
      BubbleShape.rounded => .84,
      BubbleShape.shout => .74,
      BubbleShape.thought => thoughtWidthFactor,
      BubbleShape.plainText => 1.0,
    };
    final heightFactor = switch (bubble.shape) {
      BubbleShape.ellipse || BubbleShape.whisper => .68,
      BubbleShape.rounded => .72,
      BubbleShape.shout => .62,
      BubbleShape.thought => thoughtHeightFactor,
      BubbleShape.plainText => 1.0,
    };
    final stroke = math.max(0.0, bubble.textStrokeWidth);
    return ui.Rect.fromCenter(
      center: ui.Offset(width / 2, height / 2),
      width: math.max(.0001, width * widthFactor - stroke),
      height: math.max(.0001, height * heightFactor - stroke),
    );
  }
}

class TextLayoutResult {
  const TextLayoutResult({
    required this.painter,
    required this.strokePainter,
    required this.effectiveFontSize,
    required this.overflow,
    required this.availableRect,
    required this.lineCount,
    required this.paintOffset,
  });

  final TextPainter painter;
  final TextPainter? strokePainter;
  final double effectiveFontSize;
  final bool overflow;
  // Coordinates relative to the placement's top-left, in original pixels.
  final ui.Rect availableRect;
  final int lineCount;
  final ui.Offset paintOffset;

  void paint(ui.Canvas canvas, ui.Offset placementOrigin) {
    final origin = placementOrigin + paintOffset;
    strokePainter?.paint(canvas, origin);
    painter.paint(canvas, origin);
  }

  void dispose() {
    painter.dispose();
    strokePainter?.dispose();
  }
}
