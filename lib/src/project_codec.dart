import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

import 'models.dart';
import 'image_decoder.dart';
import 'font_library.dart';
import 'bcs_script_exporter.dart';

class ProjectData {
  const ProjectData({
    required this.pages,
    required this.script,
    this.fonts = const {},
    this.fontWarnings = const [],
    this.fontAliases = const {},
    this.fontAssetReferences = const {},
    this.schemaVersion = 3,
    this.revision,
  });

  final List<ImagePage> pages;
  final String script;
  final Map<String, Uint8List> fonts;
  final List<String> fontWarnings;
  final Map<String, String> fontAliases;
  final Map<String, String> fontAssetReferences;
  final int schemaVersion;
  final int? revision;
}

Uint8List encodeProject(
  List<ImagePage> pages,
  String script, {
  Map<String, Uint8List> fonts = const {},
  int? revision,
}) {
  return _encodeProjectDocument(
    pages,
    script,
    fonts: fonts,
    format: 'bubble-caption-studio',
    includeImages: true,
    revision: revision,
  );
}

Uint8List encodeProjectManifest(
  List<ImagePage> pages,
  String script, {
  Map<String, Uint8List> fonts = const {},
  Map<String, String> fontAssetReferences = const {},
  int? revision,
}) =>
    _encodeProjectDocument(
      pages,
      script,
      fonts: fonts,
      format: 'bubble-caption-studio-manifest',
      includeImages: false,
      includePlacedImageBytes: false,
      fontAssetReferences: fontAssetReferences,
      revision: revision,
    );

