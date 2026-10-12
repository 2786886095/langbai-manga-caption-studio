import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/exporter.dart';
import 'package:bubble_caption_studio/src/font_library.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/text_layout_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _service = TextLayoutService();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  recoveryTests();

  test(
      'fixed keeps the requested size and complete text while reporting overflow',
      () {
    final bubble = _bubble().copyWith(
      width: 100,
      height: 40,
      fontSize: 80,
      caption: const CaptionLine(speaker: '', text: 'ONE\nTWO\nTHREE'),
    );
    final fixed = _service.layout(bubble);
    expect(fixed.effectiveFontSize, 80);
    expect(fixed.overflow, isTrue);
    expect(fixed.painter.text!.toPlainText(), 'ONE\nTWO\nTHREE');
    expect(fixed.painter.maxLines, isNull);
    expect(fixed.painter.ellipsis, isNull);
    fixed.dispose();

    final fit =
        _service.layout(bubble.copyWith(textSizeMode: TextSizeMode.fit));
    expect(fit.effectiveFontSize, lessThan(80));
    expect(fit.overflow, isFalse);
    expect(fit.lineCount, greaterThanOrEqualTo(3));
    expect(fit.painter.text!.toPlainText(), 'ONE\nTWO\nTHREE');
    fit.dispose();
  });

  test('letter spacing and alignment affect shared layout metrics', () {
    final bubble = _bubble().copyWith(
      width: 280,
      caption: const CaptionLine(speaker: '', text: 'ABCD'),
    );
    final normal =
        _service.layout(bubble.copyWith(textAlign: ui.TextAlign.left));
    final spaced = _service.layout(
        bubble.copyWith(letterSpacing: 4, textAlign: ui.TextAlign.right));
    expect(spaced.painter.computeLineMetrics().single.width,
        greaterThan(normal.painter.computeLineMetrics().single.width));
    expect(normal.painter.computeLineMetrics().single.left, closeTo(0, .01));
    expect(spaced.painter.computeLineMetrics().single.left, greaterThan(0));
    expect((spaced.painter.text! as TextSpan).style!.letterSpacing, 4);
    normal.dispose();
    spaced.dispose();
  });

  test('fixed text can cross its own rectangle but never the page', () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble().copyWith(
      x: 140,
      y: 85,
      width: 40,
      height: 30,
      fontSize: 40,
      caption: const CaptionLine(speaker: '', text: 'A\nB\nC'),
    );
    page.placements = [bubble];
    final image = await _paint(page);
    final pixels =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    var outsideRectangle = 0;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 320; x++) {
        if (pixels.getUint8((y * 320 + x) * 4 + 3) == 0) continue;
        if (!ui.Rect.fromLTWH(140, 85, 40, 30)
            .contains(ui.Offset(x.toDouble(), y.toDouble()))) {
          outsideRectangle++;
        }
      }
    }
    expect(outsideRectangle, greaterThan(0));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(40, 40);
    PagePainter(page: page).paint(canvas, const ui.Size(320, 200));
    final picture = recorder.endRecording();
    final padded = await picture.toImage(400, 280);
    picture.dispose();
    final paddedPixels =
        (await padded.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    padded.dispose();
    for (var y = 0; y < 280; y++) {
      for (var x = 0; x < 400; x++) {
        if (x >= 40 && x < 360 && y >= 40 && y < 240) continue;
        expect(paddedPixels.getUint8((y * 400 + x) * 4 + 3), 0);
      }
    }
  });

  test('text stroke paints independently of zero bubble outline', () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble().copyWith(
      fontColorValue: 0xffff0000,
      caption: const CaptionLine(speaker: '', text: 'STROKE'),
      strokeWidth: 0,
      textStrokeWidth: 6,
      textStrokeColorValue: 0xff0000ff,
    );
    page.placements = [bubble];
    final image = await _paint(page);
    final pixels =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    var redPixels = 0;
    var bluePixels = 0;
    for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
      if (pixels.getUint8(offset + 3) == 0) continue;
      if (pixels.getUint8(offset) > pixels.getUint8(offset + 2)) redPixels++;
      if (pixels.getUint8(offset + 2) > pixels.getUint8(offset)) bluePixels++;
    }
    expect(redPixels, greaterThan(0));
    expect(bluePixels, greaterThan(0));
  });

  test(
      'bubble outline zero really draws nothing and original px can exceed seven',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble().copyWith(
      shape: BubbleShape.rounded,
      fillOpacity: 0,
      caption: const CaptionLine(speaker: '', text: ''),
    );
    Future<int> visible(double stroke) async {
      page.placements = [bubble.copyWith(strokeWidth: stroke)];
      final image = await _paint(page);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
      var count = 0;
      for (var offset = 3; offset < pixels.lengthInBytes; offset += 4) {
        if (pixels.getUint8(offset) > 0) count++;
      }
      return count;
    }

    expect(await visible(0), 0);
    expect(await visible(20), greaterThan(await visible(7)));
  });

  test('preview and production PNG export share fixed layout and stroke pixels',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    page.placements = [
      _bubble().copyWith(
        textStrokeWidth: 2,
        letterSpacing: 1.5,
        textAlign: ui.TextAlign.left,
      )
    ];
    final preview = await _paint(page);
    final expected =
        (await preview.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    preview.dispose();
    final exported = await renderPageForExport(page, 0);
    final codec = await ui.instantiateImageCodec(exported.bytes);
    final frame = await codec.getNextFrame();
    final actual =
        (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    frame.image.dispose();
    codec.dispose();
    expect(actual, expected);
  });

  test(
      'BCS3 preserves new styles, IDs and decimal geometry; BCS2 warns and degrades',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble().copyWith(
      x: 24.25,
      fontSize: 40.75,
      textStrokeWidth: 2.25,
      textStrokeColorValue: 0xff123456,
      letterSpacing: 1.5,
      textAlign: ui.TextAlign.right,
      fontFamily: 'Runtime_Content_Hash_Family',
      fontDisplayName: '清晰中文字体',
      fontAssetId: 'sha256:test:face0',
      styleId: 'style-dialogue-1',
    );
    page.placements = [bubble];
    page.captions = [bubble.caption];
    final script = buildBcsScript([page]);
    expect(script, startsWith('@格式=BCS顺序字幕脚本\n@版本=3\n'));
    expect(script, contains('@字体=清晰中文字体\n'));
    expect(script, isNot(contains('Runtime_Content_Hash_Family')));
    final parsed = parseCaptionScript(script);
    expect(parsed.version, 3);
    expect(parsed.warnings, isEmpty);
    final caption = parsed.sections.single.captions.single;
    final restored = const LayoutEngine()
        .arrange([caption], imageWidth: 320, imageHeight: 200).single;
    expect(restored.textSizeMode, TextSizeMode.fixed);
    expect(restored.textStrokeWidth, 2.25);
    expect(restored.textStrokeColorValue, 0xff123456);
    expect(restored.letterSpacing, 1.5);
    expect(restored.textAlign, ui.TextAlign.right);
    expect(restored.fontDisplayName, '清晰中文字体');
    expect(restored.fontAssetId, 'sha256:test:face0');
    expect(restored.styleId, 'style-dialogue-1');
    expect(restored.fontSize, 40.75);
    expect(restored.x, 24.25);
    final v2 = buildBcsScript([page], version: 2);
    expect(v2, contains('@版本=2\n'));
    expect(v2, isNot(contains('@文字描边=')));
    expect(v2, isNot(contains('@样式ID=')));
    expect(bcsV2CompatibilityWarnings([page]), hasLength(5));
    final old = parseCaptionScript(v2).sections.single.captions.single;
    expect(
        const LayoutEngine()
            .arrange([old], imageWidth: 320, imageHeight: 200)
            .single
            .textSizeMode,
        TextSizeMode.fit);
  });

  test(
      'BCS uses shared ranges for typography and preserves absent legacy directives',
      () {
    final parsed = parseCaptionScript('''
@格式=BCS顺序字幕脚本
@版本=3
[图片 1]
@原文件名=001.png
@原图尺寸=320x200
@气泡ID=p1-b1
@字号=200
@行距=3
@描边=0
@文字描边=20
@字距=-10
@对齐=左对齐
正文：必须保留。
''');
    expect(parsed.warnings, isEmpty);
    final spec = parsed.sections.single.captions.single.layout!;
    expect(spec.fontSize, TextStyleLimits.maxFontSize);
    expect(spec.lineHeight, TextStyleLimits.maxLineHeight);
    expect(spec.strokeWidth, 0);
    expect(spec.textStrokeWidth, 20);
    expect(spec.letterSpacing, -10);
    expect(spec.textSizeMode, TextSizeMode.fixed);
    final old = parseCaptionScript('[001.png]\n@字号=40\n正文')
        .byFile['001.png']!
        .single
        .layout!;
    expect(old.textAlign, isNull);
    expect(old.textSizeMode, isNull);
  });

  test(
      'schema3 packed manifest and edit data preserve all expanded text fields',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble().copyWith(
      textStrokeWidth: 2,
      textStrokeColorValue: 0xffabcdef,
      letterSpacing: 3,
      textAlign: ui.TextAlign.left,
      fontAssetId: 'sha256:test:face0',
      fontDisplayName: '项目字体',
      styleId: 'linked-style',
    );
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];
    final packed = encodeProject([page], buildBcsScript([page]));
    expect(jsonDecode(utf8.decode(packed))['schemaVersion'], 3);
    final packedResult = await decodeProject(packed);
    addTearDown(packedResult.pages.single.dispose);
    final manifest = encodeProjectManifest([page], 'manifest');
    final manifestResult =
        await decodeProjectManifest(manifest, (_) async => page.bytes);
    addTearDown(manifestResult.pages.single.dispose);
    await applyProjectEdits(
        encodeProjectEdits([page], 'edits'), packedResult.pages);
    for (final result in [packedResult, manifestResult]) {
      final restored = result.pages.single.placements.single;
      expect(restored.textSizeMode, TextSizeMode.fixed);
      expect(restored.textStrokeWidth, 2);
      expect(restored.textStrokeColorValue, 0xffabcdef);
      expect(restored.letterSpacing, 3);
      expect(restored.textAlign, ui.TextAlign.left);
      expect(restored.fontAssetId, 'sha256:test:face0');
      expect(restored.fontDisplayName, '项目字体');
      expect(restored.styleId, 'linked-style');
    }
    final unlinked = bubble.copyWith(
        styleId: null, fontAssetId: null, fontDisplayName: null);
    expect(unlinked.styleId, isNull);
    expect(unlinked.fontAssetId, isNull);
    expect(unlinked.fontDisplayName, isNull);
  });

  test(
      'schema2 keeps historical fit mode and missing edit image field is not deletion',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble();
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];
    final raw = jsonDecode(utf8.decode(encodeProject([page], 'old')))
        as Map<String, dynamic>;
    raw['schemaVersion'] = 2;
    final placement = raw['pages'][0]['placements'][0] as Map<String, dynamic>;
    for (final field in [
      'textSizeMode',
      'textStrokeWidth',
      'textStrokeColorValue',
      'letterSpacing',
      'textAlign',
      'fontAssetId',
      'fontDisplayName',
      'styleId'
    ]) {
      placement.remove(field);
    }
    final restored =
        await decodeProject(Uint8List.fromList(utf8.encode(jsonEncode(raw))));
    addTearDown(restored.pages.single.dispose);
    expect(
        restored.pages.single.placements.single.textSizeMode, TextSizeMode.fit);
    final assetFrame =
        await (await ui.instantiateImageCodec(page.bytes)).getNextFrame();
    restored.pages.single.placedImages = [
      PlacedImage(
        id: 'saved-image',
        name: 'sticker.png',
        bytes: page.bytes,
        image: assetFrame.image,
        x: 10,
        y: 10,
        width: 30,
        height: 30,
      )
    ];
    final edits =
        jsonDecode(utf8.decode(encodeProjectEdits(restored.pages, 'old edits')))
            as Map<String, dynamic>;
    edits['schemaVersion'] = 2;
    (edits['pages'][0] as Map<String, dynamic>).remove('placedImages');
    await applyProjectEdits(
        Uint8List.fromList(utf8.encode(jsonEncode(edits))), restored.pages);
    expect(restored.pages.single.placedImages.single.id, 'saved-image');
  });

  test(
      'manifest references font binary assets once and packed export still embeds bytes',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final fontBytes =
        (await rootBundle.load('assets/fonts/ZCOOLXiaoWei-Regular.ttf'))
            .buffer
            .asUint8List();
    final asset = await FontLibrary.instance
        .ensureRegisteredAsset(fontBytes, displayName: '可恢复字体');
    final bubble = _bubble().copyWith(
        fontFamily: asset.runtimeFamily,
        fontAssetId: asset.id,
        fontDisplayName: asset.displayName);
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];
    final fontMap = {asset.runtimeFamily: fontBytes};
    const binaryId = 'font-binary-1';
    final manifest = encodeProjectManifest([page], 'refs',
        fonts: fontMap, fontAssetReferences: {asset.runtimeFamily: binaryId});
    final raw = jsonDecode(utf8.decode(manifest));
    expect(raw['fonts'], isEmpty);
    expect(raw['fontAssets'][asset.runtimeFamily], binaryId);
    expect(raw['fontMetadata'][asset.runtimeFamily]['id'], asset.id);
    var loads = 0;
    final restored = await decodeProjectManifest(
        manifest, (_) async => page.bytes, (id) async {
      expect(id, binaryId);
      loads++;
      return fontBytes;
    });
    addTearDown(restored.pages.single.dispose);
    expect(loads, 1);
    expect(restored.fontWarnings, isEmpty);
    expect(restored.fonts[asset.runtimeFamily], fontBytes);
    expect(restored.pages.single.placements.single.fontAssetId, asset.id);
    final packed = jsonDecode(
        utf8.decode(encodeProject([page], 'embedded', fonts: fontMap)));
    expect(packed['fonts'][asset.runtimeFamily], base64Encode(fontBytes));
    expect(packed.containsKey('fontAssets'), isFalse);
  });
}

