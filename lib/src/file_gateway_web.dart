import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'app_localization.dart' show tr;
import 'file_gateway.dart' show OpenedBinaryFile;

JSObject? get _desktopBridge {
  if (!globalContext.has('desktopBridge')) return null;
  return globalContext['desktopBridge'] as JSObject?;
}

final _directoryHandles = <String, JSObject>{};
var _directorySequence = 0;
const _downloadTarget = 'browser-download:individual-png';

String _errorName(Object error) {
  try {
    return ((error as JSObject)['name'] as JSString?)?.toDart ?? '';
  } catch (_) {
    return '';
  }
}

String _safeFileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

Future<String> _downloadBytes(String name, Uint8List bytes, String mime) async {
  final blob =
      (globalContext['Blob'] as JSFunction).callAsConstructor<JSObject>(
    [Uint8List.fromList(bytes).toJS].toJS,
    {'type': mime}.jsify(),
  );
  final urls = globalContext['URL'] as JSObject;
  final objectUrl = urls.callMethod<JSString>('createObjectURL'.toJS, blob);
  final document = globalContext['document'] as JSObject;
  final anchor = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  anchor['href'] = objectUrl;
  anchor['download'] = _safeFileName(name).toJS;
  final body = document['body'] as JSObject?;
  if (body == null) {
    throw StateError('Browser download document is unavailable');
  }
  body.callMethod<JSAny?>('appendChild'.toJS, anchor);
  try {
    anchor.callMethod<JSAny?>('click'.toJS);
  } finally {
    anchor.callMethod<JSAny?>('remove'.toJS);
    Timer(const Duration(seconds: 2), () {
      urls.callMethod<JSAny?>('revokeObjectURL'.toJS, objectUrl);
    });
  }
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return 'browser-download:${Uri.encodeComponent(_safeFileName(name))}';
}

Future<String?> saveBinaryFile({
  required String title,
  required String fileName,
  required Uint8List bytes,
  required String kind,
}) async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    return _downloadBytes(
      fileName,
      bytes,
      kind == 'image'
          ? 'image/png'
          : kind == 'text'
              ? 'text/plain;charset=utf-8'
              : 'application/json',
    );
  }
  final request = <String, Object>{
    'title': title,
    'fileName': fileName,
    'bytes': Uint8List.fromList(bytes).toJS,
    'kind': kind,
  }.jsify()!;
  final promise = bridge.callMethod<JSPromise<JSAny?>>(
    'saveFile'.toJS,
    request,
  );
  final value = await promise.toDart;
  return (value as JSString?)?.toDart;
}

Future<OpenedBinaryFile?> openProjectFile() async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.bytes == null) return null;
    return OpenedBinaryFile(name: file.name, bytes: file.bytes!);
  }
  final promise = bridge.callMethod<JSPromise<JSAny?>>('openProject'.toJS);
  final value = await promise.toDart;
  if (value == null) return null;
  final object = value as JSObject;
  return OpenedBinaryFile(
    name: (object['name'] as JSString).toDart,
    path: (object['path'] as JSString?)?.toDart,
    bytes: object.has('bytes')
        ? (object['bytes'] as JSUint8Array).toDart
        : base64Decode((object['base64'] as JSString).toDart),
  );
}

Future<List<OpenedBinaryFile>?> pickImageFiles() async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return null;
    return [
      for (final file in result.files)
        if (file.bytes != null)
          OpenedBinaryFile(name: file.name, bytes: file.bytes!),
    ];
  }
  final pickPromise =
      bridge.callMethod<JSPromise<JSAny?>>('pickImagePaths'.toJS);
  final picked = await pickPromise.toDart;
  if (picked == null) return null;
  final entries = jsonDecode((picked as JSString).toDart) as List<dynamic>;
  final files = <OpenedBinaryFile>[];
  for (final entry in entries.whereType<Map<String, dynamic>>()) {
    final filePath = entry['path']?.toString();
    if (filePath == null) continue;
    final request = <String, Object>{'path': filePath}.jsify()!;
    final readPromise = bridge.callMethod<JSPromise<JSAny?>>(
      'readImageFile'.toJS,
      request,
    );
    final value = await readPromise.toDart;
    files.add(
      OpenedBinaryFile(
        name: entry['name']?.toString() ?? filePath,
        path: filePath,
        bytes: (value as JSUint8Array).toDart,
      ),
    );
  }
  return files;
}

