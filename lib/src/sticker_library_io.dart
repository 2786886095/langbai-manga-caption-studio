import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'sticker_library.dart' show StickerAsset;

String encodeStickerBytes(Uint8List bytes) => base64Encode(bytes);
Uint8List decodeStickerBytes(String? value) =>
    value == null ? Uint8List(0) : base64Decode(value);

Future<File> _libraryFile() async => File(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}sticker-library.json',
    );

Future<List<StickerAsset>> loadStickerLibrary() async {
  final file = await _libraryFile();
  for (final candidate in [file, File('${file.path}.bak')]) {
    try {
      if (!await candidate.exists()) continue;
      final root = jsonDecode(await candidate.readAsString());
      if (root is! Map<String, dynamic> ||
          root['format'] != 'langbai-sticker-library') continue;
      return [
        for (final item in (root['assets'] as List? ?? const [])
            .whereType<Map<String, dynamic>>())
          StickerAsset.fromJson(item),
      ];
    } catch (_) {
      // Try the previous complete library generation.
    }
  }
  return const [];
}

Future<void> saveStickerLibrary(List<StickerAsset> assets) async {
  final file = await _libraryFile();
  await file.parent.create(recursive: true);
  final temporary = File(
    '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  await temporary.writeAsString(
    jsonEncode({
      'format': 'langbai-sticker-library',
      'schemaVersion': 1,
      'assets': [for (final asset in assets) asset.toJson()],
    }),
    flush: true,
  );
  try {
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
      await file.delete();
    }
    await temporary.rename(file.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}
