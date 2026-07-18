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

Future<String?> saveBinaryFile({
  required String title,
  required String fileName,
  required Uint8List bytes,
  required String kind,
}) async {
  final bridge = _desktopBridge;
  if (bridge == null) {
    return FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: fileName,
      bytes: bytes,
    );
  }
  final request = <String, Object>{
    'title': title,
    'fileName': fileName,
    'bytes': bytes.toJS,
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
  if (bridge == null) return null;
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
  if (bridge == null) return false;
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
    await saveBinaryFile(
      title: tr('保存字幕成图'),
      fileName: fileName,
      bytes: bytes,
      kind: 'image',
    );
    return;
  }
  final request = <String, Object>{
    'directory': directory,
    'fileName': fileName,
    'bytes': bytes.toJS,
    'overwrite': overwrite,
  }.jsify()!;
  final promise = bridge.callMethod<JSPromise<JSAny?>>(
    'writeExportImage'.toJS,
    request,
  );
  await promise.toDart;
}
