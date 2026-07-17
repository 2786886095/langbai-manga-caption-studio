import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'file_gateway.dart' show OpenedBinaryFile;

Future<String?> saveBinaryFile({
  required String title,
  required String fileName,
  required Uint8List bytes,
  required String kind,
}) =>
    FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: fileName,
      bytes: bytes,
    );

Future<OpenedBinaryFile?> openProjectFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  final file = result?.files.singleOrNull;
  if (file == null || file.bytes == null) return null;
  return OpenedBinaryFile(name: file.name, bytes: file.bytes!, path: file.path);
}

Future<List<OpenedBinaryFile>?> pickImageFiles() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return null;
  return [
    for (final file in result.files)
      if (file.bytes != null)
        OpenedBinaryFile(name: file.name, bytes: file.bytes!, path: file.path),
  ];
}

Future<String?> chooseImageExportDirectory({String? initialDirectory}) =>
    FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择成图导出文件夹',
      initialDirectory: initialDirectory,
    );

String _safeExportPath(String directory, String fileName) =>
    '${Directory(directory).absolute.path}${Platform.pathSeparator}${fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';

Future<bool> exportImageExists(String directory, String fileName) =>
    File(_safeExportPath(directory, fileName)).exists();

Future<void> writeExportImage(
  String directory,
  String fileName,
  Uint8List bytes, {
  required bool overwrite,
}) async {
  final target = File(_safeExportPath(directory, fileName));
  if (!overwrite && await target.exists()) {
    throw const FileSystemException('目标图片已存在');
  }
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes, flush: true);
}
