import 'dart:convert';
import 'dart:io';

import 'package:bubble_caption_studio/src/project_store_io.dart' as storage;
import 'package:bubble_caption_studio/src/revision_save_queue.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _manifest(String text, {int schemaVersion = 3}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'bubble-caption-studio-manifest',
      'schemaVersion': schemaVersion,
      'pages': [],
      'script': text,
    })));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bcs-storage-fixture-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => temporary.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (temporary.path.startsWith(Directory.systemTemp.path) &&
        temporary.path.contains('bcs-storage-fixture-')) {
      await temporary.delete(recursive: true);
    }
  });

  test('native storage validates before overwrite and recovers backup bytes',
      () async {
    const id = 'project-native-fixture';
    final first = _manifest('完整正文：第一版');
    final second = _manifest('完整正文：第二版');
    await storage.saveLocalProjectManifest(id, 'Fixture', first);
    await storage.saveLocalProjectManifest(id, 'Fixture', second);
    expect(await storage.loadLocalProjectManifest(id), second);
    await expectLater(
        storage.saveLocalProjectManifest(
            id, 'Fixture', Uint8List.fromList([0, 1])),
        throwsFormatException);
    expect(await storage.loadLocalProjectManifest(id), second);
    final file = File(
        '${temporary.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id${Platform.pathSeparator}manifest.json');
    await file.writeAsString('damaged primary');
    expect(await storage.loadLocalProjectManifest(id), first);
    await File('${file.path}.bak').writeAsString('damaged backup');
    await expectLater(
        storage.loadLocalProjectManifest(id), throwsFormatException);
    expect(await file.readAsString(), 'damaged primary');
  });

  test('native assets cannot silently overwrite a different image with same id',
      () async {
    const id = 'project-native-assets';
    final bytes = Uint8List.fromList([1, 2, 3, 255]).asUnmodifiableView();
    await storage.saveLocalProjectImage(id, 'page-fixture', bytes);
    await storage.saveLocalProjectImage(id, 'page-fixture', bytes);
    await expectLater(
        storage.saveLocalProjectImage(
            id, 'page-fixture', Uint8List.fromList([9])),
        throwsStateError);
    expect(await storage.loadLocalProjectImage(id, 'page-fixture'), bytes);
    await storage.saveLocalProjectAsset(id, 'asset-fixture', bytes);
    expect(await storage.loadLocalProjectAsset(id, 'asset-fixture'), bytes);
  });

  test('unsafe project ids cannot escape the project storage directory',
      () async {
    for (final id in ['..', '../outside', r'..\outside', '']) {
      await expectLater(storage.loadLocalProject(id), throwsArgumentError);
      await expectLater(
          storage.saveLocalProjectManifest(id, 'Fixture', _manifest('safe')),
          throwsArgumentError);
      await expectLater(storage.deleteLocalProject(id), throwsArgumentError);
    }
  });

  test(
      'native history survives new reads, deduplicates and keeps latest twenty',
      () async {
    const id = 'project-native-history';
    final image = Uint8List.fromList([1, 2, 3]);
    await storage.saveLocalProjectImage(id, 'immutable-page', image);
    final first = _manifest('版本0：完整正文');
    await storage.saveLocalProjectManifest(id, 'Fixture', first, revision: 0);
    final firstVersion = (await storage.listLocalProjectVersions(id)).single;
    expect(firstVersion.kind, 'manifest');
    expect(firstVersion.revision, 0);
    expect(await storage.loadLocalProjectVersion(id, firstVersion.id), first);
    await storage.saveLocalProjectManifest(id, 'Fixture', first, revision: 0);
    expect(await storage.listLocalProjectVersions(id), hasLength(1));
    for (var revision = 1; revision < 23; revision++) {
      await storage.saveLocalProjectManifest(
          id, 'Fixture', _manifest('版本$revision：完整正文'),
          revision: revision);
    }
    final versions = await storage.listLocalProjectVersions(id);
    expect(versions, hasLength(20));
    expect(versions.first.revision, 22);
    expect(versions.last.revision, 3);
    expect(await storage.loadLocalProjectVersion(id, versions.first.id),
        _manifest('版本22：完整正文'));
    expect(await storage.loadLocalProjectImage(id, 'immutable-page'), image);
    final history = File(
        '${temporary.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id${Platform.pathSeparator}history${Platform.pathSeparator}catalog.json');
    await history.writeAsString('broken catalog');
    expect(await storage.listLocalProjectVersions(id), hasLength(20));
    await File('${history.path}.bak').writeAsString('broken backup');
    await expectLater(
        storage.listLocalProjectVersions(id), throwsFormatException);
  });

  test(
      'history write failures reject save acknowledgement and keep queue dirty',
      () async {
    const id = 'project-native-history-failure';
    final blocked = Directory(
        '${temporary.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id${Platform.pathSeparator}history${Platform.pathSeparator}catalog.json');
    await blocked.create(recursive: true);
    final queue = RevisionSaveQueue();
    await expectLater(
        queue.enqueue(
            1,
            () => storage.saveLocalProjectManifest(
                id, 'Fixture', _manifest('未确认保存'),
                revision: 1)),
        throwsA(isA<FileSystemException>()));
    expect(queue.isDirty, isTrue);
    expect(queue.persistedRevision, -1);
    expect(queue.lastError, isA<FileSystemException>());
  });

  test('schema2 migration snapshot remains selectable beyond rolling history',
      () async {
    const id = 'project-native-migration';
    final legacy = _manifest('升级前完整正文：不可丢失', schemaVersion: 2);
    final source = File(
        '${temporary.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id${Platform.pathSeparator}manifest.json');
    await source.parent.create(recursive: true);
    await source.writeAsBytes(legacy);
    final packed = Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'bubble-caption-studio',
      'schemaVersion': 2,
      'pages': [],
      'script': '旧 packed 原文',
    })));
    final packedFile = File(
        '${temporary.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id.bcs.json');
    await packedFile.writeAsBytes(packed);
    for (var revision = 1; revision <= 23; revision++) {
      await storage.saveLocalProjectManifest(
          id, '升级测试', _manifest('升级后版本 $revision'),
          revision: revision);
    }
    final versions = await storage.listLocalProjectVersions(id);
    final migration = versions.where((v) => v.isMigrationBackup).toList();
    expect(versions.where((v) => !v.isMigrationBackup), hasLength(20));
    expect(migration, hasLength(2));
    final manifestBackup = migration.singleWhere((v) => v.kind == 'manifest');
    expect(
        await storage.loadLocalProjectVersion(id, manifestBackup.id), legacy);
    final packedBackup = migration.singleWhere((v) => v.kind == 'packed');
    expect(await storage.loadLocalProjectVersion(id, packedBackup.id), packed);
    expect(await packedFile.readAsBytes(), packed);
    expect(await storage.loadLocalProjectManifest(id), _manifest('升级后版本 23'));
    // The rolling .bak now contains a new schema3 generation, not the old source.
    expect(
        await File('${source.path}.bak').readAsBytes(), _manifest('升级后版本 22'));
  });

  test('permanent migration history failure prevents replacing old manifest',
      () async {
    const id = 'project-native-migration-failure';
    final legacy = _manifest('备份失败必须保留这份正文', schemaVersion: 2);
    final source = File(
        '${temporary.path}${Platform.pathSeparator}projects${Platform.pathSeparator}$id${Platform.pathSeparator}manifest.json');
    await source.parent.create(recursive: true);
    await source.writeAsBytes(legacy);
    final blocked = Directory(
        '${source.parent.path}${Platform.pathSeparator}migration-history${Platform.pathSeparator}catalog.json');
    await blocked.create(recursive: true);
    await expectLater(
        storage.saveLocalProjectManifest(id, '升级失败', _manifest('不能覆盖')),
        throwsA(isA<FileSystemException>()));
    expect(await source.readAsBytes(), legacy);
    expect(await storage.loadLocalProjectManifest(id), legacy);
  });
}
