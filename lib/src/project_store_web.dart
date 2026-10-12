import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'project_store.dart'
    show LocalProjectSummary, LocalProjectVersion, projectVersionIdForBytes;

const _databaseName = 'langbai-caption-projects';
const _migrationKey = 'verified-local-storage-v1';
Future<JSObject>? _database;
Future<void>? _ready;

JSObject? get _desktopBridge => globalContext.has('desktopBridge')
    ? globalContext['desktopBridge'] as JSObject?
    : null;

bool get supportsIncrementalProjectStorage => true;

Future<JSAny?> _invokeBridgeAny(String method, [JSAny? argument]) async {
  final bridge = _desktopBridge;
  if (bridge == null) throw StateError('Desktop storage bridge is unavailable');
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
  return Uint8List.fromList((value as JSUint8Array).toDart);
}

String _binaryKey(String id, String kind, [String? assetId]) =>
    jsonEncode([id, kind, if (assetId != null) assetId]);

String? _legacyValue(String key) {
  final storage = globalContext['localStorage'] as JSObject;
  return (storage.callMethod<JSAny?>('getItem'.toJS, key.toJS) as JSString?)
      ?.toDart;
}

Object _storageError(JSObject source, String operation) {
  final error = source['error'] as JSObject?;
  final message =
      error == null ? null : (error['message'] as JSString?)?.toDart;
  return StateError('$operation: ${message ?? 'IndexedDB operation failed'}');
}

Future<JSObject> _openDatabase() {
  final cached = _database;
  if (cached != null) return cached;
  final completer = Completer<JSObject>();
  _database = completer.future;
  try {
    final factory = globalContext['indexedDB'] as JSObject?;
    if (factory == null) {
      throw StateError('This browser does not support IndexedDB');
    }
    final request = factory.callMethod<JSObject>(
      'open'.toJS,
      _databaseName.toJS,
      1.toJS,
    );
    request['onupgradeneeded'] = ((JSAny? event) {
      final db = request['result'] as JSObject;
      final names = db['objectStoreNames'] as JSObject;
      for (final name in ['projects', 'binary', 'meta']) {
        if (!names.callMethod<JSBoolean>('contains'.toJS, name.toJS).toDart) {
          db.callMethod<JSAny?>('createObjectStore'.toJS, name.toJS);
        }
      }
    }).toJS;
    request['onsuccess'] = ((JSAny? event) {
      final db = request['result'] as JSObject;
      db['onversionchange'] = ((JSAny? event) {
        db.callMethod<JSAny?>('close'.toJS);
        _database = null;
        _ready = null;
      }).toJS;
      if (!completer.isCompleted) completer.complete(db);
    }).toJS;
    request['onerror'] = ((JSAny? event) {
      _database = null;
      if (!completer.isCompleted) {
        completer
            .completeError(_storageError(request, 'Opening project storage'));
      }
    }).toJS;
    request['onblocked'] = ((JSAny? event) {
      _database = null;
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('Project storage upgrade is blocked by another tab'));
      }
    }).toJS;
  } catch (error, stack) {
    _database = null;
    completer.completeError(error, stack);
  }
  return completer.future;
}

Future<JSAny?> _request(JSObject request) {
  final completer = Completer<JSAny?>();
  request['onsuccess'] = ((JSAny? event) {
    if (!completer.isCompleted) completer.complete(request['result']);
  }).toJS;
  request['onerror'] = ((JSAny? event) {
    if (!completer.isCompleted) {
      completer
          .completeError(_storageError(request, 'Reading project storage'));
    }
  }).toJS;
  return completer.future;
}

