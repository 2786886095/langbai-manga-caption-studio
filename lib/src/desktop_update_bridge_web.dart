import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? get _bridge => globalContext.has('desktopBridge')
    ? globalContext['desktopBridge'] as JSObject?
    : null;

Future<String?> invokeDesktopUpdate(String method) async {
  final bridge = _bridge;
  if (bridge == null || !bridge.has(method)) return null;
  final promise = bridge.callMethod<JSPromise<JSAny?>>(method.toJS);
  final value = await promise.toDart;
  return (value as JSString?)?.toDart;
}
