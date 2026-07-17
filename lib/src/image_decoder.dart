import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

class DecodedPreview {
  const DecodedPreview(this.image, this.originalWidth, this.originalHeight);

  final ui.Image image;
  final int originalWidth;
  final int originalHeight;
}

int previewDimensionForPageCount(int pageCount) {
  if (pageCount >= 80) return 384;
  if (pageCount >= 40) return 512;
  if (pageCount >= 20) return 640;
  return 768;
}

/// Decodes a memory-friendly editing preview while preserving source dimensions.
Future<DecodedPreview> decodeImagePreview(
  Uint8List bytes, {
  int maxDimension = 768,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final original = frame.image;
  final originalWidth = original.width;
  final originalHeight = original.height;
  final longest =
      originalWidth > originalHeight ? originalWidth : originalHeight;
  if (longest <= maxDimension) {
    return DecodedPreview(original, originalWidth, originalHeight);
  }
  final scale = maxDimension / longest;
  final targetWidth = (originalWidth * scale).round().clamp(1, originalWidth);
  final targetHeight = (originalHeight * scale).round().clamp(
        1,
        originalHeight,
      );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    original,
    ui.Rect.fromLTWH(0, 0, originalWidth.toDouble(), originalHeight.toDouble()),
    ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final preview = await recorder.endRecording().toImage(
        targetWidth,
        targetHeight,
      );
  original.dispose();
  return DecodedPreview(preview, originalWidth, originalHeight);
}

Future<ui.Image> decodeOriginalImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<String> encodeThumbnailBase64(
  ui.Image source, {
  int maxDimension = 320,
}) async {
  final longest = source.width > source.height ? source.width : source.height;
  final scale = longest > maxDimension ? maxDimension / longest : 1.0;
  final width = (source.width * scale).round().clamp(1, source.width);
  final height = (source.height * scale).round().clamp(1, source.height);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final thumbnail = await recorder.endRecording().toImage(width, height);
  final data = await thumbnail.toByteData(format: ui.ImageByteFormat.png);
  thumbnail.dispose();
  if (data == null) throw StateError('Unable to encode project thumbnail');
  return base64Encode(data.buffer.asUint8List());
}
