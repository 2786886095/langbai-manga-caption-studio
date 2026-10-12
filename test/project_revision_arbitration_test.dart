import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImagePage page;
  setUp(() async {
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    codec.dispose();
    page = ImagePage(
        pageId: 'revision-page', name: '1.png', bytes: png, image: frame.image);
    _text(page, 'MANIFEST-NEW', 72);
  });
  tearDown(() => page.dispose());

  test('all three native project formats persist explicit revision', () async {
    final packed = encodeProject([page], 'script', revision: 42);
    final manifest = encodeProjectManifest([page], 'script', revision: 42);
    final edits = encodeProjectEdits([page], 'script', revision: 42);
    for (final data in [packed, manifest, edits]) {
      expect(jsonDecode(utf8.decode(data))['revision'], 42);
    }
    final decoded = await decodeProject(packed);
    expect(decoded.revision, 42);
    decoded.pages.single.dispose();
    final decodedManifest =
        await decodeProjectManifest(manifest, (_) async => page.bytes);
    expect(decodedManifest.revision, 42);
    decodedManifest.pages.single.dispose();
  });

  test(
      'manifest-new edits-old interruption cannot revert saved caption or style',
      () async {
    final manifest = encodeProjectManifest([page], 'MANIFEST-NEW', revision: 9);
    _text(page, 'EDITS-OLD', 34);
    final oldEdits = encodeProjectEdits([page], 'EDITS-OLD', revision: 8);
    final recovered =
        await decodeProjectManifest(manifest, (_) async => page.bytes);
    final result = await applyProjectEdits(oldEdits, recovered.pages,
        projectRevision: recovered.revision);
    expect(result.ignoredStaleEdits, isTrue);
    expect(result.revision, 9);
    expect(result.script, contains('MANIFEST-NEW'));
    expect(result.script, isNot(contains('EDITS-OLD')));
    expect(
        recovered.pages.single.placements.single.caption.text, 'MANIFEST-NEW');
    expect(recovered.pages.single.placements.single.fontSize, 72);
    recovered.pages.single.dispose();
  });

  test(
      'missing edit revision is ignored only when manifest has a durable revision',
      () async {
    _text(page, 'LEGACY-EDITS', 34);
    final legacyEdits = encodeProjectEdits([page], 'LEGACY-EDITS');
    _text(page, 'CURRENT', 72);
    final protected =
        await applyProjectEdits(legacyEdits, [page], projectRevision: 5);
    expect(protected.ignoredStaleEdits, isTrue);
    expect(page.captions.single.text, 'CURRENT');
    final compatible = await applyProjectEdits(legacyEdits, [page]);
    expect(compatible.ignoredStaleEdits, isFalse);
    expect(page.captions.single.text, 'LEGACY-EDITS');
    expect(compatible.revision, isNull);
  });

  test(
      'matching and later edit revisions remain recoverable and report their revision',
      () async {
    for (final editRevision in [10, 11]) {
      _text(page, 'EDITS-$editRevision', 90);
      final edits = encodeProjectEdits([page], 'EDITS-$editRevision',
          revision: editRevision);
      _text(page, 'MANIFEST', 34);
      final result =
          await applyProjectEdits(edits, [page], projectRevision: 10);
      expect(result.ignoredStaleEdits, isFalse);
      expect(result.revision, editRevision);
      expect(page.captions.single.text, 'EDITS-$editRevision');
      expect(page.placements.single.fontSize, 90);
    }
  });

  test(
      'legacy packed files remain readable and invalid revisions cannot bypass arbitration',
      () async {
    final legacy = jsonDecode(utf8.decode(encodeProject([page], 'old')))
        as Map<String, dynamic>;
    legacy['schemaVersion'] = 2;
    final decoded = await decodeProject(_bytes(legacy));
    expect(decoded.revision, isNull);
    decoded.pages.single.dispose();
    legacy['revision'] = 2.5;
    await expectLater(decodeProject(_bytes(legacy)), throwsFormatException);
    expect(() => encodeProjectEdits([page], 'bad', revision: -1),
        throwsArgumentError);
    final invalidEdits =
        jsonDecode(utf8.decode(encodeProjectEdits([page], 'bad')))
            as Map<String, dynamic>;
    invalidEdits['revision'] = '9';
    await expectLater(
        applyProjectEdits(_bytes(invalidEdits), [page], projectRevision: 8),
        throwsFormatException);
  });
}

void _text(ImagePage page, String text, double size) {
  final caption = CaptionLine(speaker: '', text: text, bubbleId: 'p1-b1');
  page.captions = [caption];
  page.placements = [
    BubblePlacement(
        caption: caption,
        x: 0,
        y: 0,
        width: 100,
        height: 80,
        fontSize: size,
        textSizeMode: TextSizeMode.fixed,
        shape: BubbleShape.plainText)
  ];
}

Uint8List _bytes(Map<String, dynamic> data) =>
    Uint8List.fromList(utf8.encode(jsonEncode(data)));
