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

double _pillPerimeter(Size size) {
  final diameter = math.min(size.width, size.height);
  final straight = math.max(size.width, size.height) - diameter;
  return math.pi * diameter + straight * 2;
}

List<Offset> _pillPoints(Rect rect, int count) {
  final radius = rect.shortestSide / 2;
  final straight = math.max(rect.width, rect.height) - radius * 2;
  final semicircle = math.pi * radius;
  final perimeter = straight * 2 + semicircle * 2;

  Offset pointAt(double distance) {
    var cursor = distance % perimeter;
    if (rect.width >= rect.height) {
      if (cursor <= straight) {
        return Offset(rect.left + radius + cursor, rect.top);
      }
      cursor -= straight;
      if (cursor <= semicircle) {
        final angle = -math.pi / 2 + cursor / radius;
        return Offset(
          rect.right - radius + math.cos(angle) * radius,
          rect.center.dy + math.sin(angle) * radius,
        );
      }
      cursor -= semicircle;
      if (cursor <= straight) {
        return Offset(rect.right - radius - cursor, rect.bottom);
      }
      cursor -= straight;
      final angle = math.pi / 2 + cursor / radius;
      return Offset(
        rect.left + radius + math.cos(angle) * radius,
        rect.center.dy + math.sin(angle) * radius,
      );
    }

    if (cursor <= straight) {
      return Offset(rect.right, rect.top + radius + cursor);
    }
    cursor -= straight;
    if (cursor <= semicircle) {
      final angle = cursor / radius;
      return Offset(
        rect.center.dx + math.cos(angle) * radius,
        rect.bottom - radius + math.sin(angle) * radius,
      );
    }
    cursor -= semicircle;
    if (cursor <= straight) {
      return Offset(rect.left, rect.bottom - radius - cursor);
    }
    cursor -= straight;
    final angle = math.pi + cursor / radius;
    return Offset(
      rect.center.dx + math.cos(angle) * radius,
      rect.top + radius + math.sin(angle) * radius,
    );
  }

  return List.generate(
    count,
    (index) => pointAt(perimeter * index / count),
    growable: false,
  );
}

double _circumradius(Offset first, Offset second, Offset third) {
  final firstToSecond = (second - first).distance;
  final secondToThird = (third - second).distance;
  final thirdToFirst = (first - third).distance;
  final twiceArea = ((second - first).dx * (third - first).dy -
          (second - first).dy * (third - first).dx)
      .abs();
  if (twiceArea < .0001) return firstToSecond / 2;
  return firstToSecond * secondToThird * thirdToFirst / (2 * twiceArea);
}

Path _thoughtCloudPath(Rect rect) {
  if (rect.isEmpty) return Path();
  final shortest = rect.shortestSide;
  if (shortest < 8) return Path()..addOval(rect);

  // The body is a capsule decorated with true circular arcs. Both the number
  // and the radius of the lobes are derived from the current perimeter, so a
  // resize adds/removes complete lobes instead of stretching fixed circles.
  final perimeter = _pillPerimeter(rect.size);
  final targetLobeSize = (shortest * .55).clamp(48.0, 105.0);
  final minimumForLongSide = (perimeter / shortest).ceil();
  final lobeCount = math
      .max(6, math.max((perimeter / targetLobeSize).ceil(), minimumForLongSide))
      .clamp(6, 32);
  final protrusion = perimeter / lobeCount * .22;
  final inner = rect.deflate(protrusion);
  if (inner.width <= 2 || inner.height <= 2) {
    return Path()..addOval(rect);
  }

  final points = _pillPoints(inner, lobeCount);
  final distanceOnPerimeter = _pillPerimeter(inner.size) / lobeCount;
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var index = 0; index < points.length; index++) {
    final first = points[index];
    final second = points[(index + 1) % points.length];
    final chord = second - first;
    final chordDistance = chord.distance;
    if (chordDistance < .0001) continue;
    final outwardNormal = Offset(chord.dy, -chord.dx) / chordDistance;
    final curvatureOffset = math.max(0.0, distanceOnPerimeter - chordDistance);
    final midpoint = Offset.lerp(first, second, .5)!;
    final arcPoint = midpoint + outwardNormal * (protrusion + curvatureOffset);
    final radius = _circumradius(first, second, arcPoint);
    path.arcToPoint(
      second,
      radius: Radius.circular(radius),
      clockwise: true,
    );
  }
  return path..close();
}

List<({Offset center, double radius})> _thoughtTailCircles(
  Rect rect,
  BubbleTailGeometry tail,
) {
  final anchor = Offset.lerp(tail.start, tail.end, .5)!;
  final delta = tail.tip - anchor;
  if (delta.distance == 0) return const [];
  final direction = delta / delta.distance;
  final horizontalDistance = direction.dx > 0
      ? (rect.right - anchor.dx) / direction.dx
      : direction.dx < 0
          ? (rect.left - anchor.dx) / direction.dx
          : double.infinity;
  final verticalDistance = direction.dy > 0
      ? (rect.bottom - anchor.dy) / direction.dy
      : direction.dy < 0
          ? (rect.top - anchor.dy) / direction.dy
          : double.infinity;
  final edge = anchor +
      direction * math.min(horizontalDistance.abs(), verticalDistance.abs());
  final shortest = rect.shortestSide;
  final radii = [
    (shortest * .035).clamp(3.5, 9.0),
    (shortest * .024).clamp(2.5, 6.0),
    (shortest * .014).clamp(1.8, 3.8),
  ];
  final gap = (shortest * .008).clamp(1.0, 2.5);
  final circles = <({Offset center, double radius})>[];
  var travel = gap + radii.first;
  for (var i = 0; i < radii.length; i++) {
    final radius = radii[i];
    if (i > 0) {
      travel += radii[i - 1] + radius + gap;
    }
    circles.add((center: edge + direction * travel, radius: radius));
  }
  return circles;
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

  for (final circle in _thoughtTailCircles(rect, tail)) {
    if ((point - circle.center).distance <= circle.radius) return true;
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
      for (final circle in _thoughtTailCircles(rect, tail)) {
        canvas.drawCircle(circle.center, circle.radius, fill);
        canvas.drawCircle(circle.center, circle.radius, stroke);
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

    final thoughtInset = (rect.shortestSide * .18).clamp(10.0, 34.0);
    final thoughtWidthFactor =
        ((rect.width - thoughtInset * 2) / rect.width).clamp(.42, .78);
    final thoughtHeightFactor =
        ((rect.height - thoughtInset * 2) / rect.height).clamp(.42, .68);
    final textWidthFactor = switch (bubble.shape) {
      BubbleShape.ellipse => .78,
      BubbleShape.rounded => .84,
      BubbleShape.shout => .74,
      BubbleShape.thought => thoughtWidthFactor,
      BubbleShape.whisper => .78,
    };
    final textHeightFactor = switch (bubble.shape) {
      BubbleShape.ellipse => .68,
      BubbleShape.rounded => .72,
      BubbleShape.shout => .62,
      BubbleShape.thought => thoughtHeightFactor,
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
