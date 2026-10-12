import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'project_store.dart'
    show LocalProjectSummary, LocalProjectVersion, projectVersionIdForBytes;

bool get supportsIncrementalProjectStorage => true;

String _storageName(String value) {
  if (value.isEmpty || value == '.' || value == '..') {
    throw ArgumentError.value(value, 'storage identifier');
  }
  return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}

void _validateProjectId(String id) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(id)) {
    throw ArgumentError.value(
        id, 'project id', 'Unsafe project storage identifier');
  }
}

Future<Directory> _incrementalDirectory(String id) async {
  _validateProjectId(id);
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

Future<Uint8List> loadLocalProjectAsset(String id, String assetId) async {
  final directory = await _incrementalDirectory(id);
  return File(
    '${directory.path}${Platform.pathSeparator}assets${Platform.pathSeparator}${_storageName(assetId)}.bin',
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
  await _writeAsset(
      File(
        '${images.path}${Platform.pathSeparator}${_storageName(pageId)}.bin',
      ),
      bytes);
}

Future<void> saveLocalProjectAsset(
  String id,
  String assetId,
  Uint8List bytes,
) async {
  final directory = await _incrementalDirectory(id);
  final assets = Directory(
    '${directory.path}${Platform.pathSeparator}assets',
  );
  await assets.create(recursive: true);
  await _writeAsset(
      File(
        '${assets.path}${Platform.pathSeparator}${_storageName(assetId)}.bin',
      ),
      bytes);
}

Future<void> saveLocalProjectManifest(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
  int? revision,
}) async {
  _validateJsonBytes(bytes, 'bubble-caption-studio-manifest');
  final directory = await _incrementalDirectory(id);
  await directory.create(recursive: true);
  await _preserveLegacyVersions(id, name, includeManifest: true);
  await _atomicWriteBytes(
      File(
        '${directory.path}${Platform.pathSeparator}manifest.json',
      ),
      bytes);
  // Retain the previous packed project as a recovery source after migration.
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
  await _recordVersion(id, name, bytes, 'manifest', revision);
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
  var foundCatalog = false;
  for (final candidate in [file, File('${file.path}.bak')]) {
    try {
      if (await candidate.exists()) {
        foundCatalog = true;
        decoded = jsonDecode(await candidate.readAsString());
        if (decoded is List) break;
      }
    } catch (_) {
      // Try the previous complete catalog generation.
    }
  }
  if (decoded is! List) {
    if (foundCatalog) throw const FormatException('项目目录和备份均损坏，未创建空目录覆盖原数据');
    return const [];
  }
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
    if (!_sameBytes(await temporary.readAsBytes(), bytes)) {
      throw FileSystemException('临时保存文件校验失败', temporary.path);
    }
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
    }
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      // Some Windows filesystems do not replace an existing target on rename.
      // Its complete backup already exists before the compatibility fallback.
      if (!await temporary.exists() || !await file.exists()) rethrow;
      await file.delete();
      await temporary.rename(file.path);
    }
    if (!_sameBytes(await file.readAsBytes(), bytes)) {
      throw FileSystemException('保存文件回读校验失败', file.path);
    }
  } catch (_) {
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.copy(file.path);
    }
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

Future<void> _writeAsset(File file, Uint8List bytes) async {
  if (await file.exists()) {
    if (_sameBytes(await file.readAsBytes(), bytes)) return;
    throw StateError('同一个图片标识对应不同数据，原图片未覆盖：${file.path}');
  }
  await _atomicWriteBytes(file, bytes);
}

void _validateJsonBytes(Uint8List bytes, String expectedFormat) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic> || decoded['format'] != expectedFormat) {
    throw FormatException('待保存项目数据格式无效：$expectedFormat');
  }
}