Future<void> _transaction(JSObject transaction) {
  final completer = Completer<void>();
  transaction['oncomplete'] = ((JSAny? event) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  void fail(JSAny? event) {
    if (!completer.isCompleted) {
      completer.completeError(
          _storageError(transaction, 'Committing project storage'));
    }
  }

  transaction['onabort'] = fail.toJS;
  transaction['onerror'] = fail.toJS;
  return completer.future;
}

JSObject _store(JSObject transaction, String name) =>
    transaction.callMethod<JSObject>('objectStore'.toJS, name.toJS);

Future<JSAny?> _get(JSObject db, String store, String key) {
  final transaction =
      db.callMethod<JSObject>('transaction'.toJS, store.toJS, 'readonly'.toJS);
  return _request(
      _store(transaction, store).callMethod<JSObject>('get'.toJS, key.toJS));
}

Future<List<LocalProjectSummary>> _catalog(JSObject db) async {
  final transaction = db.callMethod<JSObject>(
      'transaction'.toJS, 'projects'.toJS, 'readonly'.toJS);
  final values = await _request(
      _store(transaction, 'projects').callMethod<JSObject>('getAll'.toJS));
  final records = (values as JSArray<JSString>).toDart;
  final projects = [
    for (final raw in records)
      LocalProjectSummary.fromJson(
          jsonDecode(raw.toDart) as Map<String, dynamic>),
  ];
  projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return projects;
}

void _validateJson(Uint8List bytes, String format) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic> || value['format'] != format) {
    throw FormatException('Invalid project storage payload: $format');
  }
}

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

Future<void> _ensureReady() {
  final cached = _ready;
  if (cached != null) return cached;
  final completer = Completer<void>();
  _ready = completer.future;
  () async {
    try {
      final db = await _openDatabase();
      if (await _get(db, 'meta', _migrationKey) != null) {
        completer.complete();
        return;
      }
      final catalog = jsonDecode(_legacyValue('bcs-project-catalog') ?? '[]');
      if (catalog is! List) {
        throw const FormatException('Legacy project catalog is damaged');
      }
      final migrated = <String, Uint8List>{};
      final summaries = <LocalProjectSummary>[];
      for (final item in catalog) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException(
              'Legacy project catalog contains an invalid entry');
        }
        final project = LocalProjectSummary.fromJson(item);
        if (project.id.isEmpty) {
          throw const FormatException('Legacy project has no identifier');
        }
        summaries.add(project);
        for (final pair in [
          ('packed', 'bcs-project-${project.id}', 'bubble-caption-studio'),
          (
            'edits',
            'bcs-project-edits-${project.id}',
            'bubble-caption-studio-edits'
          ),
        ]) {
          final raw = _legacyValue(pair.$2);
          if (raw == null) continue;
          final bytes = base64Decode(raw);
          _validateJson(bytes, pair.$3);
          migrated[_binaryKey(project.id, pair.$1)] = bytes;
        }
        if (project.hasData &&
            !migrated.containsKey(_binaryKey(project.id, 'packed'))) {
          throw FormatException(
              'Legacy project ${project.name} has no complete source data; original storage was preserved');
        }
      }
      final tx = db.callMethod<JSObject>(
          'transaction'.toJS,
          ['projects', 'binary'].map((s) => s.toJS).toList().toJS,
          'readwrite'.toJS);
      final committed = _transaction(tx);
      for (final project in summaries) {
        _store(tx, 'projects').callMethod<JSObject>(
            'put'.toJS, jsonEncode(project.toJson()).toJS, project.id.toJS);
      }
      for (final entry in migrated.entries) {
        _store(tx, 'binary').callMethod<JSObject>(
            'put'.toJS, Uint8List.fromList(entry.value).toJS, entry.key.toJS);
      }
      await committed;
      for (final entry in migrated.entries) {
        final restored = await _get(db, 'binary', entry.key);
        if (restored == null ||
            !_sameBytes(entry.value, (restored as JSUint8Array).toDart)) {
          throw StateError(
              'Legacy project migration failed byte verification; original storage was preserved');
        }
      }
      final projects = await _catalog(db);
      if (summaries.any((p) =>
          !projects.any((saved) => saved.id == p.id && saved.name == p.name))) {
        throw StateError(
            'Legacy project migration failed catalog verification');
      }
      final markerTx = db.callMethod<JSObject>(
          'transaction'.toJS, 'meta'.toJS, 'readwrite'.toJS);
      final marked = _transaction(markerTx);
      _store(markerTx, 'meta').callMethod<JSObject>('put'.toJS,
          'verified; legacy originals retained'.toJS, _migrationKey.toJS);
      await marked;
      // No localStorage setItem/removeItem: retained legacy data is recovery-only.
      completer.complete();
    } catch (error, stack) {
      _ready = null;
      completer.completeError(error, stack);
    }
  }();
  return completer.future;
}

