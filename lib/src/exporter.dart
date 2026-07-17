import 'dart:typed_data';
import 'dart:ui' as ui;

import 'bubble_painter.dart';
import 'image_decoder.dart';
import 'models.dart';

class RenderedExportImage {
  const RenderedExportImage({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

String exportImageName(ImagePage page, int index, {bool numbered = true}) {
  final baseName = page.name
      .replaceFirst(RegExp(r'\.[^.]+$'), '')
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final sequence = (index + 1).toString().padLeft(4, '0');
  final shortId =
      page.pageId.length > 8 ? page.pageId.substring(0, 8) : page.pageId;
  return numbered
      ? '$sequence-captioned-$baseName.png'
      : '$baseName-captioned-$shortId.png';
}

Future<RenderedExportImage> renderPageForExport(
  ImagePage page,
  int index, {
  bool numbered = true,
}) async {
  final originalImage = await decodeOriginalImage(page.bytes);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final size = ui.Size(
    page.originalWidth.toDouble(),
    page.originalHeight.toDouble(),
  );
  PagePainter(page: page, sourceImage: originalImage).paint(canvas, size);
  final image = await recorder.endRecording().toImage(
        page.originalWidth,
        page.originalHeight,
      );
  originalImage.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('无法编码图片');
  return RenderedExportImage(
    fileName: exportImageName(page, index, numbered: numbered),
    bytes: data.buffer.asUint8List(),
  );
}
