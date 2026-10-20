import 'models.dart';

List<ImagePage> mergeImagePages(
  List<ImagePage> existing,
  List<ImagePage> additions, {
  bool replace = false,
}) {
  final result = <ImagePage>[if (!replace) ...existing, ...additions];
  for (var i = 0; i < result.length; i++) {
    result[i].orderRank = i;
  }
  return result;
}

/// Keeps the user's hand-tuned geometry and appearance when only the script
/// text changes. Newly-added lines still use the generated layout.
List<BubblePlacement> preserveEditedPlacements(
  List<BubblePlacement> existing,
  List<BubblePlacement> generated,
  List<CaptionLine> captions,
) {
  final result = [...generated];
  final byId = <String, BubblePlacement>{
    for (final bubble in existing)
      if (bubble.caption.bubbleId.isNotEmpty) bubble.caption.bubbleId: bubble,
  };
  for (var i = 0; i < result.length; i++) {
    final id = captions[i].bubbleId;
    final previous = id.isNotEmpty ? byId[id] : null;
    final layout = captions[i].layout;
    final hasExplicitGeometry = layout != null &&
        (layout.x != null ||
            layout.y != null ||
            layout.width != null ||
            layout.height != null ||
            layout.xPercent != null ||
            layout.yPercent != null ||
            layout.widthPercent != null ||
            layout.heightPercent != null ||
            layout.positionPreset != null);
    final retained =
        previous ?? (id.isEmpty && i < existing.length ? existing[i] : null);
    if (retained != null && hasExplicitGeometry) {
      // A default is for new objects, not an implicit style edit when an
      // existing script object only supplies fresh geometry.
      result[i] = result[i].copyWith(
        textSizeMode: layout.textSizeMode ?? retained.textSizeMode,
        fontSize: layout.fontSize ?? retained.fontSize,
      );
    }
    if (retained != null && !hasExplicitGeometry) {
      // Keep manual placement, but explicit style directives are authoritative.
      result[i] = retained.copyWith(
        caption: captions[i],
        shape: layout?.shape,
        tailDirection: layout?.tailDirection,
        fontFamily: layout?.fontFamily == null
            ? null
            : normalizeBubbleFontFamily(layout!.fontFamily),
        fontAssetId: layout?.fontFamily != null
            ? layout?.fontAssetId
            : retained.fontAssetId,
        fontDisplayName: layout?.fontFamily != null
            ? layout?.fontDisplayName
            : retained.fontDisplayName,
        textSizeMode: layout?.textSizeMode,
        textStrokeWidth: layout?.textStrokeWidth,
        textStrokeColorValue: layout?.textStrokeColorValue,
        letterSpacing: layout?.letterSpacing,
        textAlign: layout?.textAlign,
        styleId: layout?.styleId ?? retained.styleId,
        fontColorValue: layout?.fontColorValue,
        fontSize: layout?.fontSize,
        lineHeight: layout?.lineHeight,
        strokeWidth: layout?.strokeWidth,
        fillOpacity: layout?.fillOpacity,
      );
    }
  }
  return result;
}