Uint8List _encodeProjectDocument(
  List<ImagePage> pages,
  String script, {
  required Map<String, Uint8List> fonts,
  required String format,
  required bool includeImages,
  bool includePlacedImageBytes = true,
  Map<String, String> fontAssetReferences = const {},
  int? revision,
}) {
  _validateRevision(revision);
  final json = <String, Object?>{
    'format': format,
    'schemaVersion': 3,
    if (revision != null) 'revision': revision,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'script': script,
    'fonts': {
      for (final entry in fonts.entries)
        if (!fontAssetReferences.containsKey(entry.key))
          entry.key: base64Encode(entry.value),
    },
    if (fontAssetReferences.isNotEmpty) 'fontAssets': fontAssetReferences,
    'fontMetadata': {
      for (final entry in fonts.entries)
        entry.key: {
          'id': FontLibrary.instance.recordFor(entry.key)?.id ??
              fontAssetIdForBytes(entry.value),
          'displayName':
              FontLibrary.instance.recordFor(entry.key)?.displayName ??
                  entry.key,
          'runtimeFamily': entry.key,
        },
      for (final entry in fontAssetReferences.entries)
        if (!fonts.containsKey(entry.key))
          entry.key: _referencedFontMetadata(entry.key),
    },
    'pages': [
      for (final page in pages)
        _encodePage(
          page,
          includeImage: includeImages,
          includePlacedImageBytes: includePlacedImageBytes,
        ),
    ],
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

Uint8List encodeProjectEdits(List<ImagePage> pages, String script,
    {int? revision}) {
  _validateRevision(revision);
  final json = <String, Object?>{
    'format': 'bubble-caption-studio-edits',
    // Version 2 makes an intentionally empty page authoritative. Version 1
    // did not record that intent, so an old/stale empty edit page must never
    // erase bubbles that are still present in the project manifest.
    'schemaVersion': 3,
    if (revision != null) 'revision': revision,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'script': script,
    'pages': [for (final page in pages) _encodeEditablePage(page)],
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

Map<String, Object?> _encodeEditablePage(ImagePage page) => {
      'pageId': page.pageId,
      'approved': page.approved,
      'captions': [
        for (final caption in page.captions)
          {
            'speaker': caption.speaker,
            'text': caption.text,
            'bubbleId': caption.bubbleId,
          },
      ],
      'placements': [
        for (final bubble in page.placements) _encodePlacement(bubble),
      ],
      'placedImages': [
        for (final image in page.placedImages)
          _encodePlacedImage(image, includeBytes: false),
      ],
    };

Map<String, Object?> _encodePlacedImage(
  PlacedImage image, {
  bool includeBytes = true,
}) =>
    {
      'id': image.id,
      'name': image.name,
      if (includeBytes) 'bytes': base64Encode(image.bytes),
      'x': image.x,
      'y': image.y,
      'width': image.width,
      'height': image.height,
      'rotation': image.rotation,
      'opacity': image.opacity,
      'fit': image.fit.name,
      'cropX': image.cropX,
      'cropY': image.cropY,
      'layer': image.layer.name,
      if (image.bubbleId != null) 'bubbleId': image.bubbleId,
    };

Map<String, Object?> _encodePlacement(BubblePlacement bubble) => {
      'x': bubble.x,
      'y': bubble.y,
      'width': bubble.width,
      'height': bubble.height,
      'shape': bubble.shape.name,
      'tailX': bubble.tailX,
      'tailY': bubble.tailY,
      'tailDirection': bubble.tailDirection.name,
      'fontSize': bubble.fontSize,
      'textSizeMode': bubble.textSizeMode.name,
      'textStrokeWidth': bubble.textStrokeWidth,
      'textStrokeColorValue': bubble.textStrokeColorValue,
      'letterSpacing': bubble.letterSpacing,
      'textAlign': bubble.textAlign.name,
      if (bubble.fontAssetId != null) 'fontAssetId': bubble.fontAssetId,
      if (bubble.fontDisplayName != null)
        'fontDisplayName': bubble.fontDisplayName,
      if (bubble.styleId != null) 'styleId': bubble.styleId,
      'lineHeight': bubble.lineHeight,
      'strokeWidth': bubble.strokeWidth,
      'fillOpacity': bubble.fillOpacity,
      'fontFamily': bubble.fontFamily,
      'fontColorValue': bubble.fontColorValue,
    };

Map<String, Object?> _encodePage(
  ImagePage page, {
  bool includeImage = true,
  bool includePlacedImageBytes = true,
}) =>
    {
      'pageId': page.pageId,
      'orderRank': page.orderRank,
      'name': page.name,
      'originalWidth': page.originalWidth,
      'originalHeight': page.originalHeight,
      if (includeImage) 'sourceImage': base64Encode(page.bytes),
      'approved': page.approved,
      'captions': [
        for (final caption in page.captions)
          {
            'speaker': caption.speaker,
            'text': caption.text,
            'bubbleId': caption.bubbleId,
          },
      ],
      'placements': [
        for (final bubble in page.placements) _encodePlacement(bubble),
      ],
      'placedImages': [
        for (final image in page.placedImages)
          _encodePlacedImage(image, includeBytes: includePlacedImageBytes),
      ],
    };

class ProjectEditApplyResult {
  const ProjectEditApplyResult({
    required this.script,
    required this.preservedManifestPages,
    this.ignoredStaleEdits = false,
    this.revision,
  });

  final String script;
  final int preservedManifestPages;
  final bool ignoredStaleEdits;
  final int? revision;

  bool get recoveredLegacyData => preservedManifestPages > 0;
}

Future<ProjectEditApplyResult> applyProjectEdits(
  Uint8List bytes,
  List<ImagePage> pages, {
  Map<String, String> fontAliases = const {},
  int? projectRevision,
}) async {
  final root = jsonDecode(utf8.decode(bytes));
  final schemaVersion = root is Map<String, dynamic>
      ? (root['schemaVersion'] as num?)?.toInt()
      : null;
  if (root is! Map<String, dynamic> ||
      root['format'] != 'bubble-caption-studio-edits' ||
      (schemaVersion != 1 && schemaVersion != 2 && schemaVersion != 3)) {
    throw const FormatException('Unsupported project edit data');
  }
  final editRevision = _decodeRevision(root);
  if (projectRevision != null &&
      (editRevision == null || editRevision < projectRevision)) {
    return ProjectEditApplyResult(
      script: buildBcsScript(pages),
      preservedManifestPages: 0,
      ignoredStaleEdits: true,
      revision: projectRevision,
    );
  }
  final byId = {for (final page in pages) page.pageId: page};
  var preservedManifestPages = 0;
  for (final raw in (root['pages'] as List? ?? const [])) {
    if (raw is! Map<String, dynamic>) continue;
    final page = byId[raw['pageId']?.toString()];
    if (page == null) continue;
    final rawCaptions = raw['captions'] as List? ?? const [];
    final captions = [
      for (final item in rawCaptions.whereType<Map<String, dynamic>>())
        CaptionLine(
          speaker: item['speaker']?.toString() ?? '',
          text: item['text']?.toString() ?? '',
          bubbleId: item['bubbleId']?.toString() ?? '',
        ),
    ];
    final rawPlacements = raw['placements'] as List? ?? const [];
    if (captions.length != rawPlacements.length) continue;
    if (schemaVersion == 1 && captions.isEmpty && page.captions.isNotEmpty) {
      // Legacy edit layers were frequently created before the manifest was
      // saved and could therefore contain an accidental empty page. Preserve
      // the richer manifest page instead of treating that absence as a delete.
      preservedManifestPages++;
      continue;
    }
    final placements = <BubblePlacement>[];
    for (var i = 0; i < captions.length; i++) {
      final item = rawPlacements[i];
      if (item is! Map<String, dynamic>) break;
      placements
          .add(_decodePlacement(item, captions[i], fontAliases: fontAliases));
    }
    if (placements.length != captions.length) continue;
    page
      ..captions = captions
      ..placements = placements
      ..approved = raw['approved'] == true;
    // Old edit overlays have no image-element field; absence is not deletion.
    if (!raw.containsKey('placedImages')) continue;
    final previousImages = {
      for (final image in page.placedImages) image.id: image
    };
    final decodedImages = <PlacedImage>[];
    for (final item in (raw['placedImages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      try {
        final id = item['id']?.toString() ?? '';
        decodedImages.add(
          await _decodePlacedImage(item, source: previousImages[id]),
        );
      } catch (_) {
        // A damaged optional image element must not erase valid captions.
      }
    }
    for (final image in page.placedImages) {
      if (!decodedImages.any((item) => identical(item.image, image.image))) {
        image.image.dispose();
      }
    }
    page.placedImages = decodedImages;
  }
  return ProjectEditApplyResult(
    script: root['script']?.toString() ?? '',
    preservedManifestPages: preservedManifestPages,
    revision: editRevision,
  );
}

Future<PlacedImage> _decodePlacedImage(
  Map<String, dynamic> item, {
  PlacedImage? source,
}) async {
  final encodedBytes = item['bytes']?.toString();
  final bytes =
      encodedBytes == null ? source?.bytes : base64Decode(encodedBytes);
  final raster = encodedBytes == null ? source?.image : null;
  if (bytes == null || raster == null && bytes.isEmpty) {
    throw const FormatException('图片元素缺少数据');
  }
  return PlacedImage(
    id: item['id']?.toString() ?? newPlacedImageId(),
    name: item['name']?.toString() ?? '图片元素',
    bytes: bytes,
    image: raster ?? await decodeOriginalImage(bytes),
    x: _number(item, 'x'),
    y: _number(item, 'y'),
    width: _number(item, 'width', 160),
    height: _number(item, 'height', 160),
    rotation: _number(item, 'rotation'),
    opacity: _number(item, 'opacity', 1).clamp(0, 1),
    fit: _enumValue(
      PlacedImageFit.values,
      item['fit'],
      PlacedImageFit.contain,
    ),
    cropX: _number(item, 'cropX', .5).clamp(0, 1),
    cropY: _number(item, 'cropY', .5).clamp(0, 1),
    layer: _enumValue(
      PlacedImageLayer.values,
      item['layer'],
      PlacedImageLayer.aboveBubbles,
    ),
    bubbleId: item['bubbleId']?.toString(),
  );
}

BubblePlacement _decodePlacement(
  Map<String, dynamic> item,
  CaptionLine caption, {
  Map<String, String> fontAliases = const {},
}) {
  final storedFamily =
      normalizeBubbleFontFamily(item['fontFamily']?.toString());
  final assetId = item['fontAssetId']?.toString();
  final record = FontLibrary.instance.recordFor(assetId ?? storedFamily);
  final family =
      fontAliases[storedFamily] ?? record?.runtimeFamily ?? storedFamily;
  return BubblePlacement(
    caption: caption,
    x: _number(item, 'x'),
    y: _number(item, 'y'),
    width: _number(item, 'width'),
    height: _number(item, 'height'),
    shape: _enumValue(BubbleShape.values, item['shape'], BubbleShape.ellipse),
    tailX: .5,
    tailY: _number(item, 'tailY', 1.15),
    tailDirection: _decodeTailDirection(item['tailDirection']),
    fontSize: _number(item, 'fontSize', 34),
    textSizeMode:
        _enumValue(TextSizeMode.values, item['textSizeMode'], TextSizeMode.fit),
    textStrokeWidth: _number(item, 'textStrokeWidth'),
    textStrokeColorValue:
        (item['textStrokeColorValue'] as num?)?.toInt() ?? 0xff000000,
    letterSpacing: _number(item, 'letterSpacing'),
    textAlign: _decodeTextAlign(item['textAlign']),
    fontAssetId: assetId ?? FontLibrary.instance.recordFor(family)?.id,
    fontDisplayName: item['fontDisplayName']?.toString() ??
        FontLibrary.instance.recordFor(family)?.displayName,
    styleId: item['styleId']?.toString(),
    lineHeight: _number(item, 'lineHeight', 1.25),
    strokeWidth: _number(item, 'strokeWidth', 3),
    fillOpacity: _number(item, 'fillOpacity', 1).clamp(0, 1),
    fontFamily: family,
    fontColorValue: (item['fontColorValue'] as num?)?.toInt() ?? 0xff141518,
  );
}

Future<ProjectData> decodeProject(Uint8List bytes) async {
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map<String, dynamic> ||
      root['format'] != 'bubble-caption-studio' ||
      (root['schemaVersion'] != 1 &&
          root['schemaVersion'] != 2 &&
          root['schemaVersion'] != 3)) {
    throw const FormatException('不是受支持的气泡字幕工程文件');
  }
  return _decodeProjectRoot(root);
}

Future<ProjectData> decodeProjectManifest(
    Uint8List bytes, Future<Uint8List> Function(String pageId) loadImage,
    [Future<Uint8List> Function(String assetId)? loadPlacedImage]) async {
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map<String, dynamic> ||
      root['format'] != 'bubble-caption-studio-manifest' ||
      (root['schemaVersion'] != 2 && root['schemaVersion'] != 3)) {
    throw const FormatException('不是受支持的增量工程清单');
  }
  return _decodeProjectRoot(
    root,
    loadImage: loadImage,
    loadPlacedImage: loadPlacedImage,
  );
}

Future<ProjectData> _decodeProjectRoot(
  Map<String, dynamic> root, {
  Future<Uint8List> Function(String pageId)? loadImage,
  Future<Uint8List> Function(String assetId)? loadPlacedImage,
}) async {
  final revision = _decodeRevision(root);
  final rawPages = root['pages'];
  if (rawPages is! List || rawPages.isEmpty) {
    throw const FormatException('工程中没有图片页面');
  }
  final pages = <ImagePage>[];
  final previewDimension = previewDimensionForPageCount(rawPages.length);
  final fonts = <String, Uint8List>{};
  final fontWarnings = <String>[];
  final fontAliases = <String, String>{};
  final fontMetadata = root['fontMetadata'] is Map<String, dynamic>
      ? root['fontMetadata'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final fontPayloads = <String, Uint8List>{};
  final fontAssetReferences = <String, String>{};
  final rawFonts = root['fonts'];
  if (rawFonts is Map<String, dynamic>) {
    for (final entry in rawFonts.entries) {
      try {
        fontPayloads[entry.key] = base64Decode(entry.value.toString());
      } catch (error) {
        fontWarnings.add('字体“${entry.key}”数据损坏：$error');
      }
    }
  }
  final externalFonts = root['fontAssets'];
  if (externalFonts is Map<String, dynamic>) {
    for (final entry in externalFonts.entries) {
      fontAssetReferences[entry.key] = entry.value.toString();
      try {
        if (loadPlacedImage == null) {
          throw const FormatException('工程没有字体素材读取器');
        }
        fontPayloads[entry.key] = await loadPlacedImage(entry.value.toString());
      } catch (error) {
        fontWarnings.add('字体素材“${entry.key}”无法读取，使用替代字体：$error');
      }
    }
  }
  for (final entry in fontPayloads.entries) {
    try {
      final fontBytes = entry.value;
      final metadata = fontMetadata[entry.key] is Map<String, dynamic>
          ? fontMetadata[entry.key] as Map<String, dynamic>
          : null;
      final expectedId = metadata?['id']?.toString();
      if (expectedId != null && expectedId != fontAssetIdForBytes(fontBytes)) {
        // Do not promote substituted bytes on the next autosave. The original
        // reference/identity remains available for recovery from storage/backup.
        throw const FormatException('字体素材 SHA256 与工程记录不一致，已拒绝。');
      }
      // Keep original bytes if registration fails, so a repair/retry is
      // possible; failed assets are never marked successfully registered.
      fonts[entry.key] = fontBytes;
      final asset = await FontLibrary.instance.ensureRegisteredAsset(
        fontBytes,
        expectedId: expectedId,
        // A schema2 font key is a loader alias, not the user's font name.
        // Without stored human metadata, inspectFont supplies the real family.
        displayName: metadata?['displayName']?.toString(),
      );
      fonts.remove(entry.key);
      fonts[asset.runtimeFamily] = fontBytes;
      fontAliases[entry.key] = asset.runtimeFamily;
    } catch (error) {
      fontWarnings.add('字体“${entry.key}”无法加载，使用替代字体：$error');
    }
  }
  try {
    for (final raw in rawPages) {
      if (raw is! Map<String, dynamic>) continue;
      final pageId = raw['pageId']?.toString();
      if (pageId == null || pageId.isEmpty) {
        throw const FormatException('工程图片缺少 pageId');
      }
      final imageBytes = loadImage == null
          ? base64Decode(raw['sourceImage'] as String)
          : await loadImage(pageId);
      final preview = await decodeImagePreview(
        imageBytes,
        maxDimension: previewDimension,
      );
      final page = ImagePage(
        name: raw['name'] as String,
        bytes: imageBytes,
        image: preview.image,
        originalWidth: preview.originalWidth,
        originalHeight: preview.originalHeight,
        pageId: pageId,
        orderRank: (raw['orderRank'] as num?)?.toInt() ?? pages.length,
      )..approved = raw['approved'] == true;
      pages.add(page);
      final declaredWidth = (raw['originalWidth'] as num?)?.toInt();
      final declaredHeight = (raw['originalHeight'] as num?)?.toInt();
      if ((declaredWidth != null && declaredWidth != page.originalWidth) ||
          (declaredHeight != null && declaredHeight != page.originalHeight)) {
        throw FormatException('${page.name} 的原图尺寸记录与图片数据不一致');
      }
      final rawCaptions = raw['captions'] as List? ?? const [];
      page.captions = [
        for (final item in rawCaptions.whereType<Map<String, dynamic>>())
          CaptionLine(
            speaker: item['speaker']?.toString() ?? '',
            text: item['text']?.toString() ?? '',
            bubbleId: item['bubbleId']?.toString() ?? '',
          ),
      ];
      final rawPlacements = raw['placements'] as List? ?? const [];
      for (var i = 0;
          i < rawPlacements.length && i < page.captions.length;
          i++) {
        final item = rawPlacements[i];
        if (item is! Map<String, dynamic>) continue;
        page.placements.add(
          _decodePlacement(item, page.captions[i], fontAliases: fontAliases),
        );
      }
      if (page.captions.length != page.placements.length) {
        throw FormatException('${page.name} 的字幕与气泡数量不一致');
      }
      for (final item in (raw['placedImages'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        try {
          final id = item['id']?.toString() ?? '';
          final assetBytes =
              item.containsKey('bytes') || loadPlacedImage == null
                  ? null
                  : await loadPlacedImage(id);
          final source = item.containsKey('bytes') || loadPlacedImage == null
              ? null
              : PlacedImage(
                  id: id,
                  name: item['name']?.toString() ?? '图片元素',
                  bytes: assetBytes!,
                  image: await decodeOriginalImage(assetBytes),
                  x: 0,
                  y: 0,
                  width: 1,
                  height: 1,
                );
          page.placedImages.add(await _decodePlacedImage(item, source: source));
        } catch (_) {
          // Preserve the rest of an older or partially damaged project.
        }
      }
    }
  } catch (_) {
    for (final page in pages) {
      page.dispose();
    }
    rethrow;
  }
  if (pages.isEmpty) throw const FormatException('工程中没有可读取的页面');
  pages.sort((a, b) => a.orderRank.compareTo(b.orderRank));
  for (var i = 0; i < pages.length; i++) {
    pages[i].orderRank = i;
  }
  return ProjectData(
    pages: pages,
    script: root['script']?.toString() ?? '',
    fonts: fonts,
    fontWarnings: fontWarnings,
    fontAliases: fontAliases,
    fontAssetReferences: fontAssetReferences,
    schemaVersion: (root['schemaVersion'] as num?)?.toInt() ?? 1,
    revision: revision,
  );
}

void _validateRevision(int? revision) {
  if (revision != null && revision < 0) {
    throw ArgumentError.value(
        revision, 'revision', 'Revision cannot be negative');
  }
}

int? _decodeRevision(Map<String, dynamic> root) {
  final revision = root['revision'];
  if (revision == null) return null;
  if (revision is! int || revision < 0) {
    throw const FormatException('工程 revision 必须是非负整数。');
  }
  return revision;
}

Map<String, String> _referencedFontMetadata(String family) {
  final record = FontLibrary.instance.recordFor(family);
  final hash = RegExp(r'^BCS_Font_([0-9a-f]{64})_face0$').firstMatch(family);
  return {
    if (record != null || hash != null)
      'id': record?.id ?? 'sha256:${hash!.group(1)}:face0',
    'displayName': record?.displayName ?? '导入字体',
    'runtimeFamily': family,
  };
}

double _number(Map<String, dynamic> map, String key, [double fallback = 0]) =>
    (map[key] is num && (map[key] as num).isFinite)
        ? (map[key] as num).toDouble()
        : fallback;

ui.TextAlign _decodeTextAlign(Object? value) => switch (value) {
      'left' || 'start' => ui.TextAlign.left,
      'right' || 'end' => ui.TextAlign.right,
      _ => ui.TextAlign.center,
    };

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

TailDirection _decodeTailDirection(Object? raw) => switch (raw) {
      'upLeft' => TailDirection.upLeft,
      'upRight' => TailDirection.upRight,
      'downLeft' => TailDirection.downLeft,
      'downRight' => TailDirection.downRight,
      'up' => TailDirection.upRight,
      'down' => TailDirection.downRight,
      'left' => TailDirection.downLeft,
      'right' => TailDirection.downRight,
      _ => TailDirection.downRight,
    };
