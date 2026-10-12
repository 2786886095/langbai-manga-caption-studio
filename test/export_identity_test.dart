import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unnumbered same names with time-prefix IDs never overwrite one another',
      () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    picture.dispose();
    final a = ImagePage(
        pageId: 'page-1791801000000000-0',
        name: '1.png',
        bytes: Uint8List(0),
        image: image);
    final b = ImagePage(
        pageId: 'page-1791801000000001-1',
        name: '1.png',
        bytes: Uint8List(0),
        image: image.clone());
    expect(exportImageName(a, 0, numbered: false),
        isNot(exportImageName(b, 1, numbered: false)));
    expect(exportImageName(a, 0, numbered: false),
        exportImageName(a, 100, numbered: false));
    a.dispose();
    b.dispose();
  });
}
