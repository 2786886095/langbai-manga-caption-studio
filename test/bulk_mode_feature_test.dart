// Simulated desktop/mobile widget coverage, not Android/iOS device acceptance.
// Keep this test outside the candidate until the parent copies it into test/.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _BulkHarness {
  _BulkHarness(this.tester, this.size);
  final WidgetTester tester;
  final Size size;
  static const projectId = 'bulk-mode-feature';
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
      {bool automaticSource = false, bool linkedStyles = false}) async {
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
                  text: 'P${p + 1} bubble ${b + 1} complete text',
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

  for (final size in const [
    Size(1440, 1000),
    Size(390, 844),
    Size(844, 390),
  ]) {
    testWidgets('independent auto all-pages undo redo and reopen at $size',
        (tester) async {
      final h = _BulkHarness(tester, size);
      await h.initialize();
      final original = await h.snapshot();
      expect(_placement(original, 0, 0)['textSizeMode'], 'fixed');
      expect(_placement(original, 0, 0)['fontSize'], 34);
      await h.openBulk();
      await tester.tap(find.descendant(
          of: h.dialog, matching: find.widgetWithText(TextButton, '全选')));
      await h.pumpUi();
      await h.reveal(h.property('fontSize'));
      expect(tester.widget<CheckboxListTile>(h.property('fontSize')).value,
          isFalse,
          reason: '全选不能绕过自动挡对固定字号的排斥');
      await tester.tap(find.descendant(
          of: h.dialog, matching: find.widgetWithText(TextButton, '清空')));
      await h.pumpUi();
      await h.chooseMode(TextSizeMode.fit);
      await h.reveal(h.property('fontSize'));
      final fontSize = tester.widget<CheckboxListTile>(h.property('fontSize'));
      expect(fontSize.value, isFalse);
      expect(fontSize.onChanged, isNull, reason: '自动挡不允许复制来源固定34的字号覆盖200上限');
      await h.finish();
      final expected = _copyPages(original);
      _setModes(expected, TextSizeMode.fit, size: 200);
      expect(await h.snapshot(), expected);
      await h.undoOrRedo('撤销');
      expect(await h.snapshot(), original, reason: '一条项目级撤销必须同时恢复全部图片，不能只撤当前页');
      await h.undoOrRedo('重做');
      expect(await h.snapshot(), expected);
      await h.saveAndReopen(expected);
      await h.dispose();
    });

    testWidgets('manual freezes each auto size and current-page scope at $size',
        (tester) async {
      final h = _BulkHarness(tester, size);
      await h.initialize();
      final original = await h.snapshot();
      final visible = await h.visibleSizes();
      expect(visible[0][1], lessThan(200));
      expect(visible[0][1], isNot(closeTo(34, .001)),
          reason: '夹具必须区别逐目标实际字号与源手动34');
      await h.openBulk();
      await h.chooseMode(TextSizeMode.fixed);
      await h.chooseScope('page');
      await h.finish();
      final expected = _copyPages(original);
      _placement(expected, 0, 1)
        ..['textSizeMode'] = 'fixed'
        ..['fontSize'] = visible[0][1];
      expect(await h.snapshot(), expected,
          reason: '已有手动34不改，自动对象冻结各自实际值，其他图片严格隔离');
      await h.undoOrRedo('撤销');
      expect(await h.snapshot(), original);
      await h.dispose();
    });
  }

  testWidgets('cancel and unchecked mode preserve mixed modes and sizes',
      (tester) async {
    final h = _BulkHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fixed);
    await h.toggleProperty('fontSize');
    await h.finish(cancel: true);
    expect(await h.snapshot(), original);
    await h.openBulk();
    await h.toggleProperty('fontSize');
    await h.reveal(h.property('textSizeMode'));
    expect(tester.widget<CheckboxListTile>(h.property('textSizeMode')).value,
        isFalse);
    await h.finish();
    final expected = _copyPages(original);
    for (var p = 0; p < expected.length; p++) {
      for (final b in (expected[p]['placements'] as List).cast<Map>()) {
        if (b['textSizeMode'] == 'fixed') b['fontSize'] = 34.0;
      }
    }
    expect(await h.snapshot(), expected,
        reason: '只勾字号仅改手动对象；自动对象原字段不变，渲染仍采用全局200上限');
    await h.undoOrRedo('撤销');
    expect(await h.snapshot(), original);
    await h.dispose();
  });

  testWidgets('manual mode alone freezes mixed targets across all pages',
      (tester) async {
    final h = _BulkHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    final visible = await h.visibleSizes();
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fixed);
    await h.finish();
    final expected = _copyPages(original);
    for (var p = 0; p < expected.length; p++) {
      for (var b = 0; b < 2; b++) {
        final target = _placement(expected, p, b);
        if (target['textSizeMode'] == 'fit') {
          target['fontSize'] = visible[p][b];
        }
        target['textSizeMode'] = 'fixed';
      }
    }
    expect(await h.snapshot(), expected,
        reason: '模式草稿与源无关，各页手动原值保留，自动对象不会跳到raw200');
    await h.saveAndReopen(expected);
    await h.dispose();
  });

  testWidgets('mode plus size copies automatic source visible size not raw200',
      (tester) async {
    final h = _BulkHarness(tester, const Size(1440, 1000));
    await h.initialize(automaticSource: true);
    final original = await h.snapshot();
    await h.selectPage(0);
    final sourceSize = h.visibleSize(h.page.placements.first);
    expect(sourceSize, inInclusiveRange(8, 199.999));
    expect(sourceSize, isNot(closeTo(34, .001)));
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fixed);
    await h.toggleProperty('fontSize');
    await h.finish();
    final expected = _copyPages(original);
    _setModes(expected, TextSizeMode.fixed, size: sourceSize);
    expect(await h.snapshot(), expected);
    await h.undoOrRedo('撤销');
    expect(await h.snapshot(), original);
    await h.dispose();
  });

  testWidgets('custom pages scope changes chosen pages but not middle page',
      (tester) async {
    final h = _BulkHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fit);
    await h.chooseScope('pages');
    await tester.tap(find.descendant(
        of: h.dialog, matching: find.textContaining('选择图片（已选')));
    await h.pumpUi();
    final chooser = find.byType(AlertDialog).last;
    final third = find.descendant(
        of: chooser,
        matching: find.widgetWithText(CheckboxListTile, '3. 3.png'));
    await tester.tap(third);
    await h.pumpUi();
    await tester.tap(find.descendant(
        of: chooser, matching: find.widgetWithText(FilledButton, '确认图片')));
    await h.pumpUi();
    await h.finish();
    final expected = _copyPages(original);
    _setModes(expected, TextSizeMode.fit, pageIndices: [0, 2], size: 200);
    expect(await h.snapshot(), expected);
    await h.dispose();
  });

  testWidgets('selected scope changes only checked chapter text objects',
      (tester) async {
    final h = _BulkHarness(tester, const Size(1440, 1000));
    await h.initialize();
    final original = await h.snapshot();
    await tester.tap(find.byTooltip('章节文本 / 多选对象'));
    await h.pumpUi();
    final selectedText =
        find.widgetWithText(CheckboxListTile, '1 · P1 bubble 2 complete text');
    await tester.ensureVisible(selectedText);
    await tester.tap(selectedText);
    await h.pumpUi();
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fit);
    await h.chooseScope('selected');
    await h.finish();
    final expected = _copyPages(original);
    _placement(expected, 0, 1)
      ..['textSizeMode'] = 'fit'
      ..['fontSize'] = 200.0;
    expect(await h.snapshot(), expected, reason: '勾选对象可以独立批量改模式，未勾选源与其他页不改变');
    await h.dispose();
  });

  testWidgets('repeated auto no-op preserves links revision and one undo',
      (tester) async {
    final h = _BulkHarness(tester, const Size(1440, 1000));
    await h.initialize(linkedStyles: true);
    final original = await h.snapshot();
    final untouchedLink = _placement(original, 2, 1)['styleId'];
    expect(untouchedLink, isNotNull);
    expect(_placement(original, 2, 1)['textSizeMode'], 'fit');
    expect(_placement(original, 2, 1)['fontSize'], 200);
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fit);
    await h.finish();
    final first = await h.snapshot();
    for (var p = 0; p < first.length; p++) {
      for (var b = 0; b < 2; b++) {
        expect(_placement(first, p, b)['textSizeMode'], 'fit');
        expect(_placement(first, p, b)['fontSize'], 200);
      }
    }
    expect(_placement(first, 0, 0).containsKey('styleId'), isFalse,
        reason: '真实改变源的模式后应解除关联，避免污染共享样式');
    expect(_placement(first, 2, 1)['styleId'], untouchedLink,
        reason: '已是auto200的对象没有变化，不能解除关联');
    final savedBefore = await h.waitForCommit(first);
    expect(savedBefore['revision'], isA<int>());
    await h.openBulk();
    await h.chooseMode(TextSizeMode.fit);
    await h.finish();
    expect(await h.snapshot(), first);
    // Drive both the save debounce and real IO for a bounded period. The whole
    // persisted record (including revision/savedAt) must remain the same.
    await tester.pump(const Duration(seconds: 2));
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 1)) {
      await h.pumpUi(1);
      final bytes = await tester.runAsync<Uint8List?>(
          () => loadLocalProjectEdits(_BulkHarness.projectId));
      expect(bytes, isNotNull);
      expect(jsonDecode(utf8.decode(bytes!)), savedBefore,
          reason: '重复相同批量操作不应修改磁盘revision或触发新保存');
    }
    await h.undoOrRedo('撤销');
    expect(await h.snapshot(), original,
        reason: '连续应用相同自动模式，撤销一次必须直接恢复最初mixed状态');
    await h.dispose();
  });
}
