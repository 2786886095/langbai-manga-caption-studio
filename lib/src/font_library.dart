import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'font_library_io.dart'
    if (dart.library.js_interop) 'font_library_web.dart' as persistence;
import 'font_metadata.dart';
import 'font_engine_data.dart';

export 'font_metadata.dart' show SfntFontMetadata, inspectFont;

String fontAssetIdForBytes(Uint8List bytes) =>
    'sha256:${crypto.sha256.convert(bytes)}:face0';

enum FontSource { builtIn, imported, project }

class FontRecord {
  const FontRecord(
      {required this.id,
      required this.sha256,
      required this.displayName,
      required this.runtimeFamily,
      required this.metadataFamily,
      required this.source,
      this.category = '',
      this.assetPath,
      this.fileName,
      this.favorite = false,
      this.lastUsedAt});
  final String id;
  final String sha256;
  final String displayName;
  final String runtimeFamily;
  final String metadataFamily;
  final FontSource source;
  final String category;
  final String? assetPath;
  final String? fileName;
  final bool favorite;
  final DateTime? lastUsedAt;

  FontRecord copyWith({bool? favorite, DateTime? lastUsedAt}) => FontRecord(
      id: id,
      sha256: sha256,
      displayName: displayName,
      runtimeFamily: runtimeFamily,
      metadataFamily: metadataFamily,
      source: source,
      category: category,
      assetPath: assetPath,
      fileName: fileName,
      favorite: favorite ?? this.favorite,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'sha256': sha256,
        'displayName': displayName,
        'runtimeFamily': runtimeFamily,
        'metadataFamily': metadataFamily,
        'category': category,
        'fileName': fileName,
      };
}

class FontAsset {
  const FontAsset(this.record, this.bytes, this.metadata);
  final FontRecord record;
  final Uint8List bytes;
  final SfntFontMetadata metadata;
  String get id => record.id;
  String get sha256 => record.sha256;
  String get displayName => record.displayName;
  String get runtimeFamily => record.runtimeFamily;
}

class FontResolution {
  const FontResolution(
      {required this.requestedFamily,
      required this.resolvedFamily,
      required this.missingFont,
      this.asset,
      this.missingGlyphs = const [],
      this.error});
  final String requestedFamily;
  final String resolvedFamily;
  final bool missingFont;
  final FontAsset? asset;
  final List<int> missingGlyphs;
  final String? error;
  bool get hasWarning =>
      missingFont || missingGlyphs.isNotEmpty || error != null;
}

class FontImportInput {
  const FontImportInput(this.bytes, {this.fileName});
  final Uint8List bytes;
  final String? fileName;
}

class FontImportReport {
  const FontImportReport(this.assets, this.errors);
  final List<FontAsset> assets;
  final Map<String, String> errors;
}

abstract class FontLibraryStorage {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> snapshot);
  Future<Uint8List?> readAsset(String id) async => null;
}

class _LocalFontStorage implements FontLibraryStorage {
  @override
  Future<Map<String, dynamic>?> read() => persistence.readFontLibrary();
  @override
  Future<void> write(Map<String, dynamic> snapshot) =>
      persistence.writeFontLibrary(snapshot);
  @override
  Future<Uint8List?> readAsset(String id) => persistence.readFontAsset(id);
}

/// Fonts stay local. Bundled font bytes are read/registered only on first use;
/// imported files are content-addressed, never keyed by a potentially colliding
/// file name or user-visible family. Project restores do not pollute the library.
class FontLibrary extends ChangeNotifier {
  FontLibrary(
      {FontLibraryStorage? storage,
      AssetBundle? bundle,
      Future<void> Function(String, Uint8List)? registrar})
      : _storage = storage ?? _LocalFontStorage(),
        _bundle = bundle ?? rootBundle,
        _registrar = registrar ?? _register;
  static final instance = FontLibrary();
  final FontLibraryStorage _storage;
  final AssetBundle _bundle;
  final Future<void> Function(String, Uint8List) _registrar;
  final Map<String, FontRecord> _records = {};
  final Map<String, FontAsset> _assets = {};
  final Map<String, String> _aliases = {};
  final Set<String> _registered = {};
  final Map<String, Future<void>> _registrations = {};
  final Map<String, String> _runtimeContent = {};
  final Map<String, String> _encodedAssets = {};
  final Map<String, Map<String, dynamic>> _preferences = {};
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _operations = Future.value();
  bool get isLoaded => _loaded;
  bool isRegistered(String family) => _registered.contains(family);
  List<FontRecord> get records => List.unmodifiable(_records.values);

