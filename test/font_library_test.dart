import 'dart:convert';
import 'dart:io';

import 'package:bubble_caption_studio/src/font_library.dart';
import 'package:bubble_caption_studio/src/font_picker.dart';
import 'package:bubble_caption_studio/src/font_library_io.dart' as native;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only provider directs every disk write into an isolated temporary root.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _IsolatedFontPaths extends PathProviderPlatform {
  _IsolatedFontPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _MemoryStorage extends FontLibraryStorage {
  Map<String, dynamic>? value;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> read() async {
    if (failRead) throw StateError('fixture read failed');
    return value;
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    if (failWrite) throw StateError('fixture write failed');
    writes++;
    value = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

class _LazyStorage extends _MemoryStorage {
  final assets = <String, Uint8List>{};
  int assetReads = 0;
  @override
  Future<Uint8List?> readAsset(String id) async {
    assetReads++;
    return assets[id];
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    final records = <Map<String, dynamic>>[];
    for (final record
        in (snapshot['fonts'] as List).cast<Map<String, dynamic>>()) {
      if (record['bytes'] is String) {
        assets.putIfAbsent(record['id'] as String,
            () => base64Decode(record['bytes'] as String));
      }
      records.add(Map<String, dynamic>.of(record)..remove('bytes'));
    }
    await super.write({...snapshot, 'fonts': records});
  }
}

class _LocalBundle extends CachingAssetBundle {
  final bool noBuiltins;
  int fontLoads = 0;
  _LocalBundle({this.noBuiltins = false});
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('fonts_manifest.json') && noBuiltins) {
      return ByteData.sublistView(
          Uint8List.fromList(utf8.encode('{"fonts":[]}')));
    }
    if (key.endsWith('.ttf')) fontLoads++;
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List bytes;
  late Map<String, dynamic> manifest;
  setUpAll(() async {
    bytes = await File('assets/fonts/ZCOOLKuaiLe-Regular.ttf').readAsBytes();
    manifest = jsonDecode(
            await File('assets/fonts/fonts_manifest.json').readAsString())
        as Map<String, dynamic>;
  });

  test(
      'all ten actual local font files register and produce distinguishable text metrics',
      () async {
    final library =
        FontLibrary(storage: _MemoryStorage(), bundle: _LocalBundle());
    await library.load();
    final widths = <double>{};
    for (final record in library.records) {
      final font = (await library.getAsset(record.id))!;
      expect(library.isRegistered(font.runtimeFamily), isTrue);
      final painter = TextPainter(
          text: TextSpan(
              text: '漫画字幕 Aa09',
              style: TextStyle(fontFamily: font.runtimeFamily, fontSize: 32)),
          textDirection: TextDirection.ltr)
        ..layout();
      expect(painter.width, greaterThan(0));
      widths.add(painter.width);
      painter.dispose();
    }
    expect(widths.length, greaterThanOrEqualTo(6));
  });

  test(
      'all ten fonts are complete distributions with saved OFL and verified hashes',
      () async {
    final fonts = (manifest['fonts'] as List).cast<Map<String, dynamic>>();
    expect(fonts, hasLength(10));
    for (final entry in fonts) {
      final font = await File(entry['assetPath'] as String).readAsBytes();
      final license = await File(entry['licensePath'] as String).readAsBytes();
      expect(sha256.convert(font).toString(), entry['sha256']);
      expect(fontAssetIdForBytes(font), entry['id']);
      expect(sha256.convert(license).toString(), entry['licenseSha256']);
      expect(utf8.decode(license), contains('SIL OPEN FONT LICENSE'));
      expect(entry['distribution'], 'complete-upstream-font-not-a-web-subset');
      expect(entry['unicodeCount'], greaterThan(6000));
      final metadata = inspectFont(font);
      expect(metadata.family, isNotEmpty);
      expect(metadata.glyphCount, greaterThan(6000));
      expect(metadata.missingCodePoints('你好，世界！这是漫画字幕。'), isEmpty,
          reason: entry['family'].toString());
    }
  });

  test(
      'name table not file name defines imported family and cmap detects missing glyphs',
      () {
    final metadata = inspectFont(bytes);
    expect(metadata.family, contains('ZCOOL'));
    expect(metadata.hasGlyph('漫'.runes.single), isTrue);
    expect(metadata.hasGlyph(0x10ffff), isFalse);
    expect(metadata.missingCodePoints('你好\n\t${String.fromCharCode(0x10ffff)}'),
        [0x10ffff]);
  });

  test(
      'invalid, truncated, renamed junk and collections reject before registration',
      () {
    for (final invalid in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3, 4]),
      Uint8List.fromList([...utf8.encode('ttcf'), ...List.filled(20, 0)]),
      Uint8List.sublistView(bytes, 0, 60)
    ]) {
      expect(() => inspectFont(invalid), throwsFormatException);
    }
    final broken = Uint8List.fromList(bytes);
    ByteData.sublistView(broken).setUint32(20, 0xffffffff);
    expect(() => inspectFont(broken), throwsFormatException);
  });

  test(
      'library startup is lazy, selected builtins register once and cache bytes',
      () async {
    final bundle = _LocalBundle();
    var registrations = 0;
    final library = FontLibrary(
        storage: _MemoryStorage(),
        bundle: bundle,
        registrar: (_, __) async => registrations++);
    await library.load();
    expect(library.records, hasLength(10));
    expect(bundle.fontLoads, 0);
    final record = library.records.first;
    final asset = await library.getAsset(record.id);
    expect(asset!.bytes, isNotEmpty);
    expect(bundle.fontLoads, 1);
    expect(registrations, 1);
    await library.getAsset(record.runtimeFamily);
    expect(bundle.fontLoads, 1);
    expect(registrations, 1);
  });

  test(
      'batch import deduplicates bytes despite renamed files and isolates invalid fonts',
      () async {
    final storage = _MemoryStorage();
    final library = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    final report = await library.importMany([
      FontImportInput(bytes, fileName: 'renamed.ttf'),
      FontImportInput(bytes, fileName: 'another.otf'),
      FontImportInput(Uint8List(20), fileName: 'bad.ttf'),
      FontImportInput(bytes, fileName: 'wrong.png'),
    ]);
    expect(report.assets, hasLength(2));
    expect(report.errors.keys, containsAll(['bad.ttf', 'wrong.png']));
    expect(library.records, hasLength(1));
    expect(storage.writes, 1);
    final asset = report.assets.first;
    expect(asset.id, fontAssetIdForBytes(bytes));
    expect(asset.runtimeFamily, 'BCS_Font_${sha256.convert(bytes)}_face0');
    expect(asset.displayName, inspectFont(bytes).family);
    expect(asset.displayName, isNot('renamed'));
    expect(storage.value!['fonts'][0]['bytes'], base64Encode(bytes));
  });

  test('import, favorites and recent use survive local library reload',
      () async {
    final storage = _MemoryStorage();
    final library = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    final imported = await library.importBytes(bytes, fileName: 'font.ttf');
    await library.setFavorite(imported.id, true);
    await library.markUsed(imported.id);
    final restored = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    await restored.load();
    final record = restored.recordFor(imported.id)!;
    expect(record.favorite, isTrue);
    expect(record.lastUsedAt, isNotNull);
    expect((await restored.getAsset(imported.id))!.bytes, bytes);
  });

  test('load failure is not cached as successful loading', () async {
    final storage = _MemoryStorage()..failRead = true;
    final library =
        FontLibrary(storage: storage, bundle: _LocalBundle(noBuiltins: true));
    await expectLater(library.load(), throwsStateError);
    expect(library.isLoaded, isFalse);
    expect(library.records, isEmpty);
    storage.failRead = false;
    await library.load();
    expect(library.isLoaded, isTrue);
  });

  test(
      'FontLoader failure is retriable and never marks runtime family registered',
      () async {
    var attempts = 0;
    final library = FontLibrary(
        storage: _MemoryStorage(),
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {
          if (++attempts == 1) throw StateError('fixture renderer rejected');
        });
    await expectLater(
        library.importBytes(bytes, fileName: 'font.ttf'), throwsStateError);
    final family = 'BCS_Font_${sha256.convert(bytes)}_face0';
    expect(library.isRegistered(family), isFalse);
    expect(library.records, isEmpty);
    await library.importBytes(bytes, fileName: 'font.ttf');
    expect(library.isRegistered(family), isTrue);
    expect(attempts, 2);
  });

  test('write failure does not claim saved imported font or favorite',
      () async {
    final storage = _MemoryStorage()..failWrite = true;
    final library = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    await expectLater(
        library.importBytes(bytes, fileName: 'font.ttf'), throwsStateError);
    expect(library.records, isEmpty);
    storage.failWrite = false;
    final imported = await library.importBytes(bytes, fileName: 'font.ttf');
    storage.failWrite = true;
    await expectLater(library.setFavorite(imported.id, true), throwsStateError);
    expect(library.recordFor(imported.id)!.favorite, isFalse);
  });

  test(
      'project restore verifies identity and avoids adding to global persisted imports',
      () async {
    final storage = _MemoryStorage();
    final library = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    await expectLater(
        library.ensureRegisteredAsset(bytes, expectedId: 'sha256:wrong:face0'),
        throwsFormatException);
    expect(library.records, isEmpty);
    final restored = await library.ensureRegisteredAsset(bytes,
        expectedId: fontAssetIdForBytes(bytes), displayName: '项目字体');
    expect(library.recordFor(restored.id)!.source, FontSource.project);
    expect(library.recordFor(restored.runtimeFamily)!.id, restored.id);
    expect(storage.writes, 0);
  });

  test(
      'missing font reports fallback without overwriting requested identity; missing glyphs are explicit',
      () async {
    final library = FontLibrary(
        storage: _MemoryStorage(),
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    final missing = await library.resolve('Missing font',
        assetId: 'missing-id', text: '文本');
    expect(missing.requestedFamily, 'Missing font');
    expect(missing.resolvedFamily, 'Noto Sans SC');
    expect(missing.missingFont, isTrue);
    final asset = await library.importBytes(bytes, fileName: 'test.ttf');
    final present = await library.resolve(asset.runtimeFamily,
        assetId: asset.id, text: '文本${String.fromCharCode(0x10ffff)}');
    expect(present.missingFont, isFalse);
    expect(present.missingGlyphs, [0x10ffff]);
    expect(present.hasWarning, isTrue);
  });

  testWidgets('picker searches favorites and presents real sample text',
      (tester) async {
    final library = FontLibrary(
        storage: _MemoryStorage(),
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    final asset = await library.importBytes(bytes, fileName: 'font.ttf');
    await library.setFavorite(asset.id, true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FontPicker(
                library: library, sampleText: '样本文字', onSelected: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.text('样本文字'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在的字体');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的字体'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ZCOOL');
    await tester.pumpAndSettle();
    expect(find.text('样本文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'user fonts are lazy and preference snapshots do not reload or encode untouched assets',
      () async {
    final storage = _LazyStorage();
    final first = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    final asset = await first.importBytes(bytes, fileName: 'font.ttf');
    final restored = FontLibrary(
        storage: storage,
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    await restored.load();
    expect(storage.assetReads, 0);
    await restored.setFavorite(asset.id, true);
    expect(storage.assetReads, 0);
    expect(storage.value!['fonts'][0].containsKey('bytes'), isFalse);
    expect((await restored.getAsset(asset.id))!.bytes, bytes);
    expect(storage.assetReads, 1);
    await restored.getAsset(asset.id);
    expect(storage.assetReads, 1);
  });

  test('same runtime family cannot silently bind different font contents',
      () async {
    final library = FontLibrary(
        storage: _MemoryStorage(),
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    await library.ensureRegisteredAsset(bytes, runtimeFamily: 'custom-family');
    final other = await File('assets/fonts/LongCang-Regular.ttf').readAsBytes();
    await expectLater(
        library.ensureRegisteredAsset(other, runtimeFamily: 'custom-family'),
        throwsFormatException);
    expect(library.recordFor('custom-family')!.id, fontAssetIdForBytes(bytes));
  });

  test('imported bytes are isolated from caller mutations', () async {
    final library = FontLibrary(
        storage: _MemoryStorage(),
        bundle: _LocalBundle(noBuiltins: true),
        registrar: (_, __) async {});
    final mutable = Uint8List.fromList(bytes);
    final asset = await library.importBytes(mutable, fileName: 'font.ttf');
    mutable[0] ^= 0xff;
    expect(asset.bytes, bytes);
    expect(asset.metadata.hasGlyph('你'.runes.single), isTrue);
    expect(() => asset.bytes[0] = 0, throwsUnsupportedError);
  });

  test(
      'native storage separates immutable font bytes from small backed-up preferences',
      () async {
    final root = await Directory.systemTemp.createTemp('bcs-font-library-');
    final old = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _IsolatedFontPaths(root.path);
    addTearDown(() async {
      PathProviderPlatform.instance = old;
      final resolved = root.absolute.path;
      expect(resolved, startsWith(Directory.systemTemp.absolute.path));
      expect(
          root.uri.pathSegments.where((p) => p.startsWith('bcs-font-library-')),
          isNotEmpty);
      await root.delete(recursive: true);
    });
    final metadata = inspectFont(bytes);
    final id = fontAssetIdForBytes(bytes);
    final record = {
      'id': id,
      'sha256': sha256.convert(bytes).toString(),
      'displayName': metadata.family,
      'metadataFamily': metadata.family,
      'runtimeFamily': 'BCS_Font_${sha256.convert(bytes)}_face0',
      'fileName': 'font.ttf',
      'bytes': base64Encode(bytes)
    };
    await native.writeFontLibrary({
      'format': 'langbai-font-library',
      'schemaVersion': 1,
      'fonts': [record],
      'preferences': {}
    });
    final saved = (await native.readFontLibrary())!;
    expect(saved['fonts'][0].containsKey('bytes'), isFalse);
    final manifestFile =
        File('${root.path}${Platform.pathSeparator}font-library-v1.json');
    expect(await manifestFile.length(), lessThan(2000));
    expect(await native.readFontAsset(id), bytes);
    saved['preferences'] = {
      id: {'favorite': true}
    };
    await native.writeFontLibrary(saved);
    expect(File('${manifestFile.path}.bak').existsSync(), isTrue);
    expect(await native.readFontAsset(id), bytes);
    await manifestFile.writeAsString('corrupt');
    expect((await native.readFontLibrary())!['format'], 'langbai-font-library');
    await expectLater(
        native.readFontAsset('../../outside'), throwsFormatException);
  });
}
