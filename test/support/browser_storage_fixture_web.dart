import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

JSAny? _originalPicker;
final _files = <String, Uint8List>{};

void setLegacyValue(String key, String value) =>
    (globalContext['localStorage'] as JSObject)
        .callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);

String? legacyValue(String key) => ((globalContext['localStorage'] as JSObject)
        .callMethod<JSAny?>('getItem'.toJS, key.toJS) as JSString?)
    ?.toDart;

JSObject _error(String name) => (globalContext['DOMException'] as JSFunction)
    .callAsConstructor<JSObject>('fixture'.toJS, name.toJS);

void installExportPicker(String mode) {
  _originalPicker = globalContext['showDirectoryPicker'];
  if (mode == 'missing') {
    globalContext['showDirectoryPicker'] = null;
    return;
  }
  globalContext['showDirectoryPicker'] = ((JSObject options) {
    if (mode == 'cancel') {
      return Future<JSObject>.error(_error('AbortError')).toJS;
    }
    if (mode == 'denied') {
      return Future<JSObject>.error(_error('NotAllowedError')).toJS;
    }
    return Future.value(_directory()).toJS;
  }).toJS;
}

void restoreExportPicker() {
  globalContext['showDirectoryPicker'] = _originalPicker;
}

Uint8List? fakeExportedBytes(String name) => _files[name];

JSObject _file(String name) {
  final file = JSObject();
  file['kind'] = 'file'.toJS;
  file['createWritable'] = (() {
    final stream = JSObject();
    Uint8List? pending;
    stream['write'] = ((JSUint8Array bytes) {
      pending = Uint8List.fromList(bytes.toDart);
      return Future<JSAny?>.value(null).toJS;
    }).toJS;
    stream['close'] = (() {
      if (pending != null) _files[name] = pending!;
      return Future<JSAny?>.value(null).toJS;
    }).toJS;
    stream['abort'] = (() {
      pending = null;
      return Future<JSAny?>.value(null).toJS;
    }).toJS;
    return Future.value(stream).toJS;
  }).toJS;
  return file;
}

JSObject _directory() {
  final directory = JSObject();
  directory['name'] = 'Fixture Export'.toJS;
  directory['getFileHandle'] = ((JSString rawName, JSObject options) {
    final name = rawName.toDart;
    final create = (options['create'] as JSBoolean?)?.toDart ?? false;
    if (!create && !_files.containsKey(name)) {
      return Future<JSObject>.error(_error('NotFoundError')).toJS;
    }
    return Future.value(_file(name)).toJS;
  }).toJS;
  directory['entries'] = (() {
    final names = _files.keys.toList();
    var index = 0;
    final iterator = JSObject();
    iterator['next'] = (() {
      final entry = JSObject();
      entry['done'] = (index >= names.length).toJS;
      if (index < names.length) {
        final name = names[index++];
        entry['value'] = <JSAny?>[name.toJS, _file(name)].toJS;
      }
      return Future.value(entry).toJS;
    }).toJS;
    return iterator;
  }).toJS;
  return directory;
}
