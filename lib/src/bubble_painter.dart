import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'models.dart';

class BubbleTailGeometry {
  const BubbleTailGeometry({
    required this.start,
    required this.tip,
    required this.end,
  });

  final Offset start;
  final Offset tip;
  final Offset end;
}

BubbleTailGeometry bubbleTailGeometry(Rect rect, BubblePlacement bubble) {
  final length = (rect.shortestSide * .17).clamp(12.0, 30.0);
  final horizontalHalfBase = (rect.width * .042).clamp(8.0, 18.0);
  final leftAnchor = rect.left + rect.width * .24;
  final rightAnchor = rect.right - rect.width * .24;
  switch (bubble.tailDirection) {
    case TailDirection.upLeft:
      return BubbleTailGeometry(
        start: Offset(
          leftAnchor - horizontalHalfBase,
          rect.top + rect.height * .13,
        ),
        tip: Offset(leftAnchor - length * .72, rect.top - length * .72),
        end: Offset(
          leftAnchor + horizontalHalfBase,
          rect.top + rect.height * .13,
        ),
      );
    case TailDirection.upRight:
      return BubbleTailGeometry(
        start: Offset(
          rightAnchor - horizontalHalfBase,
          rect.top + rect.height * .13,
        ),
        tip: Offset(rightAnchor + length * .72, rect.top - length * .72),
        end: Offset(
          rightAnchor + horizontalHalfBase,
          rect.top + rect.height * .13,
        ),
      );
    case TailDirection.downLeft:
      return BubbleTailGeometry(
        start: Offset(
          leftAnchor - horizontalHalfBase,
          rect.bottom - rect.height * .13,
        ),
        tip: Offset(leftAnchor - length * .72, rect.bottom + length * .72),
        end: Offset(
          leftAnchor + horizontalHalfBase,
          rect.bottom - rect.height * .13,
        ),
      );
    case TailDirection.downRight:
      return BubbleTailGeometry(
        start: Offset(
          rightAnchor - horizontalHalfBase,
          rect.bottom - rect.height * .13,
        ),
        tip: Offset(rightAnchor + length * .72, rect.bottom + length * .72),
        end: Offset(
          rightAnchor + horizontalHalfBase,
          rect.bottom - rect.height * .13,
        ),
      );
  }
}

List<Offset> bubbleResizeHandles(Rect rect) => [
      rect.topLeft,
      rect.topCenter,
      rect.topRight,
      rect.centerRight,
      rect.bottomRight,
      rect.bottomCenter,
      rect.bottomLeft,
      rect.centerLeft,
    ];

bool bubbleHasPointer(BubbleShape shape) =>
    shape == BubbleShape.ellipse ||
    shape == BubbleShape.thought ||
    shape == BubbleShape.whisper;

Path _bubbleTailPath(BubbleTailGeometry tail) {
  final firstControl = Offset.lerp(tail.start, tail.tip, .62)!;
  final secondControl = Offset.lerp(tail.tip, tail.end, .38)!;
  return Path()
    ..moveTo(tail.start.dx, tail.start.dy)
    ..quadraticBezierTo(
      firstControl.dx,
      firstControl.dy,
      tail.tip.dx,
      tail.tip.dy,
    )
    ..quadraticBezierTo(
      secondControl.dx,
      secondControl.dy,
      tail.end.dx,
      tail.end.dy,
    )
    ..close();
}

Path _thoughtCloudPath(Rect rect) {
  var cloud = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: rect.center,
          width: rect.width * .82,
          height: rect.height * .66,
        ),
        Radius.circular(rect.shortestSide * .28),
      ),
    );
  const count = 14;
  for (var i = 0; i < count; i++) {
    final angle = math.pi * 2 * i / count;
    final center = Offset(
      rect.center.dx + math.cos(angle) * rect.width * .40,
      rect.center.dy + math.sin(angle) * rect.height * .38,
    );
    final radius = rect.shortestSide * (i.isEven ? .145 : .125);
    cloud = Path.combine(
      PathOperation.union,
      cloud,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
  }
  return cloud;
}

