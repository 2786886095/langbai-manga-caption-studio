import 'dart:typed_data';

import 'file_gateway_io.dart'
    if (dart.library.js_interop) 'file_gateway_web.dart' as implementation;

class OpenedBinaryFile {
  const OpenedBinaryFile({required this.name, required this.bytes, this.path});

  final String name;
  final Uint8List bytes;
  final String? path;
}

Future<String?> saveBinaryFile({
  required String title,
  required String fileName,
  required Uint8List bytes,
  required String kind,
}) =>
    implementation.saveBinaryFile(
      title: title,
      fileName: fileName,
      bytes: bytes,
      kind: kind,
    );

Future<OpenedBinaryFile?> openProjectFile() => implementation.openProjectFile();

Future<List<OpenedBinaryFile>?> pickImageFiles() =>
    implementation.pickImageFiles();

Future<String?> chooseImageExportDirectory({String? initialDirectory}) =>
    implementation.chooseImageExportDirectory(
      initialDirectory: initialDirectory,
    );

Future<bool> exportImageExists(String directory, String fileName) =>
    implementation.exportImageExists(directory, fileName);

Future<void> writeExportImage(
  String directory,
  String fileName,
  Uint8List bytes, {
  required bool overwrite,
}) =>
    implementation.writeExportImage(
      directory,
      fileName,
      bytes,
      overwrite: overwrite,
    );