Future<List<LocalProjectSummary>> listLocalProjects() async {
  if (_desktopBridge != null) {
    final decoded =
        jsonDecode(await _invokeBridge('listProjects') ?? '[]') as List;
    final projects = [
      for (final item in decoded.whereType<Map<String, dynamic>>())
        LocalProjectSummary.fromJson(item)
    ];
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }
  await _ensureReady();
  return _catalog(await _openDatabase());
}

Future<LocalProjectSummary> createLocalProject(String name) async {
  if (_desktopBridge != null) {
    final raw = await _invokeBridge('createProject', {'name': name}.jsify());
    if (raw == null) {
      throw StateError('Desktop project creation was not acknowledged');
    }
    return LocalProjectSummary.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }
  await _ensureReady();
  final now = DateTime.now().toUtc();
  final project = LocalProjectSummary(
      id: 'project-${now.microsecondsSinceEpoch}',
      name: name,
      updatedAt: now,
      hasData: false);
  final db = await _openDatabase();
  final tx = db.callMethod<JSObject>(
      'transaction'.toJS, 'projects'.toJS, 'readwrite'.toJS);
  final committed = _transaction(tx);
  _store(tx, 'projects').callMethod<JSObject>(
      'put'.toJS, jsonEncode(project.toJson()).toJS, project.id.toJS);
  await committed;
  return project;
}

Future<Uint8List?> _loadBinary(String id, String kind,
    [String? assetId]) async {
  await _ensureReady();
  final value = await _get(
      await _openDatabase(), 'binary', _binaryKey(id, kind, assetId));
  return value == null
      ? null
      : Uint8List.fromList((value as JSUint8Array).toDart);
}

Future<Uint8List?> loadLocalProject(String id) async => _desktopBridge != null
    ? _bridgeBytes(
        await _invokeBridgeAny('loadProjectData', {'id': id}.jsify()))
    : _loadBinary(id, 'packed');

Future<Uint8List?> loadLocalProjectManifest(String id) async =>
    _desktopBridge != null
        ? _bridgeBytes(
            await _invokeBridgeAny('loadProjectManifest', {'id': id}.jsify()))
        : _loadBinary(id, 'manifest');

Future<Uint8List> loadLocalProjectImage(String id, String pageId) async {
  final bytes = _desktopBridge != null
      ? _bridgeBytes(await _invokeBridgeAny(
          'loadProjectImage', {'id': id, 'pageId': pageId}.jsify()))
      : await _loadBinary(id, 'image', pageId);
  if (bytes == null) throw StateError('项目图片不存在：$pageId');
  return bytes;
}

Future<Uint8List> loadLocalProjectAsset(String id, String assetId) async {
  final bytes = _desktopBridge != null
      ? _bridgeBytes(await _invokeBridgeAny(
          'loadProjectAsset', {'id': id, 'assetId': assetId}.jsify()))
      : await _loadBinary(id, 'asset', assetId);
  if (bytes == null) throw StateError('项目图片元素不存在：$assetId');
  return bytes;
}

