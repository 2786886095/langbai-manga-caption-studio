import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'sticker_library.dart' show StickerAsset;

String encodeStickerBytes(Uint8List bytes) => base64Encode(bytes);
Uint8List decodeStickerBytes(String? value) =>
    value == null ? Uint8List(0) : base64Decode(value);

JSObject? get _bridge => globalContext.has('desktopBridge')
    ? globalContext['desktopBridge'] as JSObject?
    : null;
JSObject get _storage => globalContext['localStorage'] as JSObject;

Future<List<StickerAsset>> loadStickerLibrary() async {
  String? raw;
  final bridge = _bridge;
  if (bridge != null) {
    final value = await bridge
        .callMethod<JSPromise<JSAny?>>('loadStickerLibrary'.toJS)
        .toDart;
    raw = (value as JSString?)?.toDart;
  } else {
    raw = (_storage.callMethod<JSAny?>(
      'getItem'.toJS,
      'langbai-sticker-library'.toJS,
    ) as JSString?)
        ?.toDart;
  }
  if (raw == null || raw.isEmpty) return const [];
  try {
    final root = jsonDecode(raw);
    if (root is! Map<String, dynamic> ||
        root['format'] != 'langbai-sticker-library') return const [];
    return [
      for (final item in (root['assets'] as List? ?? const [])
          .whereType<Map<String, dynamic>>())
        StickerAsset.fromJson(item),
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> saveStickerLibrary(List<StickerAsset> assets) async {
  final raw = jsonEncode({
    'format': 'langbai-sticker-library',
    'schemaVersion': 1,
    'assets': [for (final asset in assets) asset.toJson()],
  });
  final bridge = _bridge;
  if (bridge != null) {
    await bridge
        .callMethod<JSPromise<JSAny?>>(
          'saveStickerLibrary'.toJS,
          {'json': raw}.jsify(),
        )
        .toDart;
  } else {
    _storage.callMethod<JSAny?>(
      'setItem'.toJS,
      'langbai-sticker-library'.toJS,
      raw.toJS,
    );
  }
}
