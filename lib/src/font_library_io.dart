import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}font-library-v1.json');

Future<File> _assetFile(String id) async {
  final match = RegExp(r'^sha256:([a-f0-9]{64}):face0$').firstMatch(id);
  if (match == null) throw const FormatException('字体素材ID无效。');
  final file = await _file();
  return File(
      '${file.parent.path}${Platform.pathSeparator}font-library-assets${Platform.pathSeparator}${match.group(1)}-face0.bin');
}

Future<Uint8List?> readFontAsset(String id) async {
  final file = await _assetFile(id);
  return await file.exists() ? file.readAsBytes() : null;
}

Future<Map<String, dynamic>?> readFontLibrary() async {
  final file = await _file();
  Object? error;
  for (final candidate in [file, File('${file.path}.bak')]) {
    if (!await candidate.exists()) continue;
    try {
      final json = jsonDecode(await candidate.readAsString());
      if (json is! Map<String, dynamic> ||
          json['format'] != 'langbai-font-library') {
        throw const FormatException('字体库格式无效。');
      }
      return json;
    } catch (failure) {
      error = failure;
    }
  }
  if (error != null) throw StateError('字体库读取失败：$error');
  return null;
}

Future<void> writeFontLibrary(Map<String, dynamic> value) async {
  final file = await _file();
  await file.parent.create(recursive: true);
  final records = <Map<String, dynamic>>[];
  for (final raw in (value['fonts'] as List).cast<Map<String, dynamic>>()) {
    final asset = await _assetFile(raw['id'] as String);
    if (!await asset.exists()) {
      if (raw['bytes'] is! String) throw const FormatException('字体素材文件缺失，未保存。');
      await asset.parent.create(recursive: true);
      final temporary =
          File('${asset.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
      await temporary.writeAsBytes(base64Decode(raw['bytes'] as String),
          flush: true);
      await temporary.rename(asset.path);
    }
    records.add(Map<String, dynamic>.of(raw)..remove('bytes'));
  }
  final temporary =
      File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
  await temporary.writeAsString(jsonEncode({...value, 'fonts': records}),
      flush: true);
  try {
    if (await file.exists()) await file.copy('${file.path}.bak');
    // Windows cannot rename over an existing file; the flushed backup remains
    // readable if replacement is interrupted between these two operations.
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}