Future<void> _saveBinary(String id, String kind, Uint8List bytes,
    {String? assetId, String? name, String? thumbnailBase64}) async {
  await _ensureReady();
  final db = await _openDatabase();
  LocalProjectSummary? previous;
  if (name != null) {
    final raw = await _get(db, 'projects', id);
    if (raw != null) {
      previous = LocalProjectSummary.fromJson(
          jsonDecode((raw as JSString).toDart) as Map<String, dynamic>);
    }
  }
  final stores = name == null ? ['binary'] : ['binary', 'projects'];
  final tx = db.callMethod<JSObject>('transaction'.toJS,
      stores.map((s) => s.toJS).toList().toJS, 'readwrite'.toJS);
  final committed = _transaction(tx);
  if (name == null && (kind == 'image' || kind == 'asset')) {
    Object? mismatch;
    final store = _store(tx, 'binary');
    final key = _binaryKey(id, kind, assetId).toJS;
    final request = store.callMethod<JSObject>('get'.toJS, key);
    request['onsuccess'] = ((JSAny? event) {
      try {
        final existing = request['result'];
        if (existing != null &&
            !_sameBytes((existing as JSUint8Array).toDart, bytes)) {
          mismatch = StateError('同一个图片标识对应不同数据，原图片未覆盖');
          tx.callMethod<JSAny?>('abort'.toJS);
        } else if (existing == null) {
          store.callMethod<JSObject>(
              'put'.toJS, Uint8List.fromList(bytes).toJS, key);
        }
      } catch (error) {
        mismatch = error;
        tx.callMethod<JSAny?>('abort'.toJS);
      }
    }).toJS;
    try {
      await committed;
    } catch (_) {
      if (mismatch != null) throw mismatch!;
      rethrow;
    }
    return;
  }
  _store(tx, 'binary').callMethod<JSObject>('put'.toJS,
      Uint8List.fromList(bytes).toJS, _binaryKey(id, kind, assetId).toJS);
  if (name != null) {
    final summary = LocalProjectSummary(
        id: id,
        name: name,
        updatedAt: DateTime.now().toUtc(),
        hasData: true,
        thumbnailBase64: thumbnailBase64 ?? previous?.thumbnailBase64);
    _store(tx, 'projects').callMethod<JSObject>(
        'put'.toJS, jsonEncode(summary.toJson()).toJS, id.toJS);
  }
  await committed;
}

Future<void> saveLocalProjectImage(
    String id, String pageId, Uint8List bytes) async {
  if (_desktopBridge != null) {
    await _invokeBridgeAny(
        'saveProjectImage',
        {'id': id, 'pageId': pageId, 'bytes': Uint8List.fromList(bytes).toJS}
            .jsify());
  } else {
    await _saveBinary(id, 'image', bytes, assetId: pageId);
  }
}

Future<void> saveLocalProjectAsset(
    String id, String assetId, Uint8List bytes) async {
  if (_desktopBridge != null) {
    await _invokeBridgeAny(
        'saveProjectAsset',
        {'id': id, 'assetId': assetId, 'bytes': Uint8List.fromList(bytes).toJS}
            .jsify());
  } else {
    await _saveBinary(id, 'asset', bytes, assetId: assetId);
  }
}

Future<void> _saveJson(String id, String name, Uint8List bytes, String kind,
    String format, String bridgeMethod, String? thumbnail,
    [int? revision]) async {
  _validateJson(bytes, format);
  if (kind == 'manifest' || kind == 'packed') {
    await _preserveLegacyVersions(id, name, kind);
  }
  if (_desktopBridge != null) {
    await _invokeBridgeAny(
        bridgeMethod,
        {
          'id': id,
          'name': name,
          'bytes': Uint8List.fromList(bytes).toJS,
          if (thumbnail != null) 'thumbnailBase64': thumbnail
        }.jsify());
  } else {
    await _saveBinary(id, kind, bytes, name: name, thumbnailBase64: thumbnail);
  }
  if (kind == 'manifest' || kind == 'packed') {
    if (_desktopBridge != null) {
      await _recordBridgeVersion(id, name, bytes, kind, revision);
    } else {
      await _recordBrowserVersion(id, name, bytes, kind, revision);
    }
  }
}

Future<void> saveLocalProjectManifest(String id, String name, Uint8List bytes,
        {String? thumbnailBase64, int? revision}) =>
    _saveJson(id, name, bytes, 'manifest', 'bubble-caption-studio-manifest',
        'saveProjectManifest', thumbnailBase64, revision);

