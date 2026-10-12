import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'project_store_io.dart'
    if (dart.library.js_interop) 'project_store_web.dart' as implementation;

class LocalProjectSummary {
  const LocalProjectSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.hasData,
    this.thumbnailBase64,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
  final bool hasData;
  final String? thumbnailBase64;

  factory LocalProjectSummary.fromJson(Map<String, dynamic> json) =>
      LocalProjectSummary(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名项目',
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        hasData: json['hasData'] == true,
        thumbnailBase64: json['thumbnailBase64']?.toString(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'hasData': hasData,
        if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
      };
}

class LocalProjectVersion {
  const LocalProjectVersion(
      {required this.id,
      required this.createdAt,
      required this.name,
      required this.kind,
      this.revision,
      this.isMigrationBackup = false});
  final String id;
  final DateTime createdAt;
  final String name;
  final String kind;
  final int? revision;

  /// A pre-upgrade snapshot retained independently from the rolling history.
  final bool isMigrationBackup;
  factory LocalProjectVersion.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final kind = value['kind'];
    if (id is! String ||
        !RegExp(r'^version-(?:\d+-)?[a-f0-9]{64}$').hasMatch(id) ||
        (kind != 'manifest' && kind != 'packed')) {
      throw const FormatException('保存历史包含无效标识或类型');
    }
    return LocalProjectVersion(
        id: value['id'] as String,
        createdAt: DateTime.parse(value['createdAt'] as String),
        name: value['name'] as String,
        kind: value['kind'] as String,
        revision: (value['revision'] as num?)?.toInt(),
        isMigrationBackup: value['isMigrationBackup'] == true);
  }
  Map<String, Object?> toJson() => {
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'name': name,
        'kind': kind,
        if (revision != null) 'revision': revision,
        if (isMigrationBackup) 'isMigrationBackup': true
      };
}

/// A timestamp-independent identity; an explicitly new revision is a new version.
String projectVersionIdForBytes(Uint8List bytes, {int? revision}) {
  Object? canonical(Object? value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.where((key) => key != 'savedAt').toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  final value = canonical(jsonDecode(utf8.decode(bytes)));
  final fingerprint = sha256.convert(utf8.encode(jsonEncode(value))).toString();
  return 'version-${revision == null ? '' : '$revision-'}$fingerprint';
}

Future<List<LocalProjectVersion>> listLocalProjectVersions(String id) =>
    implementation.listLocalProjectVersions(id);

Future<Uint8List?> loadLocalProjectVersion(String id, String versionId) =>
    implementation.loadLocalProjectVersion(id, versionId);

Future<List<LocalProjectSummary>> listLocalProjects() =>
    implementation.listLocalProjects();

Future<LocalProjectSummary> createLocalProject(String name) =>
    implementation.createLocalProject(name);

Future<Uint8List?> loadLocalProject(String id) =>
    implementation.loadLocalProject(id);

bool get supportsIncrementalProjectStorage =>
    implementation.supportsIncrementalProjectStorage;

Future<Uint8List?> loadLocalProjectManifest(String id) =>
    implementation.loadLocalProjectManifest(id);

Future<Uint8List> loadLocalProjectImage(String id, String pageId) =>
    implementation.loadLocalProjectImage(id, pageId);

Future<Uint8List> loadLocalProjectAsset(String id, String assetId) =>
    implementation.loadLocalProjectAsset(id, assetId);

Future<void> saveLocalProjectImage(
  String id,
  String pageId,
  Uint8List bytes,
) =>
    implementation.saveLocalProjectImage(id, pageId, bytes);

Future<void> saveLocalProjectAsset(
  String id,
  String assetId,
  Uint8List bytes,
) =>
    implementation.saveLocalProjectAsset(id, assetId, bytes);

Future<void> saveLocalProjectManifest(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
  int? revision,
}) =>
    implementation.saveLocalProjectManifest(
      id,
      name,
      bytes,
      thumbnailBase64: thumbnailBase64,
      revision: revision,
    );

Future<void> saveLocalProject(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
  int? revision,
}) =>
    implementation.saveLocalProject(
      id,
      name,
      bytes,
      thumbnailBase64: thumbnailBase64,
      revision: revision,
    );

Future<Uint8List?> loadLocalProjectEdits(String id) =>
    implementation.loadLocalProjectEdits(id);

Future<void> saveLocalProjectEdits(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) =>
    implementation.saveLocalProjectEdits(
      id,
      name,
      bytes,
      thumbnailBase64: thumbnailBase64,
    );

Future<void> deleteLocalProject(String id) =>
    implementation.deleteLocalProject(id);
