import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void setPlatformWindowTitle(String title) {
  final document = globalContext['document'] as JSObject?;
  document?.setProperty('title'.toJS, title.toJS);
}