Future<void> saveLocalProject(String id, String name, Uint8List bytes,
        {String? thumbnailBase64, int? revision}) =>
    _saveJson(id, name, bytes, 'packed', 'bubble-caption-studio',
        'saveProjectData', thumbnailBase64, revision);

Future<Uint8List?> loadLocalProjectEdits(String id) async =>
    _desktopBridge != null
        ? _bridgeBytes(
            await _invokeBridgeAny('loadProjectEdits', {'id': id}.jsify()))
        : _loadBinary(id, 'edits');

Future<void> saveLocalProjectEdits(String id, String name, Uint8List bytes,
        {String? thumbnailBase64}) =>
    _saveJson(id, name, bytes, 'edits', 'bubble-caption-studio-edits',
        'saveProjectEdits', thumbnailBase64);

Future<void> deleteLocalProject(String id) async {
  if (_desktopBridge != null) {
    await _invokeBridgeAny('deleteProject', {'id': id}.jsify());
    return;
  }
  await _ensureReady();
  final db = await _openDatabase();
  final readTx = db.callMethod<JSObject>(
      'transaction'.toJS, 'binary'.toJS, 'readonly'.toJS);
  final rawKeys = await _request(
      _store(readTx, 'binary').callMethod<JSObject>('getAllKeys'.toJS));
  final keys = (rawKeys as JSArray<JSString>).toDart.where((key) {
    final decoded = jsonDecode(key.toDart) as List;
    return decoded.first == id;
  }).toList();
  final tx = db.callMethod<JSObject>('transaction'.toJS,
      ['projects'.toJS, 'binary'.toJS, 'meta'.toJS].toJS, 'readwrite'.toJS);
  final committed = _transaction(tx);
  _store(tx, 'projects').callMethod<JSObject>('delete'.toJS, id.toJS);
  _store(tx, 'meta').callMethod<JSObject>('delete'.toJS, 'history:$id'.toJS);
  _store(tx, 'meta')
      .callMethod<JSObject>('delete'.toJS, 'migration-history:$id'.toJS);
  for (final key in keys) {
    _store(tx, 'binary').callMethod<JSObject>('delete'.toJS, key);
  }
  await committed;
  // The verified migration marker prevents retained legacy copies resurrecting.
}

List<LocalProjectVersion> _decodeHistory(Uint8List? bytes) {
  if (bytes == null) return const [];
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic> ||
      value['format'] != 'bubble-caption-studio-history' ||
      value['versions'] is! List) {
    throw const FormatException('保存历史目录无法通过格式校验');
  }
  return [
    for (final item in value['versions'] as List)
      LocalProjectVersion.fromJson(item as Map<String, dynamic>)
  ];
}

Uint8List _encodeHistory(List<LocalProjectVersion> versions) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'bubble-caption-studio-history',
      'schemaVersion': 1,
      'versions': versions.map((v) => v.toJson()).toList()
    })));

Future<Uint8List?> _optionalBridgeAsset(String id, String assetId) async {
  try {
    return _bridgeBytes(await _invokeBridgeAny(
        'loadProjectAsset', {'id': id, 'assetId': assetId}.jsify()));
  } catch (error) {
    String message;
    try {
      message = ((error as JSObject)['message'] as JSString?)?.toDart ??
          error.toString();
    } catch (_) {
      message = error.toString();
    }
    if (message.contains('ENOENT')) return null;
    rethrow;
  }
}

Future<List<LocalProjectVersion>> _bridgeHistory(String id,
    {bool permanent = false}) async {
  Object? failed;
  final prefix = permanent ? 'migration-history' : 'history';
  for (final asset in ['$prefix-catalog', '$prefix-catalog-backup']) {
    try {
      final bytes = await _optionalBridgeAsset(id, asset);
      if (bytes != null) return _decodeHistory(bytes);
    } catch (error) {
      failed = error;
    }
  }
  if (failed != null) throw failed;
  return const [];
}

