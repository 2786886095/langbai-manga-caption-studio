import 'dart:convert';

import 'models.dart';

class ScriptImportOptions {
  const ScriptImportOptions(
      {this.text = true, this.style = true, this.geometry = true});
  final bool text, style, geometry;
}

/// Three-way field merge. Unchanged draft fields must never overwrite a newer
/// document or round hand-adjusted coordinates to exported integers.
List<BubblePlacement> mergeScriptPlacements(List<BubblePlacement> current,
    List<BubblePlacement> generated, List<CaptionLine> baseline,
    {ScriptImportOptions options = const ScriptImportOptions()}) {
  final byId = {for (final b in current) b.caption.bubbleId: b};
  final originals = {for (final c in baseline) c.bubbleId: c};
  final result = <BubblePlacement>[];
  T pick<T>(T old, T incoming, T? original, bool enabled) =>
      enabled && incoming != original ? incoming : old;
  for (final incoming in generated) {
    final old = byId[incoming.caption.bubbleId];
    if (old == null) {
      if (options.text) result.add(incoming);
      continue;
    }
    final before = originals[incoming.caption.bubbleId];
    final spec = incoming.caption.layout;
    final initial = before?.layout;
    final fontChanged = options.style &&
        spec?.fontFamily != null &&
        spec?.fontFamily != initial?.fontFamily;
    final assetChanged = options.style &&
        spec?.fontAssetId != null &&
        spec?.fontAssetId != initial?.fontAssetId;
    final nextWidth = spec?.width == null && spec?.widthPercent == null
        ? old.width
        : pick(old.width, incoming.width, initial?.width, options.geometry);
    final nextHeight = spec?.height == null && spec?.heightPercent == null
        ? old.height
        : pick(old.height, incoming.height, initial?.height, options.geometry);
    var incomingX = incoming.x;
    var incomingY = incoming.y;
    final preset = spec?.positionPreset;
    if (preset != null) {
      // A position-only import preserves hand-sized rectangles. Adjust the
      // preset anchor from the generator's default size to that retained size.
      if (spec?.x == null && spec?.xPercent == null) {
        if (preset.startsWith('右')) incomingX += incoming.width - nextWidth;
        if (preset.startsWith('中') || preset == '居中') {
          incomingX += (incoming.width - nextWidth) / 2;
        }
      }
      if (spec?.y == null && spec?.yPercent == null) {
        if (preset.endsWith('下')) incomingY += incoming.height - nextHeight;
        if (preset.endsWith('中') || preset == '居中') {
          incomingY += (incoming.height - nextHeight) / 2;
        }
      }
    }
    result.add(old.copyWith(
      caption: old.caption.copyWith(
          text: pick(old.caption.text, incoming.caption.text, before?.text,
              options.text)),
      x: spec?.x == null && spec?.xPercent == null && preset == null
          ? old.x
          : pick(old.x, incomingX, initial?.x, options.geometry),
      y: spec?.y == null && spec?.yPercent == null && preset == null
          ? old.y
          : pick(old.y, incomingY, initial?.y, options.geometry),
      width: nextWidth,
      height: nextHeight,
      shape: spec?.shape == null
          ? old.shape
          : pick(old.shape, incoming.shape, initial?.shape, options.style),
      tailDirection: spec?.tailDirection == null
          ? old.tailDirection
          : pick(old.tailDirection, incoming.tailDirection,
              initial?.tailDirection, options.style),
      fontFamily: fontChanged ? incoming.fontFamily : old.fontFamily,
      fontAssetId: fontChanged && !assetChanged
          ? null
          : (spec?.fontAssetId == null
              ? old.fontAssetId
              : pick(old.fontAssetId, incoming.fontAssetId,
                  initial?.fontAssetId, options.style)),
      fontDisplayName: fontChanged || assetChanged
          ? incoming.fontDisplayName
          : old.fontDisplayName,
      fontColorValue: spec?.fontColorValue == null
          ? old.fontColorValue
          : pick(old.fontColorValue, incoming.fontColorValue,
              initial?.fontColorValue, options.style),
      fontSize: spec?.fontSize == null
          ? old.fontSize
          : pick(old.fontSize, incoming.fontSize, initial?.fontSize,
              options.style),
      lineHeight: spec?.lineHeight == null
          ? old.lineHeight
          : pick(old.lineHeight, incoming.lineHeight, initial?.lineHeight,
              options.style),
      strokeWidth: spec?.strokeWidth == null
          ? old.strokeWidth
          : pick(old.strokeWidth, incoming.strokeWidth, initial?.strokeWidth,
              options.style),
      fillOpacity: spec?.fillOpacity == null
          ? old.fillOpacity
          : pick(old.fillOpacity, incoming.fillOpacity, initial?.fillOpacity,
              options.style),
      textSizeMode: spec?.textSizeMode == null
          ? old.textSizeMode
          : pick(old.textSizeMode, incoming.textSizeMode, initial?.textSizeMode,
              options.style),
      textStrokeWidth: spec?.textStrokeWidth == null
          ? old.textStrokeWidth
          : pick(old.textStrokeWidth, incoming.textStrokeWidth,
              initial?.textStrokeWidth, options.style),
      textStrokeColorValue: spec?.textStrokeColorValue == null
          ? old.textStrokeColorValue
          : pick(old.textStrokeColorValue, incoming.textStrokeColorValue,
              initial?.textStrokeColorValue, options.style),
      letterSpacing: spec?.letterSpacing == null
          ? old.letterSpacing
          : pick(old.letterSpacing, incoming.letterSpacing,
              initial?.letterSpacing, options.style),
      textAlign: spec?.textAlign == null
          ? old.textAlign
          : pick(old.textAlign, incoming.textAlign, initial?.textAlign,
              options.style),
      styleId: spec?.styleId == null
          ? old.styleId
          : pick(
              old.styleId, incoming.styleId, initial?.styleId, options.style),
    ));
  }
  if (!options.text) {
    final ids = result.map((b) => b.caption.bubbleId).toSet();
    result.addAll(current.where((b) => !ids.contains(b.caption.bubbleId)));
  }
  return result;
}

