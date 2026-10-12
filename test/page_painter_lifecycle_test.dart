import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'offscreen layout release is idempotent and subsequent paint is identical',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final painter = PagePainter(page: page);
    addTearDown(painter.releaseLayouts);
    final before = await _pixels(painter);
    expect(painter.debugCachedLayoutCount, 1);
    painter.releaseLayouts();
    painter.releaseLayouts();
    expect(painter.debugCachedLayoutCount, 0);
    final after = await _pixels(painter);
    expect(painter.debugCachedLayoutCount, 1);
    expect(after, before);
  });

  testWidgets('managed preview releases replaced and disposed painter layouts',
      (tester) async {
    final page = (await tester.runAsync(_page))!;
    addTearDown(page.dispose);
    final first = PagePainter(page: page);
    await tester.pumpWidget(_preview(first));
    expect(
        find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter == first),
        findsOneWidget);
    expect(first.debugCachedLayoutCount, 1);
    page.placements = [
      page.placements.single.copyWith(fontColorValue: 0xfff04167)
    ];
    final second = PagePainter(page: page);
    await tester.pumpWidget(_preview(second));
    expect(first.debugCachedLayoutCount, 0);
    expect(second.debugCachedLayoutCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(second.debugCachedLayoutCount, 0);
  });

  testWidgets('same-signature font changes clear cached metrics and repaint',
      (tester) async {
    final page = (await tester.runAsync(_page))!;
    addTearDown(page.dispose);
    final painter = _TrackingPainter(page: page);
    await tester.pumpWidget(_preview(painter));
    expect(painter.debugCachedLayoutCount, 1);
    final paintsBefore = painter.paintCount;
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    expect(painter.debugCachedLayoutCount, 0);
    await tester.pump();
    expect(painter.paintCount, greaterThan(paintsBefore));
    expect(painter.debugCachedLayoutCount, 1);
    await tester.pumpWidget(const SizedBox());
    final releasesAfterDispose = painter.releaseCount;
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    expect(painter.releaseCount, releasesAfterDispose);
  });

  test('late registered real font remeasures a reused same-family painter',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    const family = 'BCS_Lifecycle_Late_Font';
    page.placements = [page.placements.single.copyWith(fontFamily: family)];
    final reused = PagePainter(page: page);
    addTearDown(reused.releaseLayouts);
    final fallback = await _pixels(reused);
    final loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/fonts/ZCOOLXiaoWei-Regular.ttf'));
    await loader.load();
    reused.invalidateLayouts();
    final registered = await _pixels(reused);
    final fresh = PagePainter(page: page);
    addTearDown(fresh.releaseLayouts);
    final expected = await _pixels(fresh);
    expect(registered, expected);
    expect(registered, isNot(fallback));
  });
}

Widget _preview(PagePainter painter) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 200,
          child: ManagedPagePaint(painter: painter),
        ),
      ),
    );

class _TrackingPainter extends PagePainter {
  _TrackingPainter({required super.page});
  int paintCount = 0;
  int releaseCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paintCount++;
    super.paint(canvas, size);
  }

  @override
  void releaseLayouts() {
    releaseCount++;
    super.releaseLayouts();
  }
}

Future<ImagePage> _page() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  picture.dispose();
  final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
  return ImagePage(
    pageId: 'lifecycle-page',
    name: '001.png',
    bytes: encoded!.buffer.asUint8List(),
    image: image,
  )..placements = [
      const BubblePlacement(
        caption:
            CaptionLine(speaker: '', text: 'letters MWi', bubbleId: 'p1-b1'),
        x: 12,
        y: 12,
        width: 290,
        height: 140,
        shape: BubbleShape.plainText,
        textSizeMode: TextSizeMode.fixed,
        fontSize: 34,
      ),
    ];
}

Future<Uint8List> _pixels(PagePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), const ui.Size(320, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  try {
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(pixels!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}
