import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'app_settings.dart' show AppSettings;

JSObject? get _bridge => globalContext.has('desktopBridge')
    ? globalContext['desktopBridge'] as JSObject?
    : null;
JSObject get _storage => globalContext['localStorage'] as JSObject;

Future<AppSettings> loadAppSettings() async {
  final bridge = _bridge;
  String? raw;
  if (bridge != null) {
    final value =
        await bridge.callMethod<JSPromise<JSAny?>>('getSettings'.toJS).toDart;
    raw = (value as JSString?)?.toDart;
  } else {
    raw = (_storage.callMethod<JSAny?>('getItem'.toJS, 'bcs-settings'.toJS)
            as JSString?)
        ?.toDart;
  }
  if (raw == null) return const AppSettings();
  try {
    return AppSettings.fromJson(jsonDecode(raw));
  } catch (_) {
    return const AppSettings();
  }
}

Future<void> saveAppSettings(AppSettings settings) async {
  final raw = jsonEncode(settings.toJson());
  final bridge = _bridge;
  if (bridge != null) {
    await bridge
        .callMethod<JSPromise<JSAny?>>(
          'saveSettings'.toJS,
          {'json': raw}.jsify(),
        )
        .toDart;
  } else {
    _storage.callMethod<JSAny?>('setItem'.toJS, 'bcs-settings'.toJS, raw.toJS);
  }
}

Future<String?> chooseExportDirectory() async {
  final bridge = _bridge;
  if (bridge == null) return null;
  final value = await bridge
      .callMethod<JSPromise<JSAny?>>('chooseExportDirectory'.toJS)
      .toDart;
  return (value as JSString?)?.toDart;
}