Path _bubbleShapePath(Rect rect, BubbleShape shape) {
  switch (shape) {
    case BubbleShape.ellipse:
      return Path()..addOval(rect);
    case BubbleShape.rounded:
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(rect.shortestSide * .20),
          ),
        );
    case BubbleShape.shout:
      final path = Path();
      const points = 16;
      for (var i = 0; i < points; i++) {
        final angle = -math.pi / 2 + math.pi * 2 * i / points;
        final scale = i.isEven ? 1.0 : .89;
        final point = Offset(
          rect.center.dx + math.cos(angle) * rect.width * .5 * scale,
          rect.center.dy + math.sin(angle) * rect.height * .5 * scale,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      return path..close();
    case BubbleShape.thought:
      return _thoughtCloudPath(rect);
    case BubbleShape.whisper:
      return Path()..addOval(rect);
  }
}

bool bubbleContainsPoint(BubblePlacement bubble, Offset point) {
  final rect = Rect.fromLTWH(
    bubble.x,
    bubble.y,
    bubble.width,
    bubble.height,
  );
  final shapePath = _bubbleShapePath(rect, bubble.shape);
  if (shapePath.contains(point)) return true;
  if (!bubbleHasPointer(bubble.shape)) return false;

  final tail = bubbleTailGeometry(rect, bubble);
  if (bubble.shape != BubbleShape.thought) {
    return _bubbleTailPath(tail).contains(point);
  }

  final anchor = Offset.lerp(tail.start, tail.end, .5)!;
  for (final item in const [(.38, .066), (.68, .045), (.94, .027)]) {
    final center = Offset.lerp(anchor, tail.tip, item.$1)!;
    if ((point - center).distance <= rect.shortestSide * item.$2) return true;
  }
  return false;
}

int hitTestBubble(List<BubblePlacement> bubbles, Offset point) {
  for (var index = bubbles.length - 1; index >= 0; index--) {
    if (bubbleContainsPoint(bubbles[index], point)) {
      return index;
    }
  }
  return -1;
}

class PagePainter extends CustomPainter {
  PagePainter({
    required this.page,
    this.selectedIndex,
    this.showBubbles = true,
    this.sourceImage,
    super.repaint,
  }) : _paintSignature = Object.hashAll([
          page.image,
          sourceImage,
          selectedIndex,
          showBubbles,
          for (final bubble in page.placements) ...[
            bubble.caption.text,
            bubble.x,
            bubble.y,
            bubble.width,
            bubble.height,
            bubble.shape,
            bubble.tailDirection,
            bubble.fontSize,
            bubble.lineHeight,
            bubble.strokeWidth,
            bubble.fillOpacity,
            bubble.fontFamily,
            bubble.fontColorValue,
          ],
        ]);
  final ImagePage page;
  final int? selectedIndex;
  final bool showBubbles;
  final ui.Image? sourceImage;
  final int _paintSignature;
  final Map<int, ({int signature, TextPainter painter})> _textCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final raster = sourceImage ?? page.image;
    final source = Rect.fromLTWH(
      0,
      0,
      raster.width.toDouble(),
      raster.height.toDouble(),
    );
    final destination = Offset.zero & size;
    canvas.drawImageRect(
      raster,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (!showBubbles) return;
    final sx = size.width / page.originalWidth;
    final sy = size.height / page.originalHeight;
    for (var i = 0; i < page.placements.length; i++) {
      final bubble = page.placements[i];
      final rect = Rect.fromLTWH(
        bubble.x * sx,
        bubble.y * sy,
        bubble.width * sx,
        bubble.height * sy,
      );
      _drawBubble(canvas, rect, bubble, sx, sy, selectedIndex == i, i);
    }
  }