Future<List<LocalProjectVersion>> listLocalProjectVersions(String id) async {
  final recent = _desktopBridge != null
      ? await _bridgeHistory(id)
      : await _browserHistory(id);
  final migration = _desktopBridge != null
      ? await _bridgeHistory(id, permanent: true)
      : await _browserHistory(id, permanent: true);
  final migrationIds = migration.map((version) => version.id).toSet();
  return [
    ...recent.where((version) => !migrationIds.contains(version.id)),
    ...migration,
  ];
}

Future<List<LocalProjectVersion>> _browserHistory(String id,
    {bool permanent = false}) async {
  await _ensureReady();
  final key = '${permanent ? 'migration-history' : 'history'}:$id';
  final raw = await _get(await _openDatabase(), 'meta', key);
  return raw == null
      ? const []
      : _decodeHistory(
          Uint8List.fromList(utf8.encode((raw as JSString).toDart)));
}

Future<Uint8List?> loadLocalProjectVersion(String id, String versionId) async {
  if (!RegExp(r'^version-(?:\d+-)?[a-f0-9]{64}$').hasMatch(versionId)) {
    throw ArgumentError.value(versionId, 'versionId');
  }
  final versions = await listLocalProjectVersions(id);
  final version = versions.where((v) => v.id == versionId).firstOrNull;
  if (version == null) return null;
  final prefix = version.isMigrationBackup ? 'migration-history' : 'history';
  final bytes = _desktopBridge != null
      ? await _optionalBridgeAsset(id, '$prefix-$versionId')
      : await _loadBinary(
          id,
          version.isMigrationBackup ? 'migration-version' : 'version',
          versionId);
  if (bytes != null) {
    _validateJson(
        bytes,
        version.kind == 'manifest'
            ? 'bubble-caption-studio-manifest'
            : 'bubble-caption-studio');
  }
  return bytes;
}

Future<void> _recordBrowserVersion(
    String id, String name, Uint8List bytes, String kind, int? revision,
    {bool permanent = false}) async {
  final versionId = projectVersionIdForBytes(bytes, revision: revision);
  var previous = await _browserHistory(id, permanent: permanent);
  if (previous.any((version) => version.id == versionId)) {
    if (!permanent) return;
    final recovered = await _loadBinary(id, 'migration-version', versionId);
    if (recovered != null && _sameBytes(recovered, bytes)) return;
    previous = previous.where((version) => version.id != versionId).toList();
  }
  final next = [
    LocalProjectVersion(
        id: versionId,
        createdAt: DateTime.now().toUtc(),
        name: name,
        kind: kind,
        revision: revision,
        isMigrationBackup: permanent),
    ...previous
  ];
  final kept = permanent ? next : next.take(20).toList();
  final db = await _openDatabase();
  final tx = db.callMethod<JSObject>(
      'transaction'.toJS, ['binary'.toJS, 'meta'.toJS].toJS, 'readwrite'.toJS);
  final committed = _transaction(tx);
  final payloadKind = permanent ? 'migration-version' : 'version';
  _store(tx, 'binary').callMethod<JSObject>(
      'put'.toJS,
      Uint8List.fromList(bytes).toJS,
      _binaryKey(id, payloadKind, versionId).toJS);
  _store(tx, 'meta').callMethod<JSObject>(
      'put'.toJS,
      utf8.decode(_encodeHistory(kept)).toJS,
      '${permanent ? 'migration-history' : 'history'}:$id'.toJS);
  for (final expired in permanent ? <LocalProjectVersion>[] : next.skip(20)) {
    _store(tx, 'binary').callMethod<JSObject>(
        'delete'.toJS, _binaryKey(id, 'version', expired.id).toJS);
  }
  await committed;
  if (permanent) {
    final restored =
        await _get(db, 'binary', _binaryKey(id, payloadKind, versionId));
    final verified = await _browserHistory(id, permanent: true);
    if (restored == null ||
        !_sameBytes(bytes, (restored as JSUint8Array).toDart) ||
        !verified.any((version) =>
            version.id == versionId && version.isMigrationBackup)) {
      throw StateError('升级前永久备份回读校验失败，原项目未覆盖');
    }
  }
}

