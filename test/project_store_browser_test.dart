import 'dart:convert';

import 'package:bubble_caption_studio/src/file_gateway.dart';
import 'package:bubble_caption_studio/src/project_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/browser_storage_fixture.dart';

Uint8List _json(String format, {String text = '完整正文：不截断。'}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'format': format,
      'schemaVersion': 3,
      'pages': [],
      'script': text,
    }))).asUnmodifiableView();

void main() {
  test(
      'IndexedDB migration preserves legacy originals and verifies binary data',
      () async {
    setLegacyValue('bcs-project-catalog', 'damaged catalog');
    await expectLater(listLocalProjects(), throwsFormatException);
    expect(legacyValue('bcs-project-catalog'), 'damaged catalog');

    const legacyId = 'project-legacy-fixture';
    final packed = _json('bubble-caption-studio');
    final edits = _json('bubble-caption-studio-edits');
    final catalog = jsonEncode([
      {
        'id': legacyId,
        'name': '旧项目',
        'hasData': true,
        'updatedAt': '2026-10-12T00:00:00Z'
      }
    ]);
    setLegacyValue('bcs-project-catalog', catalog);
    setLegacyValue('bcs-project-$legacyId', base64Encode(packed));
    setLegacyValue('bcs-project-edits-$legacyId', base64Encode(edits));
    expect((await listLocalProjects()).any((p) => p.id == legacyId), isTrue);
    expect(await loadLocalProject(legacyId), packed);
    expect(await loadLocalProjectEdits(legacyId), edits);
    expect(legacyValue('bcs-project-catalog'), catalog);
    expect(legacyValue('bcs-project-$legacyId'), base64Encode(packed));
    expect(supportsIncrementalProjectStorage, isTrue);

    final image = Uint8List.fromList(List.generate(1024 * 1024, (i) => i % 251))
        .asUnmodifiableView();
    final fontAsset = Uint8List.fromList([1, 2, 3, 255]).asUnmodifiableView();
    await saveLocalProjectImage(legacyId, 'page-fixture', image);
    await saveLocalProjectAsset(legacyId, 'asset-fixture', fontAsset);
    await saveLocalProjectManifest(
        legacyId, '旧项目更新', _json('bubble-caption-studio-manifest'));
    expect(await loadLocalProjectImage(legacyId, 'page-fixture'), image);
    expect(
        await loadLocalProjectAsset(legacyId, 'asset-fixture'), [1, 2, 3, 255]);
    expect(await loadLocalProjectManifest(legacyId),
        _json('bubble-caption-studio-manifest'));
    final versions = await listLocalProjectVersions(legacyId);
    expect(versions, hasLength(1));
    expect(versions.single.kind, 'manifest');
    expect(await loadLocalProjectVersion(legacyId, versions.single.id),
        _json('bubble-caption-studio-manifest'));
    await saveLocalProjectManifest(
        legacyId, '旧项目更新', _json('bubble-caption-studio-manifest'));
    expect(await listLocalProjectVersions(legacyId), hasLength(1));
    for (var revision = 1; revision < 23; revision++) {
      await saveLocalProjectManifest(legacyId, '旧项目更新',
          _json('bubble-caption-studio-manifest', text: '版本$revision：完整文字'),
          revision: revision);
    }
    final recent = await listLocalProjectVersions(legacyId);
    expect(recent, hasLength(20));
    expect(recent.first.revision, 22);
    expect(await loadLocalProjectVersion(legacyId, recent.first.id),
        _json('bubble-caption-studio-manifest', text: '版本22：完整文字'));
    expect(await loadLocalProjectImage(legacyId, 'page-fixture'), image);
    await expectLater(
        saveLocalProjectEdits(legacyId, '旧项目更新', Uint8List.fromList([0, 1])),
        throwsFormatException);
    expect(await loadLocalProjectEdits(legacyId), edits);

    final created = await createLocalProject('新项目');
    await saveLocalProject(created.id, created.name, packed);
    expect(await loadLocalProject(created.id), packed);
    await deleteLocalProject(created.id);
    await deleteLocalProject(legacyId);
    expect((await listLocalProjects()).any((p) => p.id == legacyId), isFalse);
    expect(legacyValue('bcs-project-$legacyId'), base64Encode(packed));
    await expectLater(
        loadLocalProjectImage(legacyId, 'page-fixture'), throwsStateError);
  }, skip: !kIsWeb);

  test('browser export distinguishes unsupported, cancel and denied permission',
      () async {
    installExportPicker('missing');
    final fallback = await chooseImageExportDirectory();
    expect(fallback, isNotNull);
    expect(isBrowserDownloadExport(fallback!), isTrue);
    expect(exportTargetLabel(fallback), contains('逐图下载'));
    restoreExportPicker();
    installExportPicker('cancel');
    expect(await chooseImageExportDirectory(), isNull);
    restoreExportPicker();
    installExportPicker('denied');
    await expectLater(chooseImageExportDirectory(), throwsStateError);
    restoreExportPicker();
  }, skip: !kIsWeb);

  test('authorized browser directory writes individual PNGs and lists results',
      () async {
    installExportPicker('directory');
    addTearDown(restoreExportPicker);
    final target = (await chooseImageExportDirectory())!;
    expect(isBrowserDownloadExport(target), isFalse);
    expect(exportTargetLabel(target), 'Fixture Export');
    expect(await exportImageExists(target, 'fixture-1.png'), isFalse);
    await writeExportImage(target, 'fixture-1.png',
        Uint8List.fromList([1, 2, 3]).asUnmodifiableView(),
        overwrite: false);
    expect(await exportImageExists(target, 'fixture-1.png'), isTrue);
    await expectLater(
        writeExportImage(target, 'fixture-1.png', Uint8List.fromList([8]),
            overwrite: false),
        throwsStateError);
    await writeExportImage(target, 'fixture-1.png',
        Uint8List.fromList([4, 5, 6]).asUnmodifiableView(),
        overwrite: true);
    await writeExportImage(target, 'fixture-2.png', Uint8List.fromList([7, 8]),
        overwrite: false);
    expect(fakeExportedBytes('fixture-1.png'), [4, 5, 6]);
    expect(fakeExportedBytes('fixture-2.png'), [7, 8]);
    expect(await listBrowserExportFiles(target),
        ['fixture-1.png', 'fixture-2.png']);
  }, skip: !kIsWeb);
}