  void _drawBubble(
    Canvas canvas,
    Rect rect,
    BubblePlacement bubble,
    double sx,
    double sy,
    bool selected,
    int bubbleIndex,
  ) {
    final fillColor = bubble.shape == BubbleShape.rounded
        ? const Color(0xfff5f5f3)
        : Colors.white;
    final fill = Paint()
      ..color = fillColor.withOpacity(bubble.fillOpacity.clamp(0, 1));
    final stroke = Paint()
      ..color = const Color(0xff17181b)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (bubble.strokeWidth * sx).clamp(1.5, 7);
    final shapePath = _bubbleShapePath(rect, bubble.shape);
    final tail = bubbleTailGeometry(rect, bubble);
    if (bubble.shape == BubbleShape.thought) {
      canvas.drawPath(shapePath, fill);
      canvas.drawPath(shapePath, stroke);
      final anchor = Offset.lerp(tail.start, tail.end, .5)!;
      for (final item in const [(.38, .066), (.68, .045), (.94, .027)]) {
        final center = Offset.lerp(anchor, tail.tip, item.$1)!;
        final radius = rect.shortestSide * item.$2;
        canvas.drawCircle(center, radius, fill);
        canvas.drawCircle(center, radius, stroke);
      }
    } else if (bubble.shape == BubbleShape.ellipse ||
        bubble.shape == BubbleShape.whisper) {
      final tailPath = _bubbleTailPath(tail);
      final combined = Path.combine(PathOperation.union, shapePath, tailPath);
      canvas.drawPath(combined, fill);
      if (bubble.shape == BubbleShape.whisper) {
        _drawDashedPath(canvas, combined, stroke, dash: 8 * sx, gap: 6 * sx);
      } else {
        canvas.drawPath(combined, stroke);
      }
    } else {
      canvas.drawPath(shapePath, fill);
      canvas.drawPath(shapePath, stroke);
    }

    final textWidthFactor = switch (bubble.shape) {
      BubbleShape.ellipse => .78,
      BubbleShape.rounded => .84,
      BubbleShape.shout => .74,
      BubbleShape.thought => .78,
      BubbleShape.whisper => .78,
    };
    final textHeightFactor = switch (bubble.shape) {
      BubbleShape.ellipse => .68,
      BubbleShape.rounded => .72,
      BubbleShape.shout => .62,
      BubbleShape.thought => .68,
      BubbleShape.whisper => .68,
    };
    TextPainter createTextPainter(double size) => TextPainter(
          text: TextSpan(
            text: bubble.caption.text,
            style: TextStyle(
              color: Color(bubble.fontColorValue),
              fontFamily: bubble.fontFamily,
              fontSize: size,
              height: bubble.lineHeight,
              fontWeight: FontWeight.w600,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr,
          maxLines: 6,
          ellipsis: '…',
        )..layout(maxWidth: rect.width * textWidthFactor);

    final textSignature = Object.hash(
      bubble.caption.text,
      bubble.fontSize,
      bubble.fontFamily,
      bubble.fontColorValue,
      bubble.lineHeight,
      bubble.shape,
      rect.width,
      rect.height,
      sy,
    );
    final cached = _textCache[bubbleIndex];
    late final TextPainter painter;
    if (cached != null && cached.signature == textSignature) {
      painter = cached.painter;
    } else {
      var fittedSize = (bubble.fontSize * sy).clamp(12.0, 64.0);
      var fittedPainter = createTextPainter(fittedSize);
      final availableHeight = rect.height * textHeightFactor;
      while (fittedPainter.height > availableHeight && fittedSize > 12) {
        fittedSize -= 1;
        fittedPainter = createTextPainter(fittedSize);
      }
      painter = fittedPainter;
      _textCache[bubbleIndex] = (
        signature: textSignature,
        painter: painter,
      );
    }
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
    if (selected) {
      canvas.drawRect(
        rect.inflate(5),
        Paint()
          ..color = const Color(0xffe94d72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final handlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final handleStroke = Paint()
        ..color = const Color(0xffe94d72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final point in bubbleResizeHandles(rect)) {
        final handle = Rect.fromCenter(center: point, width: 10, height: 10);
        canvas.drawRect(handle, handlePaint);
        canvas.drawRect(handle, handleStroke);
      }
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + dash, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant PagePainter oldDelegate) =>
      _paintSignature != oldDelegate._paintSignature;
}
