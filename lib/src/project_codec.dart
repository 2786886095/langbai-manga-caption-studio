import 'dart:convert';
import 'package:flutter/services.dart';

import 'models.dart';
import 'image_decoder.dart';

class ProjectData {
  const ProjectData({
    required this.pages,
    required this.script,
    this.fonts = const {},
  });

  final List<ImagePage> pages;
  final String script;
  final Map<String, Uint8List> fonts;
}

Uint8List encodeProject(
  List<ImagePage> pages,
  String script, {
  Map<String, Uint8List> fonts = const {},
}) {
  final json = <String, Object?>{
    'format': 'bubble-caption-studio',
    'schemaVersion': 2,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'script': script,
    'fonts': {
      for (final entry in fonts.entries) entry.key: base64Encode(entry.value),
    },
    'pages': pages.map(_encodePage).toList(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

Uint8List encodeProjectEdits(List<ImagePage> pages, String script) {
  final json = <String, Object?>{
    'format': 'bubble-caption-studio-edits',
    'schemaVersion': 1,
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
      'lineHeight': bubble.lineHeight,
      'strokeWidth': bubble.strokeWidth,
      'fontFamily': bubble.fontFamily,
      'fontColorValue': bubble.fontColorValue,
    };

Map<String, Object?> _encodePage(ImagePage page) => {
      'pageId': page.pageId,
      'orderRank': page.orderRank,
      'name': page.name,
      'originalWidth': page.originalWidth,
      'originalHeight': page.originalHeight,
      'sourceImage': base64Encode(page.bytes),
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
    };

String applyProjectEdits(Uint8List bytes, List<ImagePage> pages) {
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map<String, dynamic> ||
      root['format'] != 'bubble-caption-studio-edits' ||
      root['schemaVersion'] != 1) {
    throw const FormatException('Unsupported project edit data');
  }
  final byId = {for (final page in pages) page.pageId: page};
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
    final placements = <BubblePlacement>[];
    for (var i = 0; i < captions.length; i++) {
      final item = rawPlacements[i];
      if (item is! Map<String, dynamic>) break;
      placements.add(_decodePlacement(item, captions[i]));
    }
    if (placements.length != captions.length) continue;
    page
      ..captions = captions
      ..placements = placements
      ..approved = raw['approved'] == true;
  }
  return root['script']?.toString() ?? '';
}

BubblePlacement _decodePlacement(
  Map<String, dynamic> item,
  CaptionLine caption,
) =>
    BubblePlacement(
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
      lineHeight: _number(item, 'lineHeight', 1.25),
      strokeWidth: _number(item, 'strokeWidth', 3),
      fontFamily: item['fontFamily']?.toString() ?? 'Microsoft YaHei',
      fontColorValue: (item['fontColorValue'] as num?)?.toInt() ?? 0xff141518,
    );

Future<ProjectData> decodeProject(Uint8List bytes) async {
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map<String, dynamic> ||
      root['format'] != 'bubble-caption-studio' ||
      (root['schemaVersion'] != 1 && root['schemaVersion'] != 2)) {
    throw const FormatException('不是受支持的气泡字幕工程文件');
  }
  final rawPages = root['pages'];
  if (rawPages is! List || rawPages.isEmpty) {
    throw const FormatException('工程中没有图片页面');
  }
  final pages = <ImagePage>[];
  final fonts = <String, Uint8List>{};
  final rawFonts = root['fonts'];
  if (rawFonts is Map<String, dynamic>) {
    for (final entry in rawFonts.entries) {
      try {
        final fontBytes = base64Decode(entry.value.toString());
        fonts[entry.key] = fontBytes;
        if (_loadedRuntimeFonts.add(entry.key)) {
          final loader = FontLoader(entry.key)
            ..addFont(Future.value(ByteData.sublistView(fontBytes)));
          await loader.load();
        }
      } catch (_) {
        // A damaged optional font must not make the whole project unreadable.
      }
    }
  }
  for (final raw in rawPages) {
    if (raw is! Map<String, dynamic>) continue;
    final imageBytes = base64Decode(raw['sourceImage'] as String);
    final preview = await decodeImagePreview(imageBytes);
    final page = ImagePage(
      name: raw['name'] as String,
      bytes: imageBytes,
      image: preview.image,
      originalWidth: preview.originalWidth,
      originalHeight: preview.originalHeight,
      pageId: raw['pageId']?.toString(),
      orderRank: (raw['orderRank'] as num?)?.toInt() ?? pages.length,
    )..approved = raw['approved'] == true;
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
    for (var i = 0; i < rawPlacements.length && i < page.captions.length; i++) {
      final item = rawPlacements[i];
      if (item is! Map<String, dynamic>) continue;
      page.placements.add(
        BubblePlacement(
          caption: page.captions[i],
          x: _number(item, 'x'),
          y: _number(item, 'y'),
          width: _number(item, 'width'),
          height: _number(item, 'height'),
          shape: _enumValue(
            BubbleShape.values,
            item['shape'],
            BubbleShape.ellipse,
          ),
          tailX: .5,
          tailY: _number(item, 'tailY', 1.15),
          tailDirection: _decodeTailDirection(item['tailDirection']),
          fontSize: _number(item, 'fontSize', 34),
          lineHeight: _number(item, 'lineHeight', 1.25),
          strokeWidth: _number(item, 'strokeWidth', 3),
          fontFamily: item['fontFamily']?.toString() ?? 'Microsoft YaHei',
          fontColorValue:
              (item['fontColorValue'] as num?)?.toInt() ?? 0xff141518,
        ),
      );
    }
    if (page.captions.length != page.placements.length) {
      throw FormatException('${page.name} 的字幕与气泡数量不一致');
    }
    pages.add(page);
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
  );
}

final Set<String> _loadedRuntimeFonts = {};

double _number(Map<String, dynamic> map, String key, [double fallback = 0]) =>
    (map[key] as num?)?.toDouble() ?? fallback;

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
