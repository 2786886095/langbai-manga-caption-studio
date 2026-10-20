// Settings defaults and explicit project transactions.
// Desktop/mobile widget coverage is simulated, not real-device acceptance.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:bubble_caption_studio/src/app_settings.dart';
import 'package:bubble_caption_studio/src/layout_engine.dart';
import 'package:bubble_caption_studio/src/script_parser.dart';
import 'package:bubble_caption_studio/src/script_merge.dart';
import 'package:bubble_caption_studio/src/page_collection.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:bubble_caption_studio/src/app_theme.dart';
import 'package:bubble_caption_studio/src/bcs_script_exporter.dart';
import 'package:bubble_caption_studio/src/bubble_painter.dart';
import 'package:bubble_caption_studio/src/font_library.dart';
import 'package:bubble_caption_studio/src/models.dart';
import 'package:bubble_caption_studio/src/project_codec.dart';
import 'package:bubble_caption_studio/src/project_store.dart';
import 'package:bubble_caption_studio/src/text_layout_service.dart';
import 'package:bubble_caption_studio/src/workspace_screen.dart';

class _BulkPaths extends PathProviderPlatform {
  _BulkPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

typedef _Pages = List<Map<String, dynamic>>;

_Pages _copyPages(_Pages pages) =>
    (jsonDecode(jsonEncode(pages)) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _placement(_Pages pages, int page, int bubble) =>
    (pages[page]['placements'] as List)[bubble] as Map<String, dynamic>;

void _setModes(_Pages pages, TextSizeMode mode,
    {Iterable<int>? pageIndices, double? size}) {
  for (final p in pageIndices ?? Iterable<int>.generate(pages.length)) {
    for (final b in (pages[p]['placements'] as List).cast<Map>()) {
      b['textSizeMode'] = mode.name;
      if (size != null) b['fontSize'] = size;
    }
  }
}

class _SettingsHarness {
  _SettingsHarness(this.tester, this.size);
  final WidgetTester tester;
  final Size size;
  Uint8List? otherProjectBefore;
  late String supportPath;
  static const projectId = 'settings-mode-feature';
  bool get portrait => size.width < 1180 && size.height > size.width;

  Finder get canvas => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is PagePainter);
  PagePainter get painter =>
      tester.widget<CustomPaint>(canvas.first).painter! as PagePainter;
  ImagePage get page => painter.page;
  Finder get dialog => find.byType(AlertDialog).last;

  Future<void> pumpUi([int rounds = 3]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> initialize(
      {bool automaticSource = false,
      bool linkedStyles = false,
      bool coldFontOnSecondPage = false,
      AppSettings initialSettings = const AppSettings()}) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousPaths = PathProviderPlatform.instance;
    final temp = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('bcs-bulk-feature-')))!;
    PathProviderPlatform.instance = _BulkPaths(temp.path);
    supportPath = temp.path;
    addTearDown(() async {
      // Unmount and drain native saves before restoring this fixture's paths,
      // including when an assertion aborted the normal dispose path.
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      PathProviderPlatform.instance = previousPaths;
    });
    // This fresh fixture is retained for diagnosis. No user project is touched.
    debugPrint('BULK_FEATURE_FIXTURE=${temp.path} VIEW=$size');
    await tester.runAsync(() async {
      await saveAppSettings(initialSettings);
      final pages = <ImagePage>[];
      for (var p = 0; p < 3; p++) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.grey, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 300);
        picture.dispose();
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final page = ImagePage(
            pageId: 'bulk-page-$p',
            orderRank: p,
            name: '${p + 1}.png',
            bytes: png,
            image: image);
        page.placements = [
          for (var b = 0; b < 2; b++)
            BubblePlacement(
              caption: CaptionLine(
                  speaker: '',
                  text: coldFontOnSecondPage && p == 1 && b == 1
                      ? '漫画文字排版测试，字体需要完整载入'
                      : 'P${p + 1} bubble ${b + 1} complete text',
                  bubbleId: 'p${p + 1}-b${b + 1}'),
              x: 20 + b * 180,
              y: 30,
              width: 150,
              height: b == 0 ? 90 : 60 + p * 12,
              shape: BubbleShape.plainText,
              fontSize: b == 0 ? 34 + p * 14 : (p == 0 ? 34 : 200),
              textSizeMode: b == 0 && !(p == 0 && automaticSource)
                  ? TextSizeMode.fixed
                  : TextSizeMode.fit,
              fontFamily: coldFontOnSecondPage && p == 1 && b == 1
                  ? 'Ma Shan Zheng'
                  : defaultBubbleFontFamily,
              fontColorValue: 0xff123456 + p * 16 + b,
              styleId: linkedStyles ? 'bulk-linked-$p-$b' : null,
            )
        ];
        page.captions = page.placements.map((b) => b.caption).toList();
        pages.add(page);
        await saveLocalProjectImage(projectId, page.pageId, png);
      }
      await saveLocalProjectManifest(projectId, '批量模式真实交互',
          encodeProjectManifest(pages, buildBcsScript(pages)));
      await saveLocalProjectManifest(
          'unopened-other-project',
          'Unopened other project',
          encodeProjectManifest(pages, buildBcsScript(pages)));
      otherProjectBefore =
          await loadLocalProjectManifest('unopened-other-project');
      for (final page in pages) {
        page.dispose();
      }
      // Freeze tests compare actual font metrics before/after user input. Wait
      // for the fixture's one local font rather than measuring fallback glyphs
      // just before the inspector finishes its normal lazy font registration.
      await FontLibrary.instance.load();
      expect(await FontLibrary.instance.getAsset(defaultBubbleFontFamily),
          isNotNull);
    });
    await mount();
  }

  Future<void> mount() async {
    await tester.runAsync(() => tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: WorkspaceScreen(
            projectId: projectId,
            projectName: '批量模式真实交互',
            onExitToProjects: () {}))));
    final deadline = Stopwatch()..start();
    while (canvas.evaluate().isEmpty &&
        deadline.elapsed < const Duration(seconds: 15)) {
      await pumpUi();
    }
    expect(canvas, findsOneWidget);
    await pumpUi();
    expect(tester.takeException(), isNull);
  }

  Future<void> dismissInspector() async {
    if (portrait && find.byType(BottomSheet).evaluate().isNotEmpty) {
      // Opening the footer dialog has scrolled the inspector header offscreen.
      // Dismiss using its visible normal modal barrier, not a hidden close
      // widget nor a Navigator callback that bypasses user input.
      await tester.tapAt(Offset(size.width / 2, 8));
      await pumpUi(6);
      expect(find.byType(BottomSheet), findsNothing);
    }
  }

  Future<void> selectPage(int index) async {
    await dismissInspector();
    if (page.pageId == 'bulk-page-$index') return;
    if (portrait) {
      final nav = find.descendant(
          of: find.byType(NavigationBar), matching: find.text('图片'));
      await tester.tap(nav);
      await pumpUi();
    }
    final label = size.width >= 1180
        ? '${index + 1}.png'
        : '${index + 1}. ${index + 1}.png';
    if (size.width < 1180 && !portrait) {
      final panel = find
          .ancestor(
              of: find.text('图片 · 3 张'), matching: find.byType(ColoredBox))
          .first;
      final scroll =
          find.descendant(of: panel, matching: find.byType(Scrollable));
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(0, 600));
      await pumpUi(1);
      await tester.scrollUntilVisible(find.text(label), 60, scrollable: scroll);
    }
    final item = find
        .ancestor(of: find.text(label).first, matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(item);
    await pumpUi(1);
    await tester.tap(item);
    await pumpUi();
    expect(page.pageId, 'bulk-page-$index');
  }

  Map<String, dynamic> currentRecord() {
    final json = jsonDecode(utf8.decode(encodeProjectEdits([page], '')))
        as Map<String, dynamic>;
    return Map<String, dynamic>.from((json['pages'] as List).single as Map);
  }

  Future<_Pages> snapshot() async {
    final result = <Map<String, dynamic>>[];
    for (var p = 0; p < 3; p++) {
      await selectPage(p);
      result.add(currentRecord());
    }
    return result;
  }

  double visibleSize(BubblePlacement bubble) {
    final layout = const TextLayoutService().layout(bubble);
    final result = layout.effectiveFontSize;
    layout.dispose();
    return result;
  }

  Future<List<List<double>>> visibleSizes() async {
    final sizes = <List<double>>[];
    for (var p = 0; p < 3; p++) {
      await selectPage(p);
      sizes.add(page.placements.map(visibleSize).toList());
    }
    return sizes;
  }

  Future<void> openBulk({int sourcePage = 0}) async {
    await selectPage(sourcePage);
    final dimensions = tester.getSize(canvas.first);
    await tester.tapAt(tester.getTopLeft(canvas.first) +
        Offset(dimensions.width * 80 / 400, dimensions.height * 65 / 300));
    await pumpUi();
    expect(painter.selectedIndex, 0);
    if (portrait) {
      await tester.tap(find.byTooltip('元素属性'));
      await pumpUi();
    }
    final open = find.text('选择属性并应用到全部');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await pumpUi();
    expect(find.byType(AlertDialog), findsOneWidget);
    final scope = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('bulk-style-scope')));
    expect(scope.value, 'all', reason: '默认必须明确跨全部图片，不能悄悄只改当前图片');
    expect(scope.items!.map((item) => item.value).toSet(),
        {'all', 'page', 'pages', 'selected'});
  }

  Finder property(String name) =>
      find.byKey(ValueKey('bulk-style-property-$name'));

  Future<void> reveal(Finder target) async {
    final scroll =
        find.descendant(of: dialog, matching: find.byType(Scrollable)).last;
    if (target.evaluate().isEmpty) {
      // ListView lazily discards offscreen tiles. Return to its start first so
      // a later mode toggle is reachable after inspecting a lower property.
      await tester.drag(scroll, const Offset(0, 900));
      await pumpUi(1);
    }
    await tester.scrollUntilVisible(target, 100, scrollable: scroll);
    await tester.ensureVisible(target);
    // A jump changes scroll offset before the following frame lays out its
    // children; tapping with the old rectangle would hit the dialog padding.
    await pumpUi(1);
  }

  Future<void> toggleProperty(String name) async {
    final item = property(name);
    await reveal(item);
    expect(tester.widget<CheckboxListTile>(item).onChanged, isNotNull);
    await tester.tap(item);
    await pumpUi();
  }

  Future<void> chooseMode(TextSizeMode mode) async {
    await reveal(property('textSizeMode'));
    if (!tester.widget<CheckboxListTile>(property('textSizeMode')).value!) {
      await toggleProperty('textSizeMode');
    }
    final picker = find.byKey(const ValueKey('bulk-style-mode-selector'));
    await reveal(picker);
    expect(tester.widget<SegmentedButton<TextSizeMode>>(picker).selected,
        {TextSizeMode.fit},
        reason: '新弹窗的模式草稿从自动挡开始，不从固定34来源隐式复制');
    if (mode == TextSizeMode.fixed) {
      final label = find.descendant(of: picker, matching: find.text('手动挡'));
      expect(label.hitTestable(), findsOneWidget,
          reason: '必须真实显示并可点击独立模式，不能直接调用回调代替用户操作');
      await tester.tap(label);
      await pumpUi();
    }
    expect(
        tester.widget<SegmentedButton<TextSizeMode>>(picker).selected, {mode});
  }

  Future<void> chooseScope(String scope) async {
    final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('bulk-style-scope')));
    final target = dropdown.items!.singleWhere((item) => item.value == scope);
    final label = (target.child as Text).data!;
    await tester.tap(find.byKey(const ValueKey('bulk-style-scope')));
    await pumpUi();
    // The DropdownMenuItem wrapper is not itself on the pointer hit-test path;
    // tap its visible menu label rather than suppressing a missed-tap warning.
    final item = find.text(label).hitTestable().last;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await pumpUi();
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('bulk-style-scope')))
            .value,
        scope);
  }

  Future<void> finish({bool cancel = false}) async {
    final button = find.descendant(
        of: dialog,
        matching: cancel
            ? find.widgetWithText(TextButton, '取消')
            : find.widgetWithText(FilledButton, '应用'));
    await tester.tap(button);
    await pumpUi();
    expect(find.byType(AlertDialog), findsNothing);
    await dismissInspector();
    expect(tester.takeException(), isNull);
  }

  Future<void> undoOrRedo(String prefix) async {
    await dismissInspector();
    final button = find.byWidgetPredicate((widget) =>
        widget is IconButton && (widget.tooltip?.startsWith(prefix) ?? false));
    expect(button, findsWidgets);
    expect(tester.widget<IconButton>(button.first).onPressed, isNotNull);
    await tester.tap(button.first);
    await pumpUi();
  }

  Future<Map<String, dynamic>> waitForCommit(_Pages expected) async {
    await dismissInspector();
    // Timers must advance AND native I/O must finish. A fixed fake-pump budget
    // alone previously produced false "autosave lost data" failures.
    await tester.pump(const Duration(seconds: 2));
    final deadline = Stopwatch()..start();
    Map<String, dynamic>? committed;
    while (deadline.elapsed < const Duration(seconds: 15)) {
      await pumpUi(1);
      final bytes = await tester
          .runAsync<Uint8List?>(() => loadLocalProjectEdits(projectId));
      if (bytes == null) continue;
      final saved = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (equals(expected).matches(saved['pages'], <dynamic, dynamic>{})) {
        committed = saved;
        break;
      }
    }
    expect(committed, isNotNull, reason: '必须等磁盘确实提交完整跨页模式与字号');
    return committed!;
  }

  Future<void> saveAndReopen(_Pages expected) async {
    await waitForCommit(expected);
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    await pumpUi();
    await mount();
    expect(await snapshot(), expected, reason: '关闭工作台重新打开后，全部图片和完整正文必须保留');
  }

  Future<void> openSettings() async {
    await dismissInspector();
    if (size.width >= 1180) {
      await tester.tap(find.byTooltip('设置'));
    } else {
      await tester.tap(find.byTooltip('更多操作'));
      await pumpUi();
      await tester.ensureVisible(find.text('设置').last);
      await pumpUi(1);
      await tester.tap(find.text('设置').hitTestable().last);
    }
    await pumpUi();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-default-text-size-mode')),
        findsOneWidget);
  }

  Future<void> revealSetting(Finder item) async {
    final scroll =
        find.descendant(of: dialog, matching: find.byType(Scrollable)).first;
    await tester.ensureVisible(item);
    await pumpUi(1);
    if (item.hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(item, 80, scrollable: scroll);
      await pumpUi(1);
    }
    expect(item.hitTestable(), findsWidgets);
  }

  Future<void> settingMode(TextSizeMode mode, {double? manualSize}) async {
    final picker =
        find.byKey(const ValueKey('settings-default-text-size-mode'));
    await revealSetting(picker);
    final label = find.descendant(
        of: picker,
        matching: find.text(mode == TextSizeMode.fit ? '自动挡' : '手动挡'));
    await tester.tap(label);
    await pumpUi();
    expect(
        tester.widget<SegmentedButton<TextSizeMode>>(picker).selected, {mode});
    if (manualSize != null) {
      final input =
          find.byKey(const ValueKey('settings-default-manual-font-size'));
      await revealSetting(input);
      await tester.enterText(input, '$manualSize');
      await pumpUi();
    }
  }

  Future<void> applyToCurrent() async {
    final item =
        find.byKey(const ValueKey('settings-apply-text-size-mode-to-project'));
    await revealSetting(item);
    expect(tester.widget<CheckboxListTile>(item).value, isFalse,
        reason: '全球默认设置不得默默改写当前旧工程');
    await tester.tap(item);
    await pumpUi();
  }

  Future<void> finishSettings({bool cancel = false}) async {
    final button = cancel
        ? find.descendant(
            of: dialog, matching: find.widgetWithText(TextButton, '取消'))
        : find.byKey(const ValueKey('settings-save'));
    await tester.tap(button);
    await pumpUi(5);
    final deadline = Stopwatch()..start();
    while (find.byType(AlertDialog).evaluate().isNotEmpty &&
        deadline.elapsed < const Duration(seconds: 5)) {
      await pumpUi(2);
    }
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      final renderedTexts = find
          .descendant(of: dialog, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .join(' | ');
      debugPrint('SETTINGS_STILL_OPEN=$renderedTexts');
      final saveButton = tester
          .widget<FilledButton>(find.byKey(const ValueKey('settings-save')));
      debugPrint('SETTINGS_SAVE_BUTTON=${saveButton.toStringDeep()}');
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }

  Future<void> expectOtherUntouched() async {
    final other = await tester
        .runAsync(() => loadLocalProjectManifest('unopened-other-project'));
    expect(other, otherProjectBefore, reason: '当前项目操作不扫描或改写其他项目');
  }

  Future<void> addObject({required bool plain}) async {
    await dismissInspector();
    expect(size.width >= 1180, isTrue);
    final compact = find.byTooltip('添加气泡或文字');
    if (compact.evaluate().isNotEmpty) {
      await tester.tap(compact);
      await pumpUi();
      await tester.tap(find.text(plain ? '添加文字' : '添加气泡').hitTestable().last);
    } else if (plain) {
      await tester.tap(find.byTooltip('添加文字').first);
    } else {
      await tester.tap(find.text('添加气泡').hitTestable().first);
    }
    await pumpUi();
  }

  Future<void> dispose() async {
    await dismissInspector();
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    await pumpUi();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(tester.takeException(), isNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'BCS Test',
        packageName: 'bcs.settings.test',
        version: '1.3.2',
        buildNumber: '42',
        buildSignature: 'test');
  });

  test('settings defaults migrate safely and reject invalid enum/font values',
      () {
    final old = AppSettings.fromJson({'exportDirectory': 'D:/Pictures'});
    expect(old.defaultTextSizeMode, TextSizeMode.fit);
    expect(old.defaultManualFontSize, 34);
    expect(old.exportDirectory, 'D:/Pictures');
    for (final value in [null, '', 'unknown', 0, true]) {
      expect(
          AppSettings.fromJson({'defaultTextSizeMode': value})
              .defaultTextSizeMode,
          TextSizeMode.fit);
    }
    for (final value in [
      null,
      'bad',
      -1,
      0,
      7,
      201,
      double.nan,
      double.infinity
    ]) {
      expect(
          AppSettings.fromJson({'defaultManualFontSize': value})
              .defaultManualFontSize,
          34,
          reason: 'invalid manual size $value must not propagate');
    }
    expect(
        AppSettings.fromJson({'defaultManualFontSize': 8})
            .defaultManualFontSize,
        8);
    expect(
        AppSettings.fromJson({'defaultManualFontSize': 200})
            .defaultManualFontSize,
        200);
  });

  test('settings mode and manual size round trip and disk persistence',
      () async {
    final previous = PathProviderPlatform.instance;
    final temp = await Directory.systemTemp.createTemp('bcs-settings-json-');
    PathProviderPlatform.instance = _BulkPaths(temp.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    final settings = const AppSettings(
        exportDirectory: 'D:/output',
        askExportLocation: false,
        numberedExportNames: false,
        languageCode: 'en',
        defaultTextSizeMode: TextSizeMode.fixed,
        defaultManualFontSize: 61.5);
    final decoded =
        AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
    expect(decoded.toJson(), settings.toJson());
    expect(
        decoded
            .copyWith(defaultTextSizeMode: TextSizeMode.fit)
            .defaultManualFontSize,
        61.5);
    await saveAppSettings(settings);
    expect((await loadAppSettings()).toJson(), settings.toJson());
  });

  test(
      'new script defaults follow settings while explicit BCS modes take priority',
      () {
    final parsed = parseCaptionScript('''@格式=BCS顺序字幕脚本
@版本=3
@坐标单位=px
[图片 1]
@原文件名=1.png
@原图尺寸=400x300

@气泡ID=p1-b1
@矩形=20,20,140,80
No explicit style

@气泡ID=p1-b2
@矩形=180,20,140,80
@字号=72
@字号模式=自动适配
Explicit automatic

@气泡ID=p1-b3
@矩形=20,140,140,80
@字号=28
@字号模式=固定
Explicit manual
''');
    expect(parsed.sections, hasLength(1));
    final result = const LayoutEngine().arrange(parsed.sections.single.captions,
        imageWidth: 400,
        imageHeight: 300,
        defaultTextSizeMode: TextSizeMode.fixed,
        defaultManualFontSize: 59);
    expect(result.map((b) => b.textSizeMode),
        [TextSizeMode.fixed, TextSizeMode.fit, TextSizeMode.fixed]);
    expect(result.map((b) => b.fontSize), [59, 72, 28]);
    final automatic = const LayoutEngine().arrange(
        [const CaptionLine(speaker: '', text: 'New', bubbleId: 'new')],
        imageWidth: 400,
        imageHeight: 300,
        defaultTextSizeMode: TextSizeMode.fit,
        defaultManualFontSize: 59).single;
    expect(automatic.textSizeMode, TextSizeMode.fit);
    expect(automatic.fontSize, 200);
  });

  test('geometry-only script preserves existing mode and raw size', () {
    const existing = BubblePlacement(
        caption: CaptionLine(speaker: '', text: 'Before', bubbleId: 'p1-b1'),
        x: 10,
        y: 20,
        width: 120,
        height: 80,
        textSizeMode: TextSizeMode.fixed,
        fontSize: 47);
    const incoming = CaptionLine(
        speaker: '',
        text: 'After',
        bubbleId: 'p1-b1',
        layout: CaptionLayoutSpec(x: 30, y: 40, width: 140, height: 90));
    final generated = const LayoutEngine().arrange([incoming],
        imageWidth: 400,
        imageHeight: 300,
        defaultTextSizeMode: TextSizeMode.fit,
        defaultManualFontSize: 34);
    final next =
        preserveEditedPlacements([existing], generated, [incoming]).single;
    expect(next.textSizeMode, TextSizeMode.fixed);
    expect(next.fontSize, 47);
    expect(next.caption.text, 'After');
    expect([next.x, next.y, next.width, next.height], [30, 40, 140, 90]);
    final merged =
        mergeScriptPlacements([existing], generated, [existing.caption]).single;
    expect(merged.textSizeMode, TextSizeMode.fixed);
    expect(merged.fontSize, 47);
  });

  testWidgets(
      'cancel and default-only settings leave current project and history unchanged',
      (tester) async {
    final h = _SettingsHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await h.openSettings();
    await h.settingMode(TextSizeMode.fixed, manualSize: 61.5);
    await h.applyToCurrent();
    await h.finishSettings(cancel: true);
    expect((await tester.runAsync(loadAppSettings))!.defaultTextSizeMode,
        TextSizeMode.fit);
    expect(await h.snapshot(), original);
    await h.openSettings();
    await h.settingMode(TextSizeMode.fixed, manualSize: 61.5);
    await h.finishSettings();
    final saved = (await tester.runAsync(loadAppSettings))!;
    expect(saved.defaultTextSizeMode, TextSizeMode.fixed);
    expect(saved.defaultManualFontSize, 61.5);
    expect(await h.snapshot(), original);
    final undo =
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '撤销');
    expect(undo, findsWidgets);
    expect(tester.widget<IconButton>(undo.first).onPressed, isNull,
        reason: '仅设置默认值，不应新增项目撤销项');
    await h.expectOtherUntouched();
    await h.dispose();
  });

  testWidgets(
      'settings automatic applies all current pages in one undo transaction and survives reopen',
      (tester) async {
    final h = _SettingsHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await h.openSettings();
    // Current default already automatic: applying is an independent explicit action.
    await h.applyToCurrent();
    await h.finishSettings();
    final expected = _copyPages(original);
    _setModes(expected, TextSizeMode.fit, size: 200);
    expect(await h.snapshot(), expected);
    await h.undoOrRedo('撤销');
    expect(await h.snapshot(), original);
    await h.undoOrRedo('重做');
    expect(await h.snapshot(), expected);
    await h.saveAndReopen(expected);
    await h.expectOtherUntouched();
    await h.dispose();
  });

  testWidgets(
      'settings manual freezes each auto size and retains existing manual across all pages',
      (tester) async {
    final h = _SettingsHarness(tester, const Size(1440, 1000));
    await h.initialize(linkedStyles: true, coldFontOnSecondPage: true);
    final original = await h.snapshot();
    final visible = await h.visibleSizes();
    expect(FontLibrary.instance.isRegistered('Ma Shan Zheng'), isFalse,
        reason: '夹具未访问对象使用的冷内置字体必须仍未注册');
    await h.openSettings();
    await h.settingMode(TextSizeMode.fixed, manualSize: 61.5);
    await h.applyToCurrent();
    await h.finishSettings();
    final freezeDeadline = Stopwatch()..start();
    while (h.page.placements.any((b) => b.textSizeMode != TextSizeMode.fixed) &&
        freezeDeadline.elapsed < const Duration(seconds: 15)) {
      await h.pumpUi(2);
    }
    expect(FontLibrary.instance.isRegistered('Ma Shan Zheng'), isTrue,
        reason: '设置批量手动冻结必须先加载未访问对象的真实字体');
    await h.selectPage(1);
    final fallbackSize = visible[1][1];
    visible[1][1] = h.visibleSize(h.page.placements[1].copyWith(
        textSizeMode: TextSizeMode.fit,
        fontSize: (_placement(original, 1, 1)['fontSize'] as num).toDouble()));
    debugPrint(
        'SETTINGS_COLD_FONT_FALLBACK_SIZE=$fallbackSize REAL_SIZE=${visible[1][1]}');
    final expected = _copyPages(original);
    for (var p = 0; p < expected.length; p++) {
      for (var b = 0; b < 2; b++) {
        final item = _placement(expected, p, b);
        if (item['textSizeMode'] == 'fit') {
          item['textSizeMode'] = 'fixed';
          item['fontSize'] = visible[p][b];
          item.remove('styleId');
        }
      }
    }
    expect(await h.snapshot(), expected,
        reason: '默认61.5仅供新建，当前自动对象固定各自可见字号，已有手动值与未变化关联保持');
    await h.undoOrRedo('撤销');
    expect(await h.snapshot(), original);
    await h.undoOrRedo('重做');
    expect(await h.snapshot(), expected);
    await h.saveAndReopen(expected);
    await h.expectOtherUntouched();
    await h.dispose();
  });

  testWidgets(
      'new bubble and plain text use persistent manual default then auto 200 after switch',
      (tester) async {
    final h = _SettingsHarness(tester, const Size(1440, 1000));
    await h.initialize(
        initialSettings: const AppSettings(
            defaultTextSizeMode: TextSizeMode.fixed,
            defaultManualFontSize: 61.5));
    final original = await h.snapshot();
    await h.selectPage(0);
    await h.addObject(plain: false);
    expect(h.page.placements.last.textSizeMode, TextSizeMode.fixed);
    expect(h.page.placements.last.fontSize, 61.5);
    expect(h.page.placements.last.shape, BubbleShape.ellipse);
    final afterBubble = await h.snapshot();
    await h.waitForCommit(afterBubble);
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    await h.pumpUi();
    await h.mount();
    // The codec adds known-font identity metadata during native reload. The
    // exact mode, raw size, complete text and all geometry must still match.
    final normalized = _copyPages(afterBubble);
    final record = FontLibrary.instance.recordFor(defaultBubbleFontFamily)!;
    _placement(normalized, 0, 2)
      ..['fontAssetId'] = record.id
      ..['fontDisplayName'] = record.displayName;
    expect(await h.snapshot(), normalized);
    await h.selectPage(0);
    await h.addObject(plain: true);
    expect(h.page.placements.last.textSizeMode, TextSizeMode.fixed);
    expect(h.page.placements.last.fontSize, 61.5);
    expect(h.page.placements.last.shape, BubbleShape.plainText);
    await h.openSettings();
    await h.settingMode(TextSizeMode.fit);
    await h.finishSettings();
    await h.addObject(plain: false);
    expect(h.page.placements.last.textSizeMode, TextSizeMode.fit);
    expect(h.page.placements.last.fontSize, 200);
    expect(h.page.placements[0].textSizeMode.name,
        _placement(original, 0, 0)['textSizeMode']);
    expect(
        h.page.placements[0].fontSize, _placement(original, 0, 0)['fontSize']);
    await h.expectOtherUntouched();
    await h.dispose();
  });

  testWidgets(
      'settings save failure remains visible without changing project and can retry',
      (tester) async {
    final h = _SettingsHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await h.openSettings();
    await h.settingMode(TextSizeMode.fixed, manualSize: 45);
    await h.applyToCurrent();
    final settingsPath =
        '${h.supportPath}${Platform.pathSeparator}settings.json';
    await tester.runAsync(() async {
      await File(settingsPath).rename('$settingsPath.pristine');
      await Directory(settingsPath).create();
    });
    await tester.tap(find.byKey(const ValueKey('settings-save')));
    final deadline = Stopwatch()..start();
    final error = find.byKey(const ValueKey('settings-save-error'));
    while (error.evaluate().isEmpty &&
        deadline.elapsed < const Duration(seconds: 5)) {
      await h.pumpUi(2);
    }
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(error.hitTestable(), findsOneWidget);
    expect(tester.widget<Text>(error).data, contains('保存设置失败'));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('settings-save')))
            .onPressed,
        isNotNull);
    await tester.runAsync(() async {
      final saved = AppSettings.fromJson(
          jsonDecode(await File('$settingsPath.pristine').readAsString()));
      expect(saved.defaultTextSizeMode, TextSizeMode.fit);
      expect(await Directory(settingsPath).exists(), isTrue);
      await Directory(settingsPath).delete(); // Empty fixture obstruction only.
      await File('$settingsPath.pristine').rename(settingsPath);
    });
    // The current page is inspectable behind the retained dialog without navigation.
    expect(h.currentRecord(), original.last,
        reason:
            'Failed settings save must not execute the checked project mutation');
    await h.finishSettings();
    final after = await h.snapshot();
    expect(
        after.every((page) => (page['placements'] as List)
            .every((b) => b['textSizeMode'] == 'fixed')),
        isTrue);
    expect((await tester.runAsync(loadAppSettings))!.defaultTextSizeMode,
        TextSizeMode.fixed);
    await h.expectOtherUntouched();
    await h.dispose();
  });

  testWidgets(
      'invalid manual input blocks saving and continuous corrected input retains focus',
      (tester) async {
    final h = _SettingsHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await h.openSettings();
    await h.settingMode(TextSizeMode.fixed);
    final input =
        find.byKey(const ValueKey('settings-default-manual-font-size'));
    await h.revealSetting(input);
    for (final value in ['201', 'NaN', '0']) {
      await tester.enterText(input, value);
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await h.pumpUi();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('请输入 8–200 之间的有效字号'), findsOneWidget);
      expect((await tester.runAsync(loadAppSettings))!.defaultTextSizeMode,
          TextSizeMode.fit);
    }
    await tester.tap(input);
    await tester.enterText(input, '6');
    await h.pumpUi();
    final editable =
        find.descendant(of: input, matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '61.5', selection: TextSelection.collapsed(offset: 4)));
    await h.pumpUi();
    expect(tester.widget<EditableText>(editable).controller.text, '61.5');
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue,
        reason:
            'onChanged must not replace the text field or force a second click');
    await h.finishSettings();
    expect(
        (await tester.runAsync(loadAppSettings))!.defaultManualFontSize, 61.5);
    expect(await h.snapshot(), original);
    await h.dispose();
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets('settings mode and size accessible at simulated $size',
        (tester) async {
      final h = _SettingsHarness(tester, size);
      await h.initialize();
      final original = await h.snapshot();
      await h.openSettings();
      await h.settingMode(TextSizeMode.fixed, manualSize: 45);
      await h.finishSettings();
      final saved = (await tester.runAsync(loadAppSettings))!;
      expect(saved.defaultTextSizeMode, TextSizeMode.fixed);
      expect(saved.defaultManualFontSize, 45);
      expect(await h.snapshot(), original);
      await h.expectOtherUntouched();
      await h.dispose();
    });
  }
}