Future<Uint8List?> _readJsonArtifact(File file, String expectedFormat) async {
  var foundData = false;
  for (final candidate in [file, File('${file.path}.bak')]) {
    try {
      if (!await candidate.exists()) continue;
      foundData = true;
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
  if (foundData) throw FormatException('项目主数据及备份无法通过格式校验：${file.path}');
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
  _validateProjectId(id);
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
  int? revision,
}) async {
  _validateProjectId(id);
  _validateJsonBytes(bytes, 'bubble-caption-studio');
  final directory = await _projectDirectory();
  await _preserveLegacyVersions(id, name, includeManifest: false);
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
  await _recordVersion(id, name, bytes, 'packed', revision);
}

Future<List<LocalProjectVersion>> listLocalProjectVersions(String id) async {
  final recent = await _readVersionCatalog(id, permanent: false);
  final migration = await _readVersionCatalog(id, permanent: true);
  final migrationIds = migration.map((version) => version.id).toSet();
  return [
    ...recent.where((version) => !migrationIds.contains(version.id)),
    ...migration,
  ];
}

Future<Directory> _historyDirectory(String id,
    {required bool permanent}) async {
  final directory = await _incrementalDirectory(id);
  return Directory(
      '${directory.path}${Platform.pathSeparator}${permanent ? 'migration-history' : 'history'}');
}

Future<List<LocalProjectVersion>> _readVersionCatalog(String id,
    {required bool permanent}) async {
  final directory = await _historyDirectory(id, permanent: permanent);
  final file = File('${directory.path}${Platform.pathSeparator}catalog.json');
  final bytes = await _readJsonArtifact(file, 'bubble-caption-studio-history');
  if (bytes == null) return const [];
  final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final versions = root['versions'] as List;
  return [
    for (final item in versions)
      LocalProjectVersion.fromJson(item as Map<String, dynamic>)
  ];
}

Future<Uint8List?> loadLocalProjectVersion(String id, String versionId) async {
  _validateProjectId(id);
  if (!RegExp(r'^version-(?:\d+-)?[a-f0-9]{64}$').hasMatch(versionId)) {
    throw ArgumentError.value(versionId, 'versionId');
  }
  final versions = await listLocalProjectVersions(id);
  final version = versions.where((item) => item.id == versionId).firstOrNull;
  if (version == null) return null;
  final directory =
      await _historyDirectory(id, permanent: version.isMigrationBackup);
  return _readJsonArtifact(
      File('${directory.path}${Platform.pathSeparator}$versionId.json'),
      version.kind == 'manifest'
          ? 'bubble-caption-studio-manifest'
          : 'bubble-caption-studio');
}

Future<void> _recordVersion(
    String id, String name, Uint8List bytes, String kind, int? revision,
    {bool permanent = false}) async {
  final versionId = projectVersionIdForBytes(bytes, revision: revision);
  final versions = await _readVersionCatalog(id, permanent: permanent);
  final history = await _historyDirectory(id, permanent: permanent);
  final file = File('${history.path}${Platform.pathSeparator}$versionId.json');
  if (versions.any((version) => version.id == versionId)) {
    if (!permanent) return;
    if (!await file.exists() || !_sameBytes(await file.readAsBytes(), bytes)) {
      // A catalog entry alone is not proof that its recovery payload is durable.
      // Repair from the still-pristine source before permitting its replacement.
      await _atomicWriteBytes(file, bytes);
    }
    return;
  }
  await _atomicWriteBytes(file, bytes);
  final next = [
    LocalProjectVersion(
        id: versionId,
        name: name,
        kind: kind,
        createdAt: DateTime.now().toUtc(),
        revision: revision,
        isMigrationBackup: permanent),
    ...versions
  ];
  final kept = permanent ? next : next.take(20).toList();
  await _atomicWriteBytes(
      File('${history.path}${Platform.pathSeparator}catalog.json'),
      Uint8List.fromList(utf8.encode(jsonEncode({
        'format': 'bubble-caption-studio-history',
        'schemaVersion': 1,
        'versions': kept.map((version) => version.toJson()).toList()
      }))));
  // History entries are bounded. Referenced images/assets are intentionally not pruned.
  for (final obsolete in permanent ? <LocalProjectVersion>[] : next.skip(20)) {
    final expired =
        File('${history.path}${Platform.pathSeparator}${obsolete.id}.json');
    if (await expired.exists()) await expired.delete();
  }
}

bool _isLegacySchema(Uint8List bytes) {
  final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final schema = root['schemaVersion'];
  return schema == null || (schema is num && schema > 0 && schema < 3);
}

/// Runs before replacing the primary or its .bak generation. Migration snapshots
/// have their own directory/catalog and are never aged out by normal saves.
Future<void> _preserveLegacyVersions(String id, String name,
    {required bool includeManifest}) async {
  final root = await _projectDirectory();
  final preserved = await _readVersionCatalog(id, permanent: true);
  final packedAlreadyProtected =
      includeManifest && preserved.any((version) => version.kind == 'packed');
  final files = <(File, String, String)>[
    if (includeManifest)
      (
        File(
            '${(await _incrementalDirectory(id)).path}${Platform.pathSeparator}manifest.json'),
        'manifest',
        'bubble-caption-studio-manifest',
      ),
    // Manifest saves never replace packed source data. Do not reread potentially
    // very large embedded-image projects after their permanent backup exists.
    // Explicit packed writes still inspect the source before replacing it.
    if (!packedAlreadyProtected)
      (
        File('${root.path}${Platform.pathSeparator}$id.bcs.json'),
        'packed',
        'bubble-caption-studio',
      ),
  ];
  for (final entry in files) {
    for (final source in [entry.$1, File('${entry.$1.path}.bak')]) {
      if (!await source.exists()) continue;
      final bytes = await source.readAsBytes();
      try {
        _validateJsonBytes(bytes, entry.$3);
      } on FormatException {
        // Do not reinterpret a damaged generation as a valid migration backup.
        continue;
      }
      if (_isLegacySchema(bytes)) {
        await _recordVersion(id, name, bytes, entry.$2, null, permanent: true);
      }
    }
  }
}

Future<Uint8List?> loadLocalProjectEdits(String id) async {
  _validateProjectId(id);
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
  _validateProjectId(id);
  _validateJsonBytes(bytes, 'bubble-caption-studio-edits');
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
  _validateProjectId(id);
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
