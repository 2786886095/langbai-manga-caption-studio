import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'models.dart';

/// Shared, retained source assets. Editing/history never owns or modifies pixels.
class DocumentAssetPool {
  final Map<String, ui.Image> _images = {};
  final Map<String, Uint8List> _bytes = {};
  Uint8List retainPageBytes(ImagePage page) =>
      _bytes.putIfAbsent('page:${page.pageId}', () => page.bytes);
  Uint8List retainPlacedBytes(PlacedImage image) =>
      _bytes.putIfAbsent('asset:${image.id}', () => image.bytes);
  ui.Image retain(ImagePage page) =>
      _images.putIfAbsent('page:${page.pageId}', () => page.image.clone());
  ui.Image retainPlacedImage(PlacedImage image) =>
      _images.putIfAbsent('asset:${image.id}', () => image.image.clone());
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes.clear();
  }
}

@immutable
class TextElement {
  const TextElement(this.placement);
  final BubblePlacement placement;
  String get id => placement.caption.bubbleId;
  String get text => placement.caption.text;
}

@immutable
class DocumentPage {
  DocumentPage.capture(ImagePage page, DocumentAssetPool pool)
      : id = page.pageId,
        name = page.name,
        bytes = pool.retainPageBytes(page),
        image = pool.retain(page),
        width = page.originalWidth,
        height = page.originalHeight,
        orderRank = page.orderRank,
        approved = page.approved,
        elements = List.unmodifiable(page.placements.map(TextElement.new)),
        images = List.unmodifiable(page.placedImages.map((i) => i.copyWith(
            image: pool.retainPlacedImage(i),
            bytes: pool.retainPlacedBytes(i))));
  final String id, name;
  final Uint8List bytes;
  final ui.Image image;
  final int width, height, orderRank;
  final bool approved;
  final List<TextElement> elements;
  final List<PlacedImage> images;
  ImagePage toPage() {
    final page = ImagePage(
        pageId: id,
        orderRank: orderRank,
        name: name,
        bytes: bytes,
        image: image.clone(),
        originalWidth: width,
        originalHeight: height);
    page.placements = elements.map((e) => e.placement.copyWith()).toList();
    page.captions = page.placements.map((e) => e.caption).toList();
    page.placedImages =
        images.map((e) => e.copyWith(image: e.image.clone())).toList();
    page.approved = approved;
    return page;
  }
}

/// The authoritative immutable revision. UI pages are a disposable projection.
@immutable
class ProjectDocument {
  ProjectDocument.capture(List<ImagePage> source, DocumentAssetPool pool,
      {required this.revision,
      required this.script,
      required this.selectedPage,
      required this.selectedBubble,
      Map<String, Uint8List> fonts = const {}})
      : pages =
            List.unmodifiable(source.map((p) => DocumentPage.capture(p, pool))),
        fonts = Map.unmodifiable(fonts);
  final int revision, selectedPage, selectedBubble;
  final String script;
  final List<DocumentPage> pages;
  final Map<String, Uint8List> fonts;
  List<ImagePage> toPages() => pages.map((p) => p.toPage()).toList();
  bool sameContent(ProjectDocument other) =>
      script == other.script &&
      mapEquals(fonts, other.fonts) &&
      _samePages(pages, other.pages);
  static bool _samePages(List<DocumentPage> a, List<DocumentPage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].orderRank != b[i].orderRank ||
          !listEquals(a[i].elements.map(_textKey).toList(),
              b[i].elements.map(_textKey).toList()) ||
          a[i].approved != b[i].approved ||
          !listEquals(a[i].images.map(_imageKey).toList(),
              b[i].images.map(_imageKey).toList())) return false;
    }
    // Script serializes every text object property and geometry.
    return true;
  }

  static String _imageKey(PlacedImage i) =>
      '${i.id}:${i.bubbleId}:${i.x}:${i.y}:'
      '${i.width}:${i.height}:${i.rotation}:${i.opacity}:${i.fit}:${i.cropX}:${i.cropY}:${i.layer}';
  static String _textKey(TextElement e) {
    final b = e.placement;
    return '${e.id}:${e.text}:${b.x}:${b.y}:${b.width}:${b.height}:${b.shape}:'
        '${b.tailDirection}:${b.fontFamily}:${b.fontAssetId}:${b.fontDisplayName}:'
        '${b.fontSize}:${b.fontColorValue}:${b.lineHeight}:${b.strokeWidth}:${b.fillOpacity}:'
        '${b.textSizeMode}:${b.textStrokeWidth}:${b.textStrokeColorValue}:${b.letterSpacing}:${b.textAlign}:${b.styleId}';
  }
}

class DocumentCommand {
  DocumentCommand(this.before, this.after, this.label, this.group);
  final ProjectDocument before;
  ProjectDocument after;
  final String label;
  final String? group;
}

class EditorHistory {
  final List<DocumentCommand> undoEntries = [];
  final List<DocumentCommand> redoEntries = [];
  String? _openGroup;
  bool record(ProjectDocument before, ProjectDocument after, String label,
      {String? group}) {
    if (before.sameContent(after)) return false;
    if (group != null &&
        group == _openGroup &&
        undoEntries.isNotEmpty &&
        undoEntries.last.group == group) {
      undoEntries.last.after = after;
    } else {
      undoEntries.add(DocumentCommand(before, after, label, group));
      if (undoEntries.length > 100) undoEntries.removeAt(0);
    }
    _openGroup = group;
    redoEntries.clear();
    return true;
  }

  void finishGroup() => _openGroup = null;
  ProjectDocument? undo() {
    finishGroup();
    if (undoEntries.isEmpty) return null;
    final command = undoEntries.removeLast();
    redoEntries.add(command);
    return command.before;
  }

  ProjectDocument? redo() {
    finishGroup();
    if (redoEntries.isEmpty) return null;
    final command = redoEntries.removeLast();
    undoEntries.add(command);
    return command.after;
  }

  void clear() {
    undoEntries.clear();
    redoEntries.clear();
    finishGroup();
  }
}
