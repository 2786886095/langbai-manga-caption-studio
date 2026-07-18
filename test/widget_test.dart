import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bubble_caption_studio/src/app.dart';
import 'package:bubble_caption_studio/src/app_localization.dart';
import 'package:bubble_caption_studio/src/app_settings.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/file_gateway.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/page_collection.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/text_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('application opens through the local project hub', (
    tester,
  ) async {
    await tester.pumpWidget(const BubbleCaptionApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, '浪白漫画字幕工坊');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('editable text exposes the Chinese right-click menu', (
    tester,
  ) async {
    final controller = TextEditingController(text: '测试字幕');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: TextField(
                controller: controller,
                contextMenuBuilder: buildAppTextContextMenu,
              ),
            ),
          ),
        ),
      ),
    );

    final location = tester.getCenter(find.byType(TextField));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await gesture.down(location);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
  });

  test('settings preserve export preferences and ignore legacy autosave', () {
    final settings = AppSettings.fromJson({
      'exportDirectory': r'D:\成图',
      'askExportLocation': false,
      'autoSave': true,
      'autoSaveSeconds': 10,
      'numberedExportNames': false,
      'languageCode': 'ja',
    });
    expect(settings.exportDirectory, r'D:\成图');
    expect(settings.askExportLocation, isFalse);
    expect(settings.numberedExportNames, isFalse);
    expect(settings.languageCode, 'ja');
    expect(settings.toJson(), isNot(contains('autoSave')));
    expect(settings.toJson(), isNot(contains('autoSaveSeconds')));
  });

  test('direct PNG export detects collisions and overwrites only when allowed',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('langbai-export-test-');
    addTearDown(() => directory.delete(recursive: true));
    const fileName = '0001-captioned-page.png';
    await writeExportImage(
      directory.path,
      fileName,
      Uint8List.fromList([1, 2, 3]),
      overwrite: false,
    );
    expect(await exportImageExists(directory.path, fileName), isTrue);
    await expectLater(
      writeExportImage(
        directory.path,
        fileName,
        Uint8List.fromList([4]),
        overwrite: false,
      ),
      throwsA(isA<FileSystemException>()),
    );
    await writeExportImage(
      directory.path,
      fileName,
      Uint8List.fromList([9, 8]),
      overwrite: true,
    );
    expect(
        await File('${directory.path}${Platform.pathSeparator}$fileName')
            .readAsBytes(),
        [9, 8]);
  });

  test('script maps captions to file names', () {
    final parsed = parseCaptionScript('[001.png]\n小雪：你好\n阿诚: 别出声');
    expect(parsed.byFile['001.png'], hasLength(2));
    expect(parsed.byFile['001.png']!.first.speaker, '小雪');
    expect(parsed.byFile['001.png']!.last.text, '别出声');
  });

  test('natural sorting keeps numbered images in visual order', () {
    expect(naturalSort(['10.png', '2.png', '1.png']), [
      '1.png',
      '2.png',
      '10.png',
    ]);
  });

  test('automatic placements remain inside the image', () {
    const captions = [
      CaptionLine(speaker: 'A', text: '第一句'),
      CaptionLine(speaker: 'B', text: '第二句'),
    ];
    const engine = LayoutEngine();
    final result = engine.arrange(
      captions,
      imageWidth: 1200,
      imageHeight: 1800,
    );
    expect(result, hasLength(2));
    for (final bubble in result) {
      expect(bubble.x, greaterThanOrEqualTo(0));
      expect(bubble.y, greaterThanOrEqualTo(0));
      expect(bubble.x + bubble.width, lessThanOrEqualTo(1200));
      expect(bubble.y + bubble.height, lessThanOrEqualTo(1800));
    }
  });

  test('bubble hit testing selects only the visible bubble shape', () {
    const caption = CaptionLine(speaker: '', text: '测试');
    const bubble = BubblePlacement(
      caption: caption,
      x: 100,
      y: 100,
      width: 200,
      height: 120,
    );
    expect(hitTestBubble(const [bubble], const Offset(150, 150)), 0);
    expect(hitTestBubble(const [bubble], const Offset(101, 101)), -1);
    expect(hitTestBubble(const [bubble], const Offset(90, 150)), -1);
    expect(hitTestBubble(const [bubble], const Offset(320, 150)), -1);

    final tail = bubbleTailGeometry(
      const Rect.fromLTWH(100, 100, 200, 120),
      bubble,
    );
    final tailInterior = Offset(
      (tail.start.dx + tail.tip.dx + tail.end.dx) / 3,
      (tail.start.dy + tail.tip.dy + tail.end.dy) / 3,
    );
    expect(hitTestBubble(const [bubble], tailInterior), 0);
  });

  test('settings reject unsupported language codes', () {
    final settings = AppSettings.fromJson({'languageCode': 'xx'});
    expect(settings.languageCode, 'zh_CN');
    expect(settings.toJson()['languageCode'], 'zh_CN');
  });

  test('all supported languages translate core interface text', () {
    expect(tr('设置', languageCode: 'zh_CN'), '设置');
    expect(tr('设置', languageCode: 'zh_TW'), '設定');
    expect(tr('设置', languageCode: 'en'), 'Settings');
    expect(tr('设置', languageCode: 'ja'), '設定');
    expect(tr('设置', languageCode: 'ko'), '설정');
    expect(
      tr('气泡属性', languageCode: 'en'),
      'Bubble properties',
    );
    expect(
      tr('字幕脚本无法应用', languageCode: 'ja'),
      '字幕スクリプトを適用できません',
    );
    expect(
      tr('批量导出', languageCode: 'ko'),
      '일괄 내보내기',
    );
  });

  test('script diagnostics follow the selected interface language', () {
    AppLocaleController.instance.setLanguage('en');
    addTearDown(() => AppLocaleController.instance.setLanguage('zh_CN'));
    final parsed = parseCaptionScript('''
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px

[图片 1]
@原图尺寸=bad
''');
    expect(parsed.warnings, isNotEmpty);
    expect(parsed.warnings.first, startsWith('Line '));
    expect(parsed.warnings.join(), isNot(contains('必须')));
  });

  testWidgets('all localized AI guides are bundled and preserve BCS tokens', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    for (final asset in const [
      'AI字幕脚本生成指南.md',
      'guides/ai_guide_zh_TW.md',
      'guides/ai_guide_en.md',
      'guides/ai_guide_ja.md',
      'guides/ai_guide_ko.md',
    ]) {
      final guide = await rootBundle.loadString(asset);
      expect(guide, contains('@格式=BCS顺序字幕脚本'), reason: asset);
      expect(guide, contains('@白底透明度=100'), reason: asset);
      expect(guide, contains('对话气泡'), reason: asset);
      expect(guide.length, greaterThan(2500), reason: asset);
    }
  });

  test('legacy font names map to bundled local fonts', () {
    expect(normalizeBubbleFontFamily('Microsoft YaHei'), 'Noto Sans SC');
    expect(normalizeBubbleFontFamily('SimSun'), 'ZCOOL XiaoWei');
    expect(normalizeBubbleFontFamily('楷体'), 'Ma Shan Zheng');
    expect(normalizeBubbleFontFamily('Imported_Custom'), 'Imported_Custom');
  });

  test('bundled Chinese fonts load and produce distinct text metrics',
      () async {
    Future<double> measure(String family, String asset) async {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
      final painter = TextPainter(
        text: TextSpan(
          text: '测试漫画气泡字幕',
          style: TextStyle(fontFamily: family, fontSize: 36),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    final widths = <double>{
      await measure(
          'Test Noto Sans SC', 'assets/fonts/NotoSansSC-Variable.ttf'),
      await measure(
        'Test ZCOOL XiaoWei',
        'assets/fonts/ZCOOLXiaoWei-Regular.ttf',
      ),
      await measure(
        'Test Ma Shan Zheng',
        'assets/fonts/MaShanZheng-Regular.ttf',
      ),
    };
    expect(widths.length, greaterThan(1));
  });

  test('precise script controls style while tail anchor stays fixed', () {
    final parsed = parseCaptionScript('''
[001.png]

@角色=小雪
@坐标=68%,12%
@尺寸=26%,18%
@尾巴=左下
@尾巴位置=35%
@气泡=旁白框
@字体=楷体
@字号=40
@颜色=#D52F4F
@行距=1.4
@描边=4
@白底透明度=65
你迟到了！
''');
    expect(parsed.warnings, hasLength(1));
    expect(parsed.warnings.single, contains('@尾巴位置 已停用'));
    final caption = parsed.byFile['001.png']!.single;
    expect(caption.speaker, '小雪');
    expect(caption.layout!.tailDirection, TailDirection.downLeft);
    expect(caption.layout!.shape, BubbleShape.rounded);
    expect(caption.layout!.fontFamily, 'Ma Shan Zheng');
    expect(caption.layout!.fontColorValue, 0xffd52f4f);

    const engine = LayoutEngine();
    final bubble =
        engine.arrange([caption], imageWidth: 1000, imageHeight: 2000).single;
    expect(bubble.x, 680);
    expect(bubble.y, 240);
    expect(bubble.width, 260);
    expect(bubble.height, 360);
    expect(bubble.fontSize, 40);
    expect(bubble.fillOpacity, .65);
    expect(bubble.tailDirection, TailDirection.downLeft);
    expect(bubble.tailX, .5);
  });

  test('project files preserve images, captions, placement, and style',
      () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final page = ImagePage(
      name: '001.png',
      bytes: Uint8List.fromList(png),
      image: frame.image,
    );
    const caption = CaptionLine(speaker: '小雪', text: '测试工程');
    page
      ..captions = const [caption]
      ..placements = const [
        BubblePlacement(
          caption: caption,
          x: 0,
          y: 0,
          width: 100,
          height: 80,
          shape: BubbleShape.thought,
          tailDirection: TailDirection.downRight,
          tailX: .65,
          fontColorValue: 0xffd52f4f,
          fillOpacity: .45,
        ),
      ]
      ..approved = true;

    final encoded = encodeProject([page], '[001.png]\n小雪：测试工程');
    final rawProject = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    expect(rawProject['schemaVersion'], 2);
    expect((rawProject['pages'] as List).single['originalWidth'], 1);
    expect((rawProject['pages'] as List).single['pageId'], page.pageId);
    final decoded = await decodeProject(encoded);

    expect(decoded.pages, hasLength(1));
    expect(decoded.pages.single.name, '001.png');
    expect(decoded.pages.single.captions.single.text, '测试工程');
    expect(decoded.pages.single.placements.single.shape, BubbleShape.thought);
    expect(decoded.pages.single.placements.single.tailX, .5);
    expect(decoded.pages.single.placements.single.fillOpacity, .45);
    expect(decoded.pages.single.approved, isTrue);
  });

  test('incremental project manifest keeps source images out of JSON',
      () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final page = ImagePage(
      name: '001.png',
      bytes: Uint8List.fromList(png),
      image: frame.image,
    );
    const caption = CaptionLine(speaker: '', text: '增量工程');
    page
      ..captions = const [caption]
      ..placements = const [
        BubblePlacement(
          caption: caption,
          x: 0,
          y: 0,
          width: 100,
          height: 80,
        ),
      ];

    final manifest = encodeProjectManifest([page], '脚本');
    final json = utf8.decode(manifest);
    expect(json, isNot(contains('sourceImage')));
    expect(manifest.length, lessThan(2000));

    final decoded = await decodeProjectManifest(manifest, (pageId) async {
      expect(pageId, page.pageId);
      return Uint8List.fromList(png);
    });
    expect(decoded.pages.single.name, '001.png');
    expect(decoded.pages.single.captions.single.text, '增量工程');
    decoded.pages.single.dispose();
    page.dispose();
  });

  test(
    'lightweight edit layers update bubbles without embedding images',
    () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final page = ImagePage(
        name: '001.png',
        bytes: Uint8List.fromList(png),
        image: frame.image,
        pageId: 'page-one',
      );
      const caption = CaptionLine(text: '修改后的文字', speaker: '');
      page
        ..captions = const [caption]
        ..placements = const [
          BubblePlacement(
            caption: caption,
            x: 12,
            y: 18,
            width: 240,
            height: 120,
            shape: BubbleShape.whisper,
          ),
        ];
      final edits = encodeProjectEdits([page], 'small script');
      expect(utf8.decode(edits), isNot(contains('sourceImage')));

      page
        ..captions = []
        ..placements = [];
      final script = applyProjectEdits(edits, [page]);
      expect(script, 'small script');
      expect(page.captions.single.text, '修改后的文字');
      expect(page.placements.single.shape, BubbleShape.whisper);
    },
  );

  test(
    'project order uses order rank and permits duplicate file names',
    () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final later = ImagePage(
        name: '001.png',
        bytes: Uint8List.fromList(png),
        image: frame.image,
        pageId: 'later',
        orderRank: 1,
      );
      final first = ImagePage(
        name: '001.png',
        bytes: Uint8List.fromList(png),
        image: frame.image,
        pageId: 'first',
        orderRank: 0,
      );

      final decoded = await decodeProject(encodeProject([later, first], ''));
      expect(decoded.pages.map((page) => page.pageId), ['first', 'later']);
      expect(decoded.pages.map((page) => page.name), ['001.png', '001.png']);
    },
  );

  test('adding images preserves the confirmed import order', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    ImagePage page(String name) => ImagePage(
          name: name,
          bytes: Uint8List.fromList(png),
          image: frame.image,
        );
    final original = page('010.png');
    final merged = mergeImagePages(
      [original],
      [page('002.png'), page('011.png')],
    );
    expect(merged.map((page) => page.name), ['010.png', '002.png', '011.png']);
    expect(merged.first, same(original));
    expect(merged.map((page) => page.orderRank), [0, 1, 2]);

    final replaced = mergeImagePages(
      [original],
      [page('001.png')],
      replace: true,
    );
    expect(replaced.map((page) => page.name), ['001.png']);
  });

  test('v2 scripts map by section order and declare original dimensions', () {
    final parsed = parseCaptionScript('''
@格式=BCS顺序字幕脚本
@版本=2
@坐标单位=px

[图片 1]
@原文件名=010.png
@原图尺寸=1000x2000

@气泡ID=p1-b1
@矩形=120,240,300,180
@气泡=心理气泡
@尾巴=右下
@颜色=#D52F4F
第一张字幕

[图片 2]
@原文件名=002.png
@原图尺寸=800x1200

@气泡ID=p2-b1
@矩形=40,60,260,140
第二张字幕
''');

    expect(parsed.usesSequentialFormat, isTrue);
    expect(parsed.sections, hasLength(2));
    expect(parsed.sections.first.originalName, '010.png');
    expect(parsed.sections.first.declaredWidth, 1000);
    expect(parsed.sections.first.declaredHeight, 2000);
    final first = parsed.sections.first.captions.single;
    expect(first.bubbleId, 'p1-b1');
    expect(first.layout!.x, 120);
    expect(first.layout!.y, 240);
    expect(first.layout!.width, 300);
    expect(first.layout!.height, 180);
    expect(first.layout!.shape, BubbleShape.thought);
    expect(parsed.sections.last.captions.single.text, '第二张字幕');
    expect(parsed.warnings, isEmpty);
  });

  test('v2 scripts report missing dimensions and out-of-order sections', () {
    final parsed = parseCaptionScript('''
[图片 2]
@原文件名=anything.png
字幕
''');
    expect(parsed.warnings, hasLength(2));
    expect(parsed.warnings.first, contains('[图片 1]'));
    expect(parsed.warnings.last, contains('@原图尺寸'));
  });

  test(
    'v2 validation blocks dimension mismatch and out-of-bounds bubbles',
    () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final page = ImagePage(
        name: 'anything.png',
        bytes: Uint8List.fromList(png),
        image: frame.image,
      );
      final parsed = parseCaptionScript('''
[图片 1]
@原文件名=another-name.png
@原图尺寸=2x1

@气泡ID=p1-b1
@矩形=1,0,2,1
字幕
''');

      final errors = validateScriptForPages(parsed, [page]);
      expect(errors, hasLength(2));
      expect(errors.first, contains('尺寸不一致'));
      expect(errors.last, contains('@矩形 超出原图'));
    },
  );

  test('applying edited scripts preserves manual bubble geometry', () {
    const oldCaption = CaptionLine(speaker: 'A', text: 'old');
    const newCaption = CaptionLine(speaker: 'A', text: 'new');
    const existing = BubblePlacement(
      caption: oldCaption,
      x: 137,
      y: 91,
      width: 284,
      height: 126,
      shape: BubbleShape.thought,
      tailDirection: TailDirection.upRight,
      tailX: .73,
      fontSize: 39,
      fontColorValue: 0xffd52f4f,
    );
    const generated = BubblePlacement(
      caption: newCaption,
      x: 20,
      y: 20,
      width: 180,
      height: 90,
    );

    final result = preserveEditedPlacements(
      const [existing],
      const [generated],
      const [newCaption],
    ).single;

    expect(result.caption.text, 'new');
    expect(result.x, 137);
    expect(result.y, 91);
    expect(result.width, 284);
    expect(result.shape, BubbleShape.thought);
    expect(result.tailDirection, TailDirection.upRight);
    expect(result.tailX, .73);
    expect(result.fontSize, 39);
  });

  test('explicit script geometry overrides an existing manual placement', () {
    const caption = CaptionLine(
      speaker: '',
      text: '使用脚本坐标',
      bubbleId: 'p1-b1',
      layout: CaptionLayoutSpec(
        x: 620,
        y: 140,
        width: 360,
        height: 220,
      ),
    );
    const existing = BubblePlacement(
      caption: caption,
      x: 20,
      y: 30,
      width: 180,
      height: 90,
    );
    const generated = BubblePlacement(
      caption: caption,
      x: 620,
      y: 140,
      width: 360,
      height: 220,
    );

    final result = preserveEditedPlacements(
      const [existing],
      const [generated],
      const [caption],
    ).single;

    expect(result.x, 620);
    expect(result.y, 140);
    expect(result.width, 360);
    expect(result.height, 220);
  });

  test('stable bubble ids preserve geometry when a caption is inserted', () {
    const first = CaptionLine(speaker: '', text: '第一句', bubbleId: 'p1-b1');
    const second = CaptionLine(speaker: '', text: '第二句', bubbleId: 'p1-b2');
    const inserted = CaptionLine(speaker: '', text: '插入句', bubbleId: 'p1-new');
    const existing = [
      BubblePlacement(caption: first, x: 10, y: 20, width: 200, height: 100),
      BubblePlacement(caption: second, x: 333, y: 444, width: 260, height: 130),
    ];
    const captions = [first, inserted, second];
    const generated = [
      BubblePlacement(caption: first, x: 0, y: 0, width: 1, height: 1),
      BubblePlacement(caption: inserted, x: 1, y: 1, width: 1, height: 1),
      BubblePlacement(caption: second, x: 2, y: 2, width: 1, height: 1),
    ];

    final result = preserveEditedPlacements(existing, generated, captions);
    expect(result[0].x, 10);
    expect(result[1].x, 1);
    expect(result[2].x, 333);
    expect(result[2].y, 444);
  });

  test('tail geometry reaches a visible tip in all four directions', () {
    const caption = CaptionLine(speaker: 'A', text: '方向测试');
    const rect = ui.Rect.fromLTWH(100, 100, 240, 120);
    BubbleTailGeometry geometry(TailDirection direction) => bubbleTailGeometry(
          rect,
          BubblePlacement(
            caption: caption,
            x: 100,
            y: 100,
            width: 240,
            height: 120,
            tailDirection: direction,
          ),
        );

    final upLeft = geometry(TailDirection.upLeft).tip;
    final upRight = geometry(TailDirection.upRight).tip;
    final downLeft = geometry(TailDirection.downLeft).tip;
    final downRight = geometry(TailDirection.downRight).tip;
    Offset base(TailDirection direction) {
      final tail = geometry(direction);
      return Offset.lerp(tail.start, tail.end, .5)!;
    }

    expect(upLeft.dx, lessThan(rect.center.dx));
    expect(upLeft.dy, lessThan(rect.top));
    expect(base(TailDirection.upLeft).dx, lessThan(rect.center.dx));
    expect(base(TailDirection.upLeft).dy, lessThan(rect.center.dy));
    expect(upRight.dx, greaterThan(rect.center.dx));
    expect(upRight.dy, lessThan(rect.top));
    expect(base(TailDirection.upRight).dx, greaterThan(rect.center.dx));
    expect(base(TailDirection.upRight).dy, lessThan(rect.center.dy));
    expect(downLeft.dx, lessThan(rect.center.dx));
    expect(downLeft.dy, greaterThan(rect.bottom));
    expect(base(TailDirection.downLeft).dx, lessThan(rect.center.dx));
    expect(base(TailDirection.downLeft).dy, greaterThan(rect.center.dy));
    expect(downRight.dx, greaterThan(rect.center.dx));
    expect(downRight.dy, greaterThan(rect.bottom));
    expect(base(TailDirection.downRight).dx, greaterThan(rect.center.dx));
    expect(base(TailDirection.downRight).dy, greaterThan(rect.center.dy));
    expect(bubbleResizeHandles(rect), hasLength(8));

    const fixedLeft = BubblePlacement(
      caption: caption,
      x: 100,
      y: 100,
      width: 240,
      height: 120,
      tailX: .2,
    );
    const fixedRight = BubblePlacement(
      caption: caption,
      x: 100,
      y: 100,
      width: 240,
      height: 120,
      tailX: .8,
    );
    expect(
      bubbleTailGeometry(rect, fixedLeft).tip,
      bubbleTailGeometry(rect, fixedRight).tip,
    );
  });

  test('preset positions and invalid values are reported safely', () {
    final valid = parseCaptionScript(
      '[001.png]\n@角色=A\n@位置=右下\n@尺寸=20%,10%\n台词',
    );
    final bubble = const LayoutEngine()
        .arrange(valid.byFile['001.png']!, imageWidth: 1000, imageHeight: 1000)
        .single;
    expect(bubble.x, 755);
    expect(bubble.y, 855);

    final invalid = parseCaptionScript(
      '[001.png]\n@角色=A\n@坐标=120%,x\n@尾巴=斜\n台词',
    );
    expect(invalid.warnings, hasLength(2));
  });

  test('expanded comic bubble styles are parsed explicitly', () {
    final whisper = parseCaptionScript('[001.png]\n@气泡=耳语气泡\n@尾巴=左上\n轻声说话');
    final shout = parseCaptionScript('[001.png]\n@气泡=惊喊气泡\n@尾巴=右下\n小心！');
    expect(
      whisper.byFile['001.png']!.single.layout!.shape,
      BubbleShape.whisper,
    );
    expect(shout.byFile['001.png']!.single.layout!.shape, BubbleShape.shout);
  });
}