Future<void> _recordBridgeVersion(
    String id, String name, Uint8List bytes, String kind, int? revision,
    {bool permanent = false}) async {
  final versionId = projectVersionIdForBytes(bytes, revision: revision);
  var previous = await _bridgeHistory(id, permanent: permanent);
  final prefix = permanent ? 'migration-history' : 'history';
  final versionAsset = '$prefix-$versionId';
  if (previous.any((version) => version.id == versionId)) {
    if (!permanent) return;
    final recovered = await _optionalBridgeAsset(id, versionAsset);
    if (recovered != null && _sameBytes(recovered, bytes)) return;
    previous = previous.where((version) => version.id != versionId).toList();
  }
  await _invokeBridgeAny(
      'saveProjectAsset',
      {
        'id': id,
        'assetId': versionAsset,
        'bytes': Uint8List.fromList(bytes).toJS
      }.jsify());
  final restored = await _optionalBridgeAsset(id, versionAsset);
  if (restored == null || !_sameBytes(restored, bytes)) {
    throw StateError('保存历史正文回读校验失败');
  }
  if (previous.isNotEmpty) {
    await _invokeBridgeAny(
        'saveProjectAsset',
        {
          'id': id,
          'assetId': '$prefix-catalog-backup',
          'bytes': Uint8List.fromList(_encodeHistory(previous)).toJS
        }.jsify());
  }
  final next = [
    LocalProjectVersion(
        id: versionId,
        createdAt: DateTime.now().toUtc(),
        name: name,
        kind: kind,
        revision: revision,
        isMigrationBackup: permanent),
    ...previous
  ];
  final catalog = _encodeHistory(permanent ? next : next.take(20).toList());
  await _invokeBridgeAny(
      'saveProjectAsset',
      {
        'id': id,
        'assetId': '$prefix-catalog',
        'bytes': Uint8List.fromList(catalog).toJS
      }.jsify());
  final verified = await _optionalBridgeAsset(id, '$prefix-catalog');
  if (verified == null || !_sameBytes(verified, catalog)) {
    throw StateError('保存历史目录回读校验失败');
  }
  // Old bridge APIs cannot enumerate/delete individual assets. Only the 20-entry
  // history catalog is bounded; we never delete unknown source or image assets.
}

bool _isLegacySchema(Uint8List bytes) {
  final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final schema = root['schemaVersion'];
  return schema == null || (schema is num && schema > 0 && schema < 3);
}

Future<void> _preserveLegacyVersions(
    String id, String name, String kind) async {
  final protected = _desktopBridge != null
      ? await _bridgeHistory(id, permanent: true)
      : await _browserHistory(id, permanent: true);
  final packedAlreadyProtected = kind == 'manifest' &&
      protected.any((version) => version.kind == 'packed');
  final sources = <(Uint8List?, String, String)>[
    if (kind == 'manifest')
      (
        await loadLocalProjectManifest(id),
        'manifest',
        'bubble-caption-studio-manifest'
      ),
    // Manifest saves do not overwrite packed originals. Avoid loading embedded
    // images repeatedly after their independent permanent snapshot was committed.
    if (!packedAlreadyProtected)
      (await loadLocalProject(id), 'packed', 'bubble-caption-studio'),
  ];
  for (final source in sources) {
    final bytes = source.$1;
    if (bytes == null) continue;
    _validateJson(bytes, source.$3);
    if (!_isLegacySchema(bytes)) continue;
    if (_desktopBridge != null) {
      await _recordBridgeVersion(id, name, bytes, source.$2, null,
          permanent: true);
    } else {
      await _recordBrowserVersion(id, name, bytes, source.$2, null,
          permanent: true);
    }
  }
}