String linkedTextStyleKey(BubblePlacement b) => jsonEncode([
      b.fontAssetId ?? b.fontFamily,
      b.fontDisplayName,
      b.fontSize,
      b.fontColorValue,
      b.lineHeight,
      b.textSizeMode.name,
      b.letterSpacing,
      b.textAlign.name,
      b.textStrokeWidth,
      b.textStrokeColorValue,
    ]);

/// Call on the entire candidate project BEFORE mutating the live document.
/// One changed definition updates the linked group. Conflicting changed/new
/// definitions are rejected, never resolved by an arbitrary last object.
List<BubblePlacement> mergeLinkedStyleChanges(
    List<BubblePlacement> before, List<BubblePlacement> after,
    {bool applyStyle = true}) {
  if (!applyStyle) return List.of(after);
  final originals = {for (final b in before) b.caption.bubbleId: b};
  final groups = <String, List<BubblePlacement>>{};
  for (final b in after) {
    if (b.styleId?.isNotEmpty == true) {
      groups.putIfAbsent(b.styleId!, () => []).add(b);
    }
  }
  final definitions = <String, BubblePlacement>{};
  for (final entry in groups.entries) {
    final changed = entry.value.where((b) {
      final old = originals[b.caption.bubbleId];
      return old != null &&
          old.styleId == b.styleId &&
          linkedTextStyleKey(old) != linkedTextStyleKey(b);
    }).toList();
    final candidates = changed.isEmpty ? entry.value : changed;
    if (candidates.map(linkedTextStyleKey).toSet().length > 1) {
      throw FormatException('关联文字样式“${entry.key}”有多个不同定义。'
          '请统一字体、字号、文字描边等字段，或解除该样式关联后再应用。');
    }
    definitions[entry.key] = candidates.first;
  }
  return [
    for (final b in after)
      if (definitions[b.styleId] case final source?)
        b.copyWith(
            fontFamily: source.fontFamily,
            fontAssetId: source.fontAssetId,
            fontDisplayName: source.fontDisplayName,
            fontSize: source.fontSize,
            fontColorValue: source.fontColorValue,
            lineHeight: source.lineHeight,
            textSizeMode: source.textSizeMode,
            letterSpacing: source.letterSpacing,
            textAlign: source.textAlign,
            textStrokeWidth: source.textStrokeWidth,
            textStrokeColorValue: source.textStrokeColorValue)
      else
        b,
  ];
}
