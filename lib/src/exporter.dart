import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
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
      sha256.convert(utf8.encode(page.pageId)).toString().substring(0, 16);
  return numbered
      ? '$sequence-captioned-$baseName.png'
      : '$baseName-captioned-$shortId.png';
}

Future<RenderedExportImage> renderPageForExport(
  ImagePage page,
  int index, {
  bool numbered = true,
}) async {
  ui.Image? originalImage;
  ui.Picture? picture;
  ui.Image? image;
  PagePainter? painter;
  try {
    originalImage = await decodeOriginalImage(page.bytes);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size =
        ui.Size(page.originalWidth.toDouble(), page.originalHeight.toDouble());
    painter = PagePainter(page: page, sourceImage: originalImage);
    painter.paint(canvas, size);
    picture = recorder.endRecording();
    image = await picture.toImage(page.originalWidth, page.originalHeight);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法编码图片');
    return RenderedExportImage(
        fileName: exportImageName(page, index, numbered: numbered),
        bytes: data.buffer.asUint8List());
  } finally {
    painter?.releaseLayouts();
    image?.dispose();
    picture?.dispose();
    originalImage?.dispose();
  }
}