Future<String?> chooseImageExportDirectory({String? initialDirectory}) async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    final picker = globalContext['showDirectoryPicker'];
    if (picker == null || !picker.typeofEquals('function')) {
      return _downloadTarget;
    }
    try {
      final handle = await globalContext
          .callMethod<JSPromise<JSObject>>(
            'showDirectoryPicker'.toJS,
            {'mode': 'readwrite', 'id': 'langbai-caption-export'}.jsify(),
          )
          .toDart;
      final name = (handle['name'] as JSString?)?.toDart ?? '成图文件夹';
      final token =
          'browser-directory:${++_directorySequence}:${Uri.encodeComponent(name)}';
      _directoryHandles[token] = handle;
      return token;
    } catch (error) {
      if (_errorName(error) == 'AbortError') return null;
      if (_errorName(error) == 'NotSupportedError') return _downloadTarget;
      throw StateError('浏览器无法授权导出文件夹，请检查权限或使用逐图下载：$error');
    }
  }
  final request = <String, Object>{
    if (initialDirectory != null) 'initialDirectory': initialDirectory,
  }.jsify()!;
  final promise = bridge.callMethod<JSPromise<JSAny?>>(
    'chooseImageExportDirectory'.toJS,
    request,
  );
  final value = await promise.toDart;
  return (value as JSString?)?.toDart;
}

Future<bool> exportImageExists(String directory, String fileName) async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    if (directory.startsWith('browser-download:')) return false;
    final handle = _directoryHandles[directory];
    if (handle == null) throw StateError('浏览器导出目录授权已失效，请重新选择目录');
    try {
      await handle
          .callMethod<JSPromise<JSObject>>('getFileHandle'.toJS,
              _safeFileName(fileName).toJS, {'create': false}.jsify())
          .toDart;
      return true;
    } catch (error) {
      if (_errorName(error) == 'NotFoundError') return false;
      rethrow;
    }
  }
  final request = <String, Object>{
    'directory': directory,
    'fileName': fileName,
  }.jsify()!;
  final promise = bridge.callMethod<JSPromise<JSAny?>>(
    'exportImageExists'.toJS,
    request,
  );
  final value = await promise.toDart;
  return (value as JSBoolean?)?.toDart ?? false;
}

Future<void> writeExportImage(
  String directory,
  String fileName,
  Uint8List bytes, {
  required bool overwrite,
}) async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    if (directory.startsWith('browser-download:')) {
      await _downloadBytes(fileName, bytes, 'image/png');
      return;
    }
    final handle = _directoryHandles[directory];
    if (handle == null) throw StateError('浏览器导出目录授权已失效，请重新选择目录');
    if (!overwrite && await exportImageExists(directory, fileName)) {
      throw StateError(tr('目标图片已存在'));
    }
    final file = await handle
        .callMethod<JSPromise<JSObject>>('getFileHandle'.toJS,
            _safeFileName(fileName).toJS, {'create': true}.jsify())
        .toDart;
    final writer = await file
        .callMethod<JSPromise<JSObject>>('createWritable'.toJS)
        .toDart;
    try {
      await writer
          .callMethod<JSPromise<JSAny?>>(
              'write'.toJS, Uint8List.fromList(bytes).toJS)
          .toDart;
      await writer.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    } catch (_) {
      try {
        await writer.callMethod<JSPromise<JSAny?>>('abort'.toJS).toDart;
      } catch (_) {
        // Preserve the original write failure, not a secondary abort failure.
      }
      rethrow;
    }
    return;
  }
  final request = <String, Object>{
    'directory': directory,
    'fileName': fileName,
    'bytes': Uint8List.fromList(bytes).toJS,
    'overwrite': overwrite,
  }.jsify()!;
  final promise = bridge.callMethod<JSPromise<JSAny?>>(
    'writeExportImage'.toJS,
    request,
  );
  await promise.toDart;
}

Future<List<String>> listBrowserExportFiles(String target) async {
  if (_desktopBridge != null || target.startsWith('browser-download:')) {
    return const [];
  }
  final directory = _directoryHandles[target];
  if (directory == null) throw StateError('浏览器导出目录授权已失效');
  final iterator = directory.callMethod<JSObject>('entries'.toJS);
  final names = <String>[];
  while (true) {
    final entry =
        await iterator.callMethod<JSPromise<JSObject>>('next'.toJS).toDart;
    if ((entry['done'] as JSBoolean).toDart) break;
    final value = (entry['value'] as JSArray<JSAny?>).toDart;
    final handle = value[1] as JSObject;
    if ((handle['kind'] as JSString).toDart == 'file') {
      names.add((value[0] as JSString).toDart);
    }
  }
  names.sort();
  return names;
}

bool get supportsIndividualBrowserDownloads => _desktopBridge == null;
