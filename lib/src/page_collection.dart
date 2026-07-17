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
    if (previous != null) {
      result[i] = previous.copyWith(caption: captions[i]);
    } else if (id.isEmpty && i < existing.length) {
      result[i] = existing[i].copyWith(caption: captions[i]);
    }
  }
  return result;
}
