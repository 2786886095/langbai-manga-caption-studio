import 'dart:typed_data';

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

Future<List<LocalProjectSummary>> listLocalProjects() =>
    implementation.listLocalProjects();

Future<LocalProjectSummary> createLocalProject(String name) =>
    implementation.createLocalProject(name);

Future<Uint8List?> loadLocalProject(String id) =>
    implementation.loadLocalProject(id);

Future<void> saveLocalProject(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) =>
    implementation.saveLocalProject(
      id,
      name,
      bytes,
      thumbnailBase64: thumbnailBase64,
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
