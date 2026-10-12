import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

const _storeName = 'library';
Future<JSObject>? _databaseFuture;
final _persistedIds = <String>{};

Future<JSObject> _database() => _databaseFuture ??= _openDatabase();

Future<JSObject> _openDatabase() {
  final completer = Completer<JSObject>();
  final indexedDb = globalContext['indexedDB'] as JSObject?;
  if (indexedDb == null) {
    return Future.error(StateError('浏览器不支持本地IndexedDB字体库。'));
  }
  final request = indexedDb.callMethod<JSObject>(
      'open'.toJS, 'langbai-font-library'.toJS, 1.toJS);
  request['onupgradeneeded'] = ((JSAny? _) {
    final database = request['result'] as JSObject;
    database.callMethod<JSObject>('createObjectStore'.toJS, _storeName.toJS);
  }).toJS;
  request['onsuccess'] = ((JSAny? _) {
    if (!completer.isCompleted) {
      completer.complete(request['result'] as JSObject);
    }
  }).toJS;
  request['onerror'] = ((JSAny? _) {
    _databaseFuture = null;
    if (!completer.isCompleted) {
      completer.completeError(StateError('本地字体库打开失败。'));
    }
  }).toJS;
  request['onblocked'] = ((JSAny? _) {
    _databaseFuture = null;
    if (!completer.isCompleted) {
      completer.completeError(StateError('本地字体库被其他窗口占用。'));
    }
  }).toJS;
  return completer.future;
}

Future<Map<String, dynamic>?> readFontLibrary() async {
  final database = await _database();
  final transaction = database.callMethod<JSObject>(
      'transaction'.toJS, _storeName.toJS, 'readonly'.toJS);
  final store =
      transaction.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
  final request = store.callMethod<JSObject>('get'.toJS, 'snapshot'.toJS);
  final completer = Completer<Map<String, dynamic>?>();
  request['onsuccess'] = ((JSAny? _) {
    try {
      final raw = (request['result'] as JSString?)?.toDart;
      if (raw == null) {
        completer.complete(null);
      } else {
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic> ||
            json['format'] != 'langbai-font-library') {
          throw const FormatException('本地字体库格式无效。');
        }
        for (final record in (json['fonts'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()) {
          if (record['bytes'] == null) {
            _persistedIds.add(record['id'] as String);
          }
        }
        completer.complete(json);
      }
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
  }).toJS;
  request['onerror'] =
      ((JSAny? _) => completer.completeError(StateError('本地字体库读取失败。'))).toJS;
  return completer.future;
}

Future<Uint8List?> readFontAsset(String id) async {
  final database = await _database();
  final transaction = database.callMethod<JSObject>(
      'transaction'.toJS, _storeName.toJS, 'readonly'.toJS);
  final store =
      transaction.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
  final request = store.callMethod<JSObject>('get'.toJS, 'font:$id'.toJS);
  final completer = Completer<Uint8List?>();
  request['onsuccess'] = ((JSAny? _) {
    try {
      final raw = (request['result'] as JSString?)?.toDart;
      completer.complete(raw == null ? null : base64Decode(raw));
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
  }).toJS;
  request['onerror'] =
      ((JSAny? _) => completer.completeError(StateError('字体素材读取失败。'))).toJS;
  return completer.future;
}

Future<void> writeFontLibrary(Map<String, dynamic> value) async {
  final database = await _database();
  final transaction = database.callMethod<JSObject>(
      'transaction'.toJS, _storeName.toJS, 'readwrite'.toJS);
  final completer = Completer<void>();
  transaction['oncomplete'] = ((JSAny? _) => completer.complete()).toJS;
  void failure(JSAny? _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('字体库保存失败，可能是存储配额不足。'));
    }
  }

  transaction['onerror'] = failure.toJS;
  transaction['onabort'] = failure.toJS;
  final store =
      transaction.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
  final writtenIds = <String>{};
  final records = <Map<String, dynamic>>[];
  for (final raw in (value['fonts'] as List).cast<Map<String, dynamic>>()) {
    final id = raw['id'] as String;
    if (!_persistedIds.contains(id)) {
      if (raw['bytes'] is! String) {
        transaction.callMethod<JSAny?>('abort'.toJS);
        throw const FormatException('字体素材文件缺失，未保存。');
      }
      store.callMethod<JSObject>(
          'put'.toJS, (raw['bytes'] as String).toJS, 'font:$id'.toJS);
      writtenIds.add(id);
    }
    records.add(Map<String, dynamic>.of(raw)..remove('bytes'));
  }
  store.callMethod<JSObject>('put'.toJS,
      jsonEncode({...value, 'fonts': records}).toJS, 'snapshot'.toJS);
  await completer.future;
  _persistedIds.addAll(writtenIds);
}