// Additional recovery checks run as a separate group, without UI/global storage.
void recoveryTests() {
  test('all six documentation files contain parseable counted BCS3 examples',
      () {
    final files = [
      '字幕导入格式规范.md',
      'AI字幕脚本生成指南.md',
      'guides/ai_guide_zh_TW.md',
      'guides/ai_guide_en.md',
      'guides/ai_guide_ja.md',
      'guides/ai_guide_ko.md'
    ];
    for (final file in files) {
      final contents = File(file).readAsStringSync();
      final blocks = RegExp(r'```text\r?\n([\s\S]*?)\r?\n```')
          .allMatches(contents)
          .map((match) => match.group(1)!)
          .where((text) =>
              text.startsWith('@格式=BCS顺序字幕脚本') && text.contains('@版本=3'))
          .toList();
      expect(blocks, isNotEmpty, reason: file);
      for (final block in blocks) {
        final parsed = parseCaptionScript(block);
        expect(parsed.errors, isEmpty, reason: file);
        expect(parsed.warnings, isEmpty, reason: file);
        expect(parsed.sections.single.captions, hasLength(1), reason: file);
      }
    }
  });

  test('BCS3 round trips an empty caption without deleting its bubble',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final bubble = _bubble().copyWith(
      caption:
          const CaptionLine(speaker: '', text: '', bubbleId: 'empty-bubble'),
    );
    page.placements = [bubble];
    final script = buildBcsScript([page]);
    expect(script, contains('@正文行数=0\n'));
    final parsed = parseCaptionScript(script);
    expect(parsed.errors, isEmpty);
    expect(parsed.sections.single.captions, hasLength(1));
    expect(parsed.sections.single.captions.single.text, '');
    expect(parsed.sections.single.captions.single.bubbleId, 'empty-bubble');
    expect(bcsV2CompatibilityWarnings([page]).join(), contains('空气泡'));
  });

  test(
      'BCS3 counted bodies retain blank lines and leading or trailing whitespace',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    const text = '  第一行  \n\n第三行\n';
    page.placements = [
      _bubble().copyWith(
        caption:
            const CaptionLine(speaker: '', text: text, bubbleId: 'literal'),
      )
    ];
    final parsed = parseCaptionScript(buildBcsScript([page]));
    expect(parsed.errors, isEmpty);
    expect(parsed.sections.single.captions.single.text, text);
    expect(bcsV2CompatibilityWarnings([page]).join(), contains('正文空行'));
  });

  test(
      'BCS3 literal body markers are not comments, directives or image headers',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    const text = '#实际作品文字\n@气泡ID=这不是字段\n[图片 99]\n@正文行数=999\n正文';
    page.placements = [
      _bubble().copyWith(
          caption:
              const CaptionLine(speaker: '', text: text, bubbleId: 'p1-b1')),
      _bubble().copyWith(
          caption: const CaptionLine(
              speaker: '', text: '下一个气泡。', bubbleId: 'p1-b2')),
    ];
    final parsed = parseCaptionScript(buildBcsScript([page]));
    expect(parsed.errors, isEmpty);
    expect(parsed.warnings, isEmpty);
    expect(parsed.sections, hasLength(1));
    expect(parsed.sections.single.captions, hasLength(2));
    expect(parsed.sections.single.captions[0].text, text);
    expect(parsed.sections.single.captions[1].text, '下一个气泡。');
  });

  test('invalid or unfinished BCS3 counted bodies block script application',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    const prefix = '@格式=BCS顺序字幕脚本\n@版本=3\n[图片 1]\n'
        '@原图尺寸=320x200\n@气泡ID=p1-b1\n';
    for (final body in ['@正文行数=-1\n正文', '@正文行数=4\n只有一行']) {
      final parsed = parseCaptionScript(prefix + body);
      expect(parsed.errors, isNotEmpty);
      expect(validateScriptForPages(parsed, [page]), isNotEmpty);
    }
  });

  test(
      'missing or substituted font assets keep their reference and logical identity',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final hash = List.filled(64, 'a').join();
    final family = 'BCS_Font_${hash}_face0';
    final id = 'sha256:$hash:face0';
    final bubble = _bubble().copyWith(
        fontFamily: family, fontAssetId: id, fontDisplayName: '暂时无法读取的字体');
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];
    final references = {family: 'font-original-binary'};
    final manifest = encodeProjectManifest([page], 'missing font',
        fontAssetReferences: references);
    final missing = await decodeProjectManifest(
        manifest,
        (_) async => page.bytes,
        (_) async => throw StateError('temporary read failure'));
    addTearDown(missing.pages.single.dispose);
    expect(missing.fontWarnings, isNotEmpty);
    expect(missing.fontAssetReferences, references);
    expect(missing.pages.single.placements.single.fontAssetId, id);
    expect(missing.pages.single.placements.single.fontFamily, family);
    final next = jsonDecode(utf8.decode(encodeProjectManifest(
        missing.pages, 'edited text',
        fonts: missing.fonts,
        fontAssetReferences: missing.fontAssetReferences)));
    expect(next['fontAssets'], references);
    expect(next['fontMetadata'][family]['id'], id);

    final substitutedBytes =
        (await rootBundle.load('assets/fonts/ZCOOLXiaoWei-Regular.ttf'))
            .buffer
            .asUint8List();
    final substituted = await decodeProjectManifest(
        manifest, (_) async => page.bytes, (_) async => substitutedBytes);
    addTearDown(substituted.pages.single.dispose);
    expect(substituted.fontWarnings.single, contains('SHA256'));
    expect(substituted.fonts, isEmpty);
    expect(substituted.fontAssetReferences, references);
    expect(substituted.pages.single.placements.single.fontAssetId, id);
  });

  test(
      'legacy schema2 font aliases remap consistently through old edit overlays',
      () async {
    final page = await _page();
    addTearDown(page.dispose);
    final fontBytes =
        (await rootBundle.load('assets/fonts/ZCOOLXiaoWei-Regular.ttf'))
            .buffer
            .asUint8List();
    const oldFamily = 'Imported_legacy_name_6313808';
    final bubble = _bubble().copyWith(fontFamily: oldFamily);
    page
      ..captions = [bubble.caption]
      ..placements = [bubble];
    final packed = jsonDecode(utf8.decode(
            encodeProject([page], 'legacy', fonts: {oldFamily: fontBytes})))
        as Map<String, dynamic>;
    packed['schemaVersion'] = 2;
    packed.remove('fontMetadata');
    final rawPlacement =
        packed['pages'][0]['placements'][0] as Map<String, dynamic>;
    rawPlacement.remove('textSizeMode');
    final restored = await decodeProject(
        Uint8List.fromList(utf8.encode(jsonEncode(packed))));
    addTearDown(restored.pages.single.dispose);
    final runtimeFamily = restored.pages.single.placements.single.fontFamily;
    expect(runtimeFamily, isNot(oldFamily));
    expect(restored.fontAliases[oldFamily], runtimeFamily);
    expect(
        restored.pages.single.placements.single.textSizeMode, TextSizeMode.fit);
    final overlay = encodeProjectEdits([page], 'old layer');
    await applyProjectEdits(overlay, restored.pages,
        fontAliases: restored.fontAliases);
    expect(restored.pages.single.placements.single.fontFamily, runtimeFamily);
    expect(restored.pages.single.placements.single.fontAssetId,
        fontAssetIdForBytes(fontBytes));
  });
}

BubblePlacement _bubble() => const BubblePlacement(
      caption: CaptionLine(speaker: '', text: '完整：固定文字。', bubbleId: 'p1-b1'),
      x: 24,
      y: 24,
      width: 240,
      height: 120,
      shape: BubbleShape.plainText,
      textSizeMode: TextSizeMode.fixed,
      fontSize: 34,
      fontColorValue: 0xff141518,
    );

Future<ImagePage> _page() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  picture.dispose();
  final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
  return ImagePage(
      name: '001.png',
      bytes: encoded!.buffer.asUint8List(),
      image: image,
      pageId: 'test-page');
}

Future<ui.Image> _paint(ImagePage page) async {
  final recorder = ui.PictureRecorder();
  PagePainter(page: page).paint(ui.Canvas(recorder), const ui.Size(320, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  picture.dispose();
  return image;
}
