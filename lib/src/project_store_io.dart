import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'project_store.dart' show LocalProjectSummary;

bool get supportsIncrementalProjectStorage => true;

String _storageName(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

Future<Directory> _incrementalDirectory(String id) async {
  final root = await _projectDirectory();
  return Directory(
    '${root.path}${Platform.pathSeparator}${_storageName(id)}',
  );
}

Future<Uint8List?> loadLocalProjectManifest(String id) async {
  final directory = await _incrementalDirectory(id);
  final file = File('${directory.path}${Platform.pathSeparator}manifest.json');
  return _readJsonArtifact(file, 'bubble-caption-studio-manifest');
}

Future<Uint8List> loadLocalProjectImage(String id, String pageId) async {
  final directory = await _incrementalDirectory(id);
  return File(
    '${directory.path}${Platform.pathSeparator}images${Platform.pathSeparator}${_storageName(pageId)}.bin',
  ).readAsBytes();
}

Future<void> saveLocalProjectImage(
  String id,
  String pageId,
  Uint8List bytes,
) async {
  final directory = await _incrementalDirectory(id);
  final images = Directory(
    '${directory.path}${Platform.pathSeparator}images',
  );
  await images.create(recursive: true);
  await File(
    '${images.path}${Platform.pathSeparator}${_storageName(pageId)}.bin',
  ).writeAsBytes(bytes, flush: true);
}

Future<void> saveLocalProjectManifest(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final directory = await _incrementalDirectory(id);
  await directory.create(recursive: true);
  await _atomicWriteBytes(
      File(
        '${directory.path}${Platform.pathSeparator}manifest.json',
      ),
      bytes);
  final legacy = File(
    '${(await _projectDirectory()).path}${Platform.pathSeparator}$id.bcs.json',
  );
  if (await legacy.exists()) await legacy.delete();
  final projects = await listLocalProjects();
  final previous = projects.where((project) => project.id == id).firstOrNull;
  await _writeCatalog([
    LocalProjectSummary(
      id: id,
      name: name,
      updatedAt: DateTime.now().toUtc(),
      hasData: true,
      thumbnailBase64: thumbnailBase64 ?? previous?.thumbnailBase64,
    ),
    for (final project in projects)
      if (project.id != id) project,
  ]);
}

Future<Directory> _projectDirectory() async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory('${root.path}${Platform.pathSeparator}projects');
  await directory.create(recursive: true);
  return directory;
}

Future<File> _catalogFile() async => File(
      '${(await _projectDirectory()).path}${Platform.pathSeparator}catalog.json',
    );

Future<List<LocalProjectSummary>> listLocalProjects() async {
  final file = await _catalogFile();
  Object? decoded;
  for (final candidate in [file, File('${file.path}.bak')]) {
    try {
      if (await candidate.exists()) {
        decoded = jsonDecode(await candidate.readAsString());
        if (decoded is List) break;
      }
    } catch (_) {
      // Try the previous complete catalog generation.
    }
  }
  if (decoded is! List) return const [];
  final projects = [
    for (final item in decoded.whereType<Map<String, dynamic>>())
      LocalProjectSummary.fromJson(item),
  ];
  projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return projects;
}

Future<void> _writeCatalog(List<LocalProjectSummary> projects) async {
  final file = await _catalogFile();
  await _atomicWriteBytes(
    file,
    Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent(
          ' ',
        ).convert(projects.map((project) => project.toJson()).toList()),
      ),
    ),
  );
}

Future<void> _atomicWriteBytes(File file, Uint8List bytes) async {
  await file.parent.create(recursive: true);
  final temporary = File(
    '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  await temporary.writeAsBytes(bytes, flush: true);
  try {
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
      await file.delete();
    }
    await temporary.rename(file.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

Future<Uint8List?> _readJsonArtifact(File file, String expectedFormat) async {
  for (final candidate in [file, File('${file.path}.bak')]) {
    try {
      if (!await candidate.exists()) continue;
      final bytes = await candidate.readAsBytes();
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> &&
          decoded['format'] == expectedFormat) {
        return bytes;
      }
    } catch (_) {
      // Try the previous complete generation.
    }
  }
  return null;
}

Future<LocalProjectSummary> createLocalProject(String name) async {
  final now = DateTime.now().toUtc();
  final project = LocalProjectSummary(
    id: 'project-${now.microsecondsSinceEpoch}',
    name: name,
    updatedAt: now,
    hasData: false,
  );
  await _writeCatalog([project, ...await listLocalProjects()]);
  return project;
}

Future<Uint8List?> loadLocalProject(String id) async {
  final file = File(
    '${(await _projectDirectory()).path}${Platform.pathSeparator}$id.bcs.json',
  );
  return _readJsonArtifact(file, 'bubble-caption-studio');
}

Future<void> saveLocalProject(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final directory = await _projectDirectory();
  await _atomicWriteBytes(
      File(
        '${directory.path}${Platform.pathSeparator}$id.bcs.json',
      ),
      bytes);
  final now = DateTime.now().toUtc();
  final projects = await listLocalProjects();
  final updated = LocalProjectSummary(
    id: id,
    name: name,
    updatedAt: now,
    hasData: true,
    thumbnailBase64: thumbnailBase64 ??
        projects
            .where((project) => project.id == id)
            .firstOrNull
            ?.thumbnailBase64,
  );
  await _writeCatalog([
    updated,
    for (final project in projects)
      if (project.id != id) project,
  ]);
}

Future<Uint8List?> loadLocalProjectEdits(String id) async {
  final file = File(
    '${(await _projectDirectory()).path}${Platform.pathSeparator}$id.edits.json',
  );
  return _readJsonArtifact(file, 'bubble-caption-studio-edits');
}

Future<void> saveLocalProjectEdits(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final directory = await _projectDirectory();
  await _atomicWriteBytes(
      File(
        '${directory.path}${Platform.pathSeparator}$id.edits.json',
      ),
      bytes);
  final now = DateTime.now().toUtc();
  final projects = await listLocalProjects();
  final previous = projects.where((project) => project.id == id).firstOrNull;
  await _writeCatalog([
    LocalProjectSummary(
      id: id,
      name: name,
      updatedAt: now,
      hasData: true,
      thumbnailBase64: thumbnailBase64 ?? previous?.thumbnailBase64,
    ),
    for (final project in projects)
      if (project.id != id) project,
  ]);
}

Future<void> deleteLocalProject(String id) async {
  final file = File(
    '${(await _projectDirectory()).path}${Platform.pathSeparator}$id.bcs.json',
  );
  if (await file.exists()) await file.delete();
  final fileBackup = File('${file.path}.bak');
  if (await fileBackup.exists()) await fileBackup.delete();
  final edits = File(
    '${(await _projectDirectory()).path}${Platform.pathSeparator}$id.edits.json',
  );
  if (await edits.exists()) await edits.delete();
  final editsBackup = File('${edits.path}.bak');
  if (await editsBackup.exists()) await editsBackup.delete();
  final incremental = await _incrementalDirectory(id);
  if (await incremental.exists()) await incremental.delete(recursive: true);
  await _writeCatalog([
    for (final project in await listLocalProjects())
      if (project.id != id) project,
  ]);
}
