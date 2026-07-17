import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'project_store.dart' show LocalProjectSummary;

JSObject? get _desktopBridge => globalContext.has('desktopBridge')
    ? globalContext['desktopBridge'] as JSObject?
    : null;

JSObject get _storage => globalContext['localStorage'] as JSObject;

Future<String?> _invokeBridge(String method, [JSAny? argument]) async {
  final bridge = _desktopBridge;
  if (bridge == null) return null;
  final promise = argument == null
      ? bridge.callMethod<JSPromise<JSAny?>>(method.toJS)
      : bridge.callMethod<JSPromise<JSAny?>>(method.toJS, argument);
  final value = await promise.toDart;
  return (value as JSString?)?.toDart;
}

String? _get(String key) =>
    (_storage.callMethod<JSAny?>('getItem'.toJS, key.toJS) as JSString?)
        ?.toDart;

void _set(String key, String value) =>
    _storage.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);

void _remove(String key) =>
    _storage.callMethod<JSAny?>('removeItem'.toJS, key.toJS);

Future<List<LocalProjectSummary>> listLocalProjects() async {
  final raw = await _invokeBridge('listProjects') ??
      _get('bcs-project-catalog') ??
      '[]';
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final projects = [
    for (final item in decoded.whereType<Map<String, dynamic>>())
      LocalProjectSummary.fromJson(item),
  ];
  projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return projects;
}

Future<LocalProjectSummary> createLocalProject(String name) async {
  final raw = await _invokeBridge('createProject', {'name': name}.jsify());
  if (raw != null) {
    return LocalProjectSummary.fromJson(jsonDecode(raw));
  }
  final now = DateTime.now().toUtc();
  final project = LocalProjectSummary(
    id: 'project-${now.microsecondsSinceEpoch}',
    name: name,
    updatedAt: now,
    hasData: false,
  );
  _set(
    'bcs-project-catalog',
    jsonEncode([
      project.toJson(),
      ...(await listLocalProjects()).map((p) => p.toJson()),
    ]),
  );
  return project;
}

Future<Uint8List?> loadLocalProject(String id) async {
  final raw = await _invokeBridge('loadProjectData', {'id': id}.jsify()) ??
      _get('bcs-project-$id');
  return raw == null ? null : base64Decode(raw);
}

Future<void> saveLocalProject(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final request = {
    'id': id,
    'name': name,
    'base64': base64Encode(bytes),
    if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
  }.jsify();
  if (_desktopBridge != null) {
    await _invokeBridge('saveProjectData', request);
    return;
  }
  _set('bcs-project-$id', base64Encode(bytes));
  final updated = LocalProjectSummary(
    id: id,
    name: name,
    updatedAt: DateTime.now().toUtc(),
    hasData: true,
    thumbnailBase64: thumbnailBase64,
  );
  _set(
    'bcs-project-catalog',
    jsonEncode([
      updated.toJson(),
      for (final project in await listLocalProjects())
        if (project.id != id) project.toJson(),
    ]),
  );
}

Future<Uint8List?> loadLocalProjectEdits(String id) async {
  final raw = await _invokeBridge('loadProjectEdits', {'id': id}.jsify()) ??
      _get('bcs-project-edits-$id');
  return raw == null ? null : base64Decode(raw);
}

Future<void> saveLocalProjectEdits(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  final request = {
    'id': id,
    'name': name,
    'base64': base64Encode(bytes),
    if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
  }.jsify();
  if (_desktopBridge != null) {
    await _invokeBridge('saveProjectEdits', request);
    return;
  }
  _set('bcs-project-edits-$id', base64Encode(bytes));
  final projects = await listLocalProjects();
  final previous = projects.where((project) => project.id == id).firstOrNull;
  final updated = LocalProjectSummary(
    id: id,
    name: name,
    updatedAt: DateTime.now().toUtc(),
    hasData: true,
    thumbnailBase64: thumbnailBase64 ?? previous?.thumbnailBase64,
  );
  _set(
    'bcs-project-catalog',
    jsonEncode([
      updated.toJson(),
      for (final project in projects)
        if (project.id != id) project.toJson(),
    ]),
  );
}

Future<void> deleteLocalProject(String id) async {
  if (_desktopBridge != null) {
    await _invokeBridge('deleteProject', {'id': id}.jsify());
    return;
  }
  _remove('bcs-project-$id');
  _remove('bcs-project-edits-$id');
  _set(
    'bcs-project-catalog',
    jsonEncode([
      for (final project in await listLocalProjects())
        if (project.id != id) project.toJson(),
    ]),
  );
}