  static Future<void> _register(String family, Uint8List bytes) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(fontDataForEngine(bytes)));
    await loader.load();
  }

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final manifest =
        jsonDecode(await _bundle.loadString('assets/fonts/fonts_manifest.json'))
            as Map<String, dynamic>;
    final saved = await _storage.read();
    final builtins = <String, FontRecord>{};
    for (final item
        in (manifest['fonts'] as List).cast<Map<String, dynamic>>()) {
      final record = FontRecord(
          id: item['id'] as String,
          sha256: item['sha256'] as String,
          displayName: item['displayName'] as String,
          runtimeFamily: item['family'] as String,
          metadataFamily: item['metadataFamily'] as String,
          source: FontSource.builtIn,
          category: item['category'] as String? ?? '',
          assetPath: item['assetPath'] as String);
      builtins[record.id] = record;
    }
    final imported = <String, FontRecord>{};
    for (final raw in (saved?['fonts'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final id = raw['id']?.toString() ?? '';
      final match = RegExp(r'^sha256:([a-f0-9]{64}):face0$').firstMatch(id);
      if (match == null) throw const FormatException('字体库素材ID无效。');
      if (raw['bytes'] is String) {
        // Read the legacy in-snapshot representation once. New native/Web
        // storage keeps immutable bytes separately and loads them on demand.
        final bytes = base64Decode(raw['bytes'] as String).asUnmodifiableView();
        final metadata = inspectFont(bytes);
        if (fontAssetIdForBytes(bytes) != id) {
          throw const FormatException('字体库文件校验失败，未载入。');
        }
        final record = _recordForBytes(bytes, metadata, FontSource.imported,
            fileName: raw['fileName'] as String?);
        imported[id] = record;
        _assets[id] = FontAsset(record, bytes, metadata);
        _encodedAssets[id] = raw['bytes'] as String;
      } else {
        imported[id] = FontRecord(
            id: id,
            sha256: match.group(1)!,
            displayName: raw['displayName'] as String,
            runtimeFamily: 'BCS_Font_${match.group(1)!}_face0',
            metadataFamily: raw['metadataFamily'] as String,
            source: FontSource.imported,
            fileName: raw['fileName'] as String?);
      }
    }
    _preferences.clear();
    final prefs = saved?['preferences'];
    if (prefs is Map) {
      for (final entry in prefs.entries) {
        if (entry.value is Map) {
          _preferences[entry.key.toString()] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    _records.addAll(builtins);
    for (final entry in imported.entries) {
      if (!builtins.containsKey(entry.key)) {
        _records[entry.key] = entry.value;
      }
    }
    for (final entry in _records.entries.toList()) {
      final prefs = _preferences[entry.key];
      if (prefs != null) {
        _records[entry.key] = entry.value.copyWith(
            favorite: prefs['favorite'] == true,
            lastUsedAt:
                DateTime.tryParse(prefs['lastUsedAt']?.toString() ?? ''));
      }
    }
    _loaded = true;
    notifyListeners();
  }

  FontRecord? recordFor(String value) {
    final direct = _records[value] ?? _records[_aliases[value]];
    if (direct != null) return direct;
    for (final record in _records.values) {
      if (record.runtimeFamily == value ||
          record.displayName == value ||
          record.metadataFamily == value) return record;
    }
    return null;
  }

  Future<FontAsset?> getAsset(String value) async {
    final record = recordFor(value);
    if (record == null) return null;
    var asset = _assets[record.id];
    if (asset == null) {
      final path = record.assetPath;
      Uint8List? bytes;
      if (path != null) {
        final data = await _bundle.load(path);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } else {
        bytes = await _storage.readAsset(record.id);
      }
      if (bytes == null) throw const FormatException('字体素材文件缺失，未载入。');
      if (fontAssetIdForBytes(bytes) != record.id) {
        throw const FormatException('字体SHA256校验失败，未载入。');
      }
      bytes = bytes.asUnmodifiableView();
      asset = FontAsset(record, bytes, inspectFont(bytes));
    }
    await _ensureRegistered(record.runtimeFamily, asset.bytes, record.id);
    _assets[asset.id] = asset;
    return FontAsset(record, asset.bytes, asset.metadata);
  }

  Future<void> _ensureRegistered(
      String family, Uint8List bytes, String id) async {
    if (_runtimeContent[family] != null && _runtimeContent[family] != id) {
      throw const FormatException('运行时字体名称已绑定不同字体内容，禁止静默替换。');
    }
    if (_registered.contains(family)) return;
    final pending = _registrations[family];
    if (pending != null) return pending;
    final future = _registrar(family, bytes);
    _runtimeContent[family] = id;
    _registrations[family] = future;
    try {
      await future;
      _registered.add(family);
    } finally {
      _registrations.remove(family);
      if (!_registered.contains(family)) _runtimeContent.remove(family);
    }
  }

  FontRecord _recordForBytes(
      Uint8List bytes, SfntFontMetadata metadata, FontSource source,
      {String? fileName, String? displayName, String? runtimeFamily}) {
    final hash = crypto.sha256.convert(bytes).toString();
    return FontRecord(
        id: 'sha256:$hash:face0',
        sha256: hash,
        displayName: displayName ?? metadata.family,
        runtimeFamily: runtimeFamily ?? 'BCS_Font_${hash}_face0',
        metadataFamily: metadata.family,
        source: source,
        fileName: fileName);
  }

  Future<FontAsset> ensureRegisteredAsset(Uint8List bytes,
      {String? expectedId, String? displayName, String? runtimeFamily}) async {
    final stableBytes = Uint8List.fromList(bytes).asUnmodifiableView();
    final metadata = inspectFont(stableBytes);
    final id = fontAssetIdForBytes(stableBytes);
    if (expectedId != null && expectedId != id) {
      throw const FormatException('项目字体SHA256与素材ID不一致，未载入。');
    }
    final record = _recordForBytes(stableBytes, metadata, FontSource.project,
        displayName: displayName, runtimeFamily: runtimeFamily);
    await _ensureRegistered(record.runtimeFamily, stableBytes, record.id);
    final asset = FontAsset(record, stableBytes, metadata);
    _aliases[record.runtimeFamily] = id;
    _records.putIfAbsent(id, () => record);
    _assets.putIfAbsent(id, () => asset);
    return asset;
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<FontAsset> importBytes(Uint8List bytes, {String? fileName}) async {
    await load();
    return _serialized(() async {
      if (fileName != null &&
          !RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(fileName)) {
        throw const FormatException('仅可导入TTF或OTF字体文件。');
      }
      final stableBytes = Uint8List.fromList(bytes).asUnmodifiableView();
      final metadata = inspectFont(stableBytes);
      final id = fontAssetIdForBytes(stableBytes);
      final existing = _records[id];
      if (existing != null && existing.source != FontSource.project) {
        return (await getAsset(id))!;
      }
      final record = _recordForBytes(stableBytes, metadata, FontSource.imported,
          fileName: fileName);
      final asset = FontAsset(record, stableBytes, metadata);
      await _ensureRegistered(record.runtimeFamily, asset.bytes, record.id);
      final records = Map<String, FontRecord>.of(_records)..[id] = record;
      final assets = Map<String, FontAsset>.of(_assets)..[id] = asset;
      try {
        await _storage.write(_snapshot(records, assets, _preferences));
      } catch (_) {
        _registered.remove(record.runtimeFamily);
        rethrow;
      }
      _records[id] = record;
      _assets[id] = asset;
      notifyListeners();
      return asset;
    });
  }

  Future<FontImportReport> importMany(List<FontImportInput> files) async {
    final assets = <FontAsset>[];
    final errors = <String, String>{};
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        assets.add(await importBytes(file.bytes, fileName: file.fileName));
      } catch (error) {
        errors[file.fileName ?? '字体${i + 1}'] = error.toString();
      }
    }
    return FontImportReport(assets, errors);
  }

  Map<String, dynamic> _snapshot(
          Map<String, FontRecord> records,
          Map<String, FontAsset> assets,
          Map<String, Map<String, dynamic>> prefs) =>
      {
        'format': 'langbai-font-library',
        'schemaVersion': 1,
        'fonts': [
          for (final record in records.values)
            if (record.source == FontSource.imported)
              {
                ...record.toJson(),
                if (assets[record.id] != null)
                  'bytes': _encodedAssets.putIfAbsent(
                      record.id, () => base64Encode(assets[record.id]!.bytes))
              }
        ],
        'preferences': prefs,
      };

  Future<void> setFavorite(String id, bool favorite) =>
      _updatePreference(id, favorite: favorite);
  Future<void> markUsed(String id) =>
      _updatePreference(id, usedAt: DateTime.now().toUtc());
  Future<void> _updatePreference(String id,
      {bool? favorite, DateTime? usedAt}) async {
    await load();
    await _serialized(() async {
      final record = _records[id];
      if (record == null) throw StateError('字体不存在。');
      final prefs = Map<String, Map<String, dynamic>>.of(_preferences);
      prefs[id] = {
        ...?_preferences[id],
        if (favorite != null) 'favorite': favorite,
        if (usedAt != null) 'lastUsedAt': usedAt.toIso8601String()
      };
      await _storage.write(_snapshot(_records, _assets, prefs));
      _preferences[id] = prefs[id]!;
      _records[id] = record.copyWith(favorite: favorite, lastUsedAt: usedAt);
      notifyListeners();
    });
  }

  Future<FontResolution> resolve(String requestedFamily,
      {String? assetId, String text = ''}) async {
    await load();
    try {
      final asset = await getAsset(assetId ?? requestedFamily);
      if (asset != null) {
        return FontResolution(
            requestedFamily: requestedFamily,
            resolvedFamily: asset.runtimeFamily,
            missingFont: false,
            asset: asset,
            missingGlyphs: asset.metadata.missingCodePoints(text));
      }
      return FontResolution(
          requestedFamily: requestedFamily,
          resolvedFamily: 'Noto Sans SC',
          missingFont: true);
    } catch (error) {
      return FontResolution(
          requestedFamily: requestedFamily,
          resolvedFamily: 'Noto Sans SC',
          missingFont: true,
          error: error.toString());
    }
  }
}
