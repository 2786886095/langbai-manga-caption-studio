import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'project_store.dart' show LocalProjectSummary;

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
  if (!await file.exists()) return const [];
  final decoded = jsonDecode(await file.readAsString());
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
  await file.writeAsString(
    const JsonEncoder.withIndent(
      ' ',
    ).convert(projects.map((project) => project.toJson()).toList()),
    flush: true,
  );
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
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> saveLocalProject(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final directory = await _projectDirectory();
  await File(
    '${directory.path}${Platform.pathSeparator}$id.bcs.json',
  ).writeAsBytes(bytes, flush: true);
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
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> saveLocalProjectEdits(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final directory = await _projectDirectory();
  await File(
    '${directory.path}${Platform.pathSeparator}$id.edits.json',
  ).writeAsBytes(bytes, flush: true);
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
  final edits = File(
    '${(await _projectDirectory()).path}${Platform.pathSeparator}$id.edits.json',
  );
  if (await edits.exists()) await edits.delete();
  await _writeCatalog([
    for (final project in await listLocalProjects())
      if (project.id != id) project,
  ]);
}
