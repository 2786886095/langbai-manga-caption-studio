@TestOn('browser')
library;

import 'dart:convert';

import 'package:bubble_caption_studio/src/font_library.dart';
import 'package:bubble_caption_studio/src/font_library_web.dart' as storage;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real Web FontLoader accepts immutable bundled and project font assets',
      () async {
    final library = FontLibrary();
    await library.load();
    for (final family in ['Noto Sans SC', 'ZCOOL KuaiLe']) {
      final asset = (await library.getAsset(family))!;
      expect(library.isRegistered(asset.runtimeFamily), isTrue);
      expect(() => asset.bytes[0] = 0, throwsUnsupportedError);
      final resolved = await library.resolve(family, text: '漫画对白');
      expect(resolved.error, isNull);
      expect(resolved.missingFont, isFalse);
    }
    final data = await rootBundle.load('assets/fonts/LongCang-Regular.ttf');
    final project = await library.ensureRegisteredAsset(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    expect(library.isRegistered(project.runtimeFamily), isTrue);
    expect(project.runtimeFamily, startsWith('BCS_Font_'));
  });
  test(
      'IndexedDB stores font resources once, updates metadata, and reloads actual local bytes',
      () async {
    final data = await rootBundle.load('assets/fonts/ZCOOLKuaiLe-Regular.ttf');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final id = fontAssetIdForBytes(bytes);
    final metadata = inspectFont(bytes);
    await storage.writeFontLibrary({
      'format': 'langbai-font-library',
      'schemaVersion': 1,
      'fonts': [
        {
          'id': id,
          'sha256': id.split(':')[1],
          'displayName': metadata.family,
          'metadataFamily': metadata.family,
          'runtimeFamily': 'BCS_Font_${id.split(':')[1]}_face0',
          'bytes': base64Encode(bytes)
        }
      ],
      'preferences': {}
    });
    final saved = (await storage.readFontLibrary())!;
    expect(saved['fonts'][0].containsKey('bytes'), isFalse);
    expect(await storage.readFontAsset(id), bytes);
    saved['preferences'] = {
      id: {'favorite': true}
    };
    await storage.writeFontLibrary(saved);
    expect((await storage.readFontLibrary())!['preferences'][id]['favorite'],
        isTrue);
    expect(await storage.readFontAsset(id), bytes);
    expect(await storage.readFontAsset('missing-font'), isNull);
  });
}
