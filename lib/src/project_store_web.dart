import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'project_store.dart' show LocalProjectSummary;

JSObject? get _desktopBridge => globalContext.has('desktopBridge')
    ? globalContext['desktopBridge'] as JSObject?
    : null;

JSObject get _storage => globalContext['localStorage'] as JSObject;

bool get supportsIncrementalProjectStorage => _desktopBridge != null;

Future<JSAny?> _invokeBridgeAny(String method, [JSAny? argument]) async {
  final bridge = _desktopBridge;
  if (bridge == null) return null;
  final promise = argument == null
      ? bridge.callMethod<JSPromise<JSAny?>>(method.toJS)
      : bridge.callMethod<JSPromise<JSAny?>>(method.toJS, argument);
  return promise.toDart;
}

Future<String?> _invokeBridge(String method, [JSAny? argument]) async =>
    (await _invokeBridgeAny(method, argument) as JSString?)?.toDart;

Uint8List? _bridgeBytes(JSAny? value) {
  if (value == null) return null;
  if (value.typeofEquals('string')) {
    return base64Decode((value as JSString).toDart);
  }
  return (value as JSUint8Array).toDart;
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
  if (_desktopBridge != null) {
    return _bridgeBytes(
      await _invokeBridgeAny('loadProjectData', {'id': id}.jsify()),
    );
  }
  final raw = _get('bcs-project-$id');
  return raw == null ? null : base64Decode(raw);
}

Future<Uint8List?> loadLocalProjectManifest(String id) => _loadBridgeBytes(
      'loadProjectManifest',
      {'id': id}.jsify(),
    );

Future<Uint8List> loadLocalProjectImage(String id, String pageId) async {
  final bytes = await _loadBridgeBytes(
    'loadProjectImage',
    {'id': id, 'pageId': pageId}.jsify(),
  );
  if (bytes == null) throw StateError('项目图片不存在：$pageId');
  return bytes;
}

Future<Uint8List?> _loadBridgeBytes(String method, JSAny? request) async =>
    _bridgeBytes(await _invokeBridgeAny(method, request));

Future<void> saveLocalProjectImage(
  String id,
  String pageId,
  Uint8List bytes,
) async {
  await _invokeBridge(
    'saveProjectImage',
    {'id': id, 'pageId': pageId, 'bytes': bytes.toJS}.jsify(),
  );
}

Future<void> saveLocalProjectManifest(
  String id,
  String name,
  Uint8List bytes, {
  String? thumbnailBase64,
}) async {
  await _invokeBridge(
    'saveProjectManifest',
    {
      'id': id,
      'name': name,
      'bytes': bytes.toJS,
      if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
    }.jsify(),
  );
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
    'bytes': bytes.toJS,
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
  if (_desktopBridge != null) {
    return _bridgeBytes(
      await _invokeBridgeAny('loadProjectEdits', {'id': id}.jsify()),
    );
  }
  final raw = _get('bcs-project-edits-$id');
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
    'bytes': bytes.toJS,
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
