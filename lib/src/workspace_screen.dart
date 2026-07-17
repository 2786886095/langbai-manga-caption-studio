import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'bubble_painter.dart';
import 'exporter.dart';
import 'file_gateway.dart';
import 'layout_engine.dart';
import 'image_decoder.dart';
import 'models.dart';
import 'page_collection.dart';
import 'project_codec.dart';
import 'project_store.dart';
import 'script_parser.dart';
import 'settings_dialog.dart';
import 'text_context_menu.dart';

class _PageEditState {
  _PageEditState({
    required this.captions,
    required this.placements,
    required this.approved,
  });

  factory _PageEditState.capture(ImagePage page) {
    final captions =
        page.captions.map((caption) => caption.copyWith()).toList();
    return _PageEditState(
      captions: captions,
      placements: [
        for (var i = 0; i < page.placements.length; i++)
          page.placements[i].copyWith(caption: captions[i]),
      ],
      approved: page.approved,
    );
  }

  final List<CaptionLine> captions;
  final List<BubblePlacement> placements;
  final bool approved;

  void restore(ImagePage page) {
    final restoredCaptions =
        captions.map((caption) => caption.copyWith()).toList();
    page
      ..captions = restoredCaptions
      ..placements = [
        for (var i = 0; i < placements.length; i++)
          placements[i].copyWith(caption: restoredCaptions[i]),
      ]
      ..approved = approved;
  }
}

class _ProjectSnapshot {
  _ProjectSnapshot({
    required this.pages,
    required this.selectedPage,
    required this.selectedBubble,
  });

  factory _ProjectSnapshot.capture(
    List<ImagePage> pages,
    int selectedPage,
    int selectedBubble,
  ) =>
      _ProjectSnapshot(
        pages: pages.map(_PageEditState.capture).toList(),
        selectedPage: selectedPage,
        selectedBubble: selectedBubble,
      );

  final List<_PageEditState> pages;
  final int selectedPage;
  final int selectedBubble;
}

enum _DragMode {
  move,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

enum _ExistingImageChoice { overwrite, overwriteAll, skip, cancel }

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.onExitToProjects,
  });

  final String projectId;
  final String projectName;
  final VoidCallback onExitToProjects;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _engine = const LayoutEngine();
  final _script = TextEditingController();
  final List<ImagePage> _pages = [];
  final List<_ProjectSnapshot> _undoStack = [];
  final List<_ProjectSnapshot> _redoStack = [];
  int _selectedPage = 0;
  int _selectedBubble = 0;
  bool _processing = true;
  bool _exporting = false;
  bool _saving = false;
  bool _dirty = false;
  bool _isDemoProject = false;
  bool _showRendered = true;
  bool _inspectorVisible = true;
  String _projectName = '未命名工程';
  double _zoom = 1;
  _DragMode? _dragMode;
  _DragMode? _hoverMode;
  bool _selectionVisible = true;
  bool _structureDirty = false;
  Timer? _autosaveTimer;
  AppSettings _settings = const AppSettings();
  final List<String> _importedFonts = [];
  final Map<String, Uint8List> _fontBytes = {};
  String? _projectThumbnailBase64;

  ImagePage? get _page =>
      _pages.isEmpty ? null : _pages[_selectedPage.clamp(0, _pages.length - 1)];
  BubblePlacement? get _bubble {
    final page = _page;
    if (page == null || page.placements.isEmpty) return null;
    return page.placements[_selectedBubble.clamp(
      0,
      page.placements.length - 1,
    )];
  }

  @override
  void initState() {
    super.initState();
    _projectName = widget.projectName;
    _loadStoredProject();
    _loadSettingsAndConfigureAutosave();
  }

  Future<void> _loadSettingsAndConfigureAutosave() async {
    _settings = await loadAppSettings();
    _configureAutosave();
    if (mounted) setState(() {});
  }

  void _configureAutosave() {
    _autosaveTimer?.cancel();
    if (!_settings.autoSave) return;
    _autosaveTimer = Timer.periodic(
      Duration(seconds: _settings.autoSaveSeconds),
      (_) {
        if (_dirty && !_saving && !_processing) {
          unawaited(_persistLocalProject());
        }
      },
    );
  }

  Future<void> _showSettings() async {
    final settings = await showAppSettingsDialog(context, _settings);
    if (settings == null || !mounted) return;
    setState(() => _settings = settings);
    _configureAutosave();
  }

  Future<void> _importFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final base = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final family =
        'Imported_${base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}_${bytes.length}';
    if (!_importedFonts.contains(family)) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      if (mounted) {
        setState(() {
          _importedFonts.add(family);
          _fontBytes[family] = Uint8List.fromList(bytes);
          _dirty = true;
          _structureDirty = true;
        });
      }
    }
    final bubble = _bubble;
    if (bubble != null) {
      _replaceBubble(bubble.copyWith(fontFamily: family), remember: true);
    }
  }

  Future<void> _pickFontColor(BubblePlacement bubble) async {
    var selected = Color(bubble.fontColorValue);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择任意字体颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selected,
            onColorChanged: (color) => selected = color,
            enableAlpha: false,
            displayThumbColor: true,
            hexInputBar: true,
            paletteType: PaletteType.hsvWithHue,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('应用颜色'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      _replaceBubble(
        bubble.copyWith(fontColorValue: selected.value),
        remember: true,
      );
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    if (_dirty && _pages.isNotEmpty) unawaited(_persistLocalProject());
    _script.dispose();
    super.dispose();
  }

  Future<void> _loadStoredProject() async {
    try {
      final bytes = await loadLocalProject(widget.projectId);
      if (bytes == null) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      final project = await decodeProject(bytes);
      final thumbnail = project.pages.isEmpty
          ? null
          : await encodeThumbnailBase64(project.pages.first.image);
      final edits = await loadLocalProjectEdits(widget.projectId);
      String? editedScript;
      if (edits != null) {
        try {
          editedScript = applyProjectEdits(edits, project.pages);
        } catch (_) {
          // The full project remains usable even if an optional edit layer fails.
        }
      }
      _ensureBubbleIds(project.pages);
      if (!mounted) return;
      setState(() {
        _pages
          ..clear()
          ..addAll(project.pages);
        _fontBytes
          ..clear()
          ..addAll(project.fonts);
        _importedFonts
          ..clear()
          ..addAll(project.fonts.keys);
        _script.text = editedScript ?? _scriptForPages(project.pages);
        _projectThumbnailBase64 = thumbnail;
        _selectedPage = 0;
        _selectedBubble = 0;
        _selectionVisible =
            _pages.isNotEmpty && _pages.first.placements.isNotEmpty;
        _processing = false;
        _dirty = false;
        _structureDirty = false;
      });
      await saveLocalProjectEdits(
        widget.projectId,
        widget.projectName,
        encodeProjectEdits(project.pages, _script.text),
        thumbnailBase64: thumbnail,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('项目无法打开'),
          content: Text('本地项目数据可能已经损坏：$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _persistLocalProject({bool forceFull = false}) async {
    if (_pages.isEmpty || _saving) return;
    _saving = true;
    try {
      if (forceFull || _structureDirty) {
        await saveLocalProject(
          widget.projectId,
          widget.projectName,
          encodeProject(_pages, _script.text, fonts: _fontBytes),
          thumbnailBase64: _projectThumbnailBase64,
        );
        _structureDirty = false;
      }
      await saveLocalProjectEdits(
        widget.projectId,
        widget.projectName,
        encodeProjectEdits(_pages, _script.text),
        thumbnailBase64: _projectThumbnailBase64,
      );
      if (mounted) setState(() => _dirty = false);
    } finally {
      _saving = false;
    }
  }

  Future<void> _returnToProjects() async {
    if (_dirty && _pages.isNotEmpty) await _persistLocalProject();
    if (mounted) widget.onExitToProjects();
  }

  void _ensureBubbleIds(List<ImagePage> pages) {
    for (final page in pages) {
      for (var i = 0; i < page.captions.length; i++) {
        final caption = page.captions[i];
        if (caption.bubbleId.isNotEmpty) continue;
        final migrated = caption.copyWith(bubbleId: '${page.pageId}-b${i + 1}');
        page.captions[i] = migrated;
        if (i < page.placements.length) {
          page.placements[i] = page.placements[i].copyWith(caption: migrated);
        }
      }
    }
  }

  String _scriptForPages(List<ImagePage> pages) {
    final output = StringBuffer();
    output
      ..writeln('@格式=BCS顺序字幕脚本')
      ..writeln('@版本=2')
      ..writeln('@坐标单位=px')
      ..writeln();
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      output
        ..writeln('[图片 ${pageIndex + 1}]')
        ..writeln('@原文件名=${page.name}')
        ..writeln('@原图尺寸=${page.originalWidth}x${page.originalHeight}')
        ..writeln();
      for (var i = 0; i < page.captions.length; i++) {
        final caption = page.captions[i];
        final bubble = page.placements[i];
        final bubbleId = caption.bubbleId.isEmpty
            ? 'p${pageIndex + 1}-b${i + 1}'
            : caption.bubbleId;
        output
          ..writeln('@气泡ID=$bubbleId')
          ..writeln(
            '@矩形=${bubble.x.toStringAsFixed(0)},${bubble.y.toStringAsFixed(0)},${bubble.width.toStringAsFixed(0)},${bubble.height.toStringAsFixed(0)}',
          )
          ..writeln('@尾巴=${_tailName(bubble.tailDirection)}')
          ..writeln('@气泡=${_shapeName(bubble.shape)}')
          ..writeln('@字体=${bubble.fontFamily}')
          ..writeln('@字号=${bubble.fontSize.toStringAsFixed(0)}')
          ..writeln(
            '@颜色=#${bubble.fontColorValue.toRadixString(16).padLeft(8, '0').substring(2)}',
          )
          ..writeln('@行距=${bubble.lineHeight.toStringAsFixed(2)}')
          ..writeln('@描边=${bubble.strokeWidth.toStringAsFixed(1)}')
          ..writeln(caption.text)
          ..writeln();
      }
    }
    return output.toString().trimRight();
  }

  String _tailName(TailDirection value) => switch (value) {
        TailDirection.upLeft => '左上',
        TailDirection.upRight => '右上',
        TailDirection.downLeft => '左下',
        TailDirection.downRight => '右下',
      };

  String _shapeName(BubbleShape value) => switch (value) {
        BubbleShape.ellipse => '对话气泡',
        BubbleShape.rounded => '旁白框',
        BubbleShape.shout => '惊喊气泡',
        BubbleShape.thought => '心理气泡',
        BubbleShape.whisper => '耳语气泡',
      };

  Future<void> _pickImages({bool replaceProject = false}) async {
    final replace = replaceProject || _isDemoProject || _pages.isEmpty;
    if (replaceProject && _dirty && _pages.isNotEmpty && !_isDemoProject) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('新建图片项目？'),
          content: const Text('这会替换当前工程。请先保存需要保留的修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃并新建'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    setState(() => _processing = true);
    final pages = <ImagePage>[];
    final failed = <String>[];
    for (final file in result.files) {
      final name = file.name;
      final bytes = file.bytes;
      if (bytes == null) {
        failed.add(name);
        continue;
      }
      try {
        final sourceBytes = Uint8List.fromList(bytes);
        final preview = await decodeImagePreview(sourceBytes);
        pages.add(
          ImagePage(
            name: name,
            bytes: sourceBytes,
            image: preview.image,
            originalWidth: preview.originalWidth,
            originalHeight: preview.originalHeight,
          ),
        );
      } catch (_) {
        failed.add(name);
      }
    }
    if (pages.isEmpty) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没有读取到有效图片，请检查文件格式或文件是否损坏。')));
      return;
    }
    if (!mounted) return;
    setState(() => _processing = false);
    pages.sort((a, b) => compareNaturalNames(a.name, b.name));
    final orderedPages = await _confirmImageOrder(pages);
    if (orderedPages == null || !mounted) return;
    final existingCount = replace ? 0 : _pages.length;
    final selectedPageId = orderedPages.first.pageId;
    setState(() {
      final merged = mergeImagePages(_pages, orderedPages, replace: replace);
      _pages
        ..clear()
        ..addAll(merged);
      _selectedPage = _pages.indexWhere(
        (page) => page.pageId == selectedPageId,
      );
      _selectedBubble = 0;
      _selectionVisible = true;
      _processing = false;
      if (replace) _projectName = '未命名工程';
      _dirty = true;
      _structureDirty = true;
      _isDemoProject = false;
      _undoStack.clear();
      _redoStack.clear();
    });
    _script.text = _scriptForPages(_pages);
    _projectThumbnailBase64 = await encodeThumbnailBase64(_pages.first.image);
    await _persistLocalProject(forceFull: true);
    if (mounted) {
      final messages = <String>[
        '${replace ? '已导入' : '已添加'} ${pages.length} 张图片，项目共 ${_pages.length} 张。',
        if (failed.isNotEmpty) '跳过 ${failed.length} 个无法读取的文件。',
        '${orderedPages.length} 张图片已按确认顺序放在第 ${existingCount + 1}–${existingCount + orderedPages.length} 位。',
      ];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messages.join(' '))));
    }
  }

  Future<List<ImagePage>?> _confirmImageOrder(List<ImagePage> source) async {
    final ordered = [...source];
    return showDialog<List<ImagePage>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('确认图片顺序'),
          content: SizedBox(
            width: 620,
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('当前默认按文件名自然排序；可以拖动调整。字幕将严格按确认后的第 1、2、3 张依次对应。'),
                const SizedBox(height: 12),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: ordered.length,
                    onReorder: (oldIndex, newIndex) {
                      setDialogState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final page = ordered.removeAt(oldIndex);
                        ordered.insert(newIndex, page);
                      });
                    },
                    itemBuilder: (context, index) {
                      final page = ordered[index];
                      return ListTile(
                        key: ValueKey(page.pageId),
                        leading: SizedBox(
                          width: 54,
                          height: 54,
                          child: RawImage(image: page.image, fit: BoxFit.cover),
                        ),
                        title: Text('${index + 1}. ${page.name}'),
                        subtitle: Text(
                          '${page.originalWidth} × ${page.originalHeight} px',
                        ),
                        trailing: const Icon(Icons.drag_handle),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消导入'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [...ordered]),
              child: const Text('确认此顺序'),
            ),
          ],
        ),
      ),
    );
  }

  void _autoArrange() {
    final parsed = parseCaptionScript(_script.text);
    final blocking = validateScriptForPages(parsed, _pages);
    if (blocking.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('字幕脚本无法应用'),
          content: Text(blocking.take(8).join('\n\n')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回修改'),
            ),
          ],
        ),
      );
      return;
    }
    final migratedLegacy = parsed.sections.any(
      (section) => section.legacyHeader,
    );
    if (_pages.isNotEmpty) _remember();
    for (var pageIndex = 0; pageIndex < _pages.length; pageIndex++) {
      final page = _pages[pageIndex];
      final incoming = parsed.sections[pageIndex].captions;
      final generated = _engine.arrange(
        incoming,
        imageWidth: page.originalWidth,
        imageHeight: page.originalHeight,
      );
      final oldPlacements = page.placements;
      final placements = preserveEditedPlacements(
        oldPlacements,
        generated,
        incoming,
      );
      final changed = page.captions.length != incoming.length ||
          List.generate(
            incoming.length,
            (i) =>
                i >= page.captions.length ||
                page.captions[i].speaker != incoming[i].speaker ||
                page.captions[i].text != incoming[i].text,
          ).any((value) => value);
      page
        ..captions = incoming
        ..placements = placements;
      if (changed) page.approved = false;
    }
    setState(() {
      _selectedBubble = 0;
      _selectionVisible = true;
      _dirty = true;
    });
    if (migratedLegacy) _script.text = _scriptForPages(_pages);
    if (mounted && (parsed.warnings.isNotEmpty || migratedLegacy)) {
      final messages = <String>[
        if (migratedLegacy) '旧版文件名脚本已按段落出现顺序迁移为 v2；文件名不再参与匹配。',
        ...parsed.warnings.take(3),
        if (parsed.warnings.length > 3)
          '另有 ${parsed.warnings.length - 3} 条格式警告。',
      ];
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('字幕格式检查'),
          content: Text(messages.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回修改'),
            ),
          ],
        ),
      );
    }
  }

  void _resetCurrentPageLayout() {
    final page = _page;
    if (page == null || page.captions.isEmpty) return;
    _remember();
    setState(() {
      page.placements = _engine.arrange(
        page.captions,
        imageWidth: page.originalWidth,
        imageHeight: page.originalHeight,
      );
      page.approved = false;
      _selectedBubble = 0;
      _selectionVisible = true;
      _dirty = true;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('仅重置了当前图片的气泡排版')));
  }

  Future<void> _runLayoutStep() async {
    final pagesWithCaptions = _pages.where((page) => page.captions.isNotEmpty);
    if (pagesWithCaptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可排版字幕，请先进入“字幕”导入或添加气泡。')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新自动排版'),
        content: Text(
          '将根据图片尺寸重新计算 ${pagesWithCaptions.length} 张图片中的气泡位置。'
          '手动调整过的位置会被替换，但文字、字体、颜色和气泡样式不会改变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始排版'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _remember();
    var bubbleCount = 0;
    setState(() {
      for (final page in pagesWithCaptions) {
        page.placements = _engine.arrange(
          page.captions,
          imageWidth: page.originalWidth,
          imageHeight: page.originalHeight,
        );
        page.approved = false;
        bubbleCount += page.placements.length;
      }
      _selectedBubble = 0;
      _selectionVisible = _page?.placements.isNotEmpty ?? false;
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '排版完成：${pagesWithCaptions.length} 张图片，共 $bubbleCount 个气泡。可继续手动微调。'),
      ),
    );
  }

  void _remember() {
    if (_pages.isEmpty) return;
    _undoStack.add(
      _ProjectSnapshot.capture(_pages, _selectedPage, _selectedBubble),
    );
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_pages.isEmpty || _undoStack.isEmpty) return;
    _redoStack.add(
      _ProjectSnapshot.capture(_pages, _selectedPage, _selectedBubble),
    );
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_pages.isEmpty || _redoStack.isEmpty) return;
    _undoStack.add(
      _ProjectSnapshot.capture(_pages, _selectedPage, _selectedBubble),
    );
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(_ProjectSnapshot snapshot) {
    if (snapshot.pages.length != _pages.length) return;
    setState(() {
      for (var i = 0; i < _pages.length; i++) {
        snapshot.pages[i].restore(_pages[i]);
      }
      _selectedPage = snapshot.selectedPage.clamp(0, _pages.length - 1);
      final count = _pages[_selectedPage].placements.length;
      _selectedBubble =
          count == 0 ? 0 : snapshot.selectedBubble.clamp(0, count - 1);
      _selectionVisible = count > 0;
      _dirty = true;
    });
  }

  void _replaceBubble(BubblePlacement bubble, {bool remember = false}) {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    if (remember) _remember();
    setState(() {
      page.placements[_selectedBubble] = bubble;
      page.captions[_selectedBubble] = bubble.caption;
      page.approved = false;
      _dirty = true;
    });
  }

  void _addBubble() {
    final page = _page;
    if (page == null) return;
    _remember();
    final index = page.placements.length;
    final caption = CaptionLine(
      speaker: '',
      text: '新字幕 ${index + 1}',
      bubbleId: '${page.pageId}-b${DateTime.now().microsecondsSinceEpoch}',
    );
    final width = page.originalWidth * .30;
    final height = page.originalHeight * .16;
    final offset = (index % 5) * page.originalWidth * .035;
    final bubble = BubblePlacement(
      caption: caption,
      x: (page.originalWidth * .08 + offset).clamp(
        0,
        page.originalWidth - width,
      ),
      y: (page.originalHeight * .08 + offset).clamp(
        0,
        page.originalHeight - height,
      ),
      width: width,
      height: height,
    );
    setState(() {
      page.captions.add(caption);
      page.placements.add(bubble);
      _selectedBubble = page.placements.length - 1;
      _selectionVisible = true;
      page.approved = false;
      _dirty = true;
    });
  }

  void _duplicateBubble() {
    final page = _page;
    final source = _bubble;
    if (page == null || source == null) return;
    _remember();
    final caption = source.caption.copyWith(
      text: '${source.caption.text}（副本）',
      bubbleId: '${page.pageId}-b${DateTime.now().microsecondsSinceEpoch}',
    );
    final bubble = source.copyWith(
      caption: caption,
      x: (source.x + 24).clamp(0, page.originalWidth - source.width),
      y: (source.y + 24).clamp(0, page.originalHeight - source.height),
    );
    setState(() {
      page.captions.add(caption);
      page.placements.add(bubble);
      _selectedBubble = page.placements.length - 1;
      _selectionVisible = true;
      page.approved = false;
      _dirty = true;
    });
  }

  void _deleteBubble() {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    _remember();
    setState(() {
      page.placements.removeAt(_selectedBubble);
      page.captions.removeAt(_selectedBubble);
      _selectedBubble = page.placements.isEmpty
          ? 0
          : _selectedBubble.clamp(0, page.placements.length - 1);
      _selectionVisible = page.placements.isNotEmpty;
      page.approved = false;
      _dirty = true;
    });
  }

  void _moveLayer(int delta) {
    final page = _page;
    if (page == null || page.placements.length < 2) return;
    final target = (_selectedBubble + delta).clamp(
      0,
      page.placements.length - 1,
    );
    if (target == _selectedBubble) return;
    _remember();
    setState(() {
      final bubble = page.placements.removeAt(_selectedBubble);
      final caption = page.captions.removeAt(_selectedBubble);
      page.placements.insert(target, bubble);
      page.captions.insert(target, caption);
      _selectedBubble = target;
      page.approved = false;
      _dirty = true;
    });
  }

  void _selectPage(int index) => setState(() {
        _selectedPage = index;
        _selectedBubble = 0;
        _selectionVisible = _pages[index].placements.isNotEmpty;
        _undoStack.clear();
        _redoStack.clear();
      });

  Future<void> _exportAll() async {
    if (_pages.isEmpty || _exporting) return;
    final directory = await chooseImageExportDirectory(
      initialDirectory:
          _settings.exportDirectory.isEmpty ? null : _settings.exportDirectory,
    );
    if (directory == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      var exported = 0;
      var skipped = 0;
      var overwriteAll = false;
      for (var index = 0; index < _pages.length; index++) {
        final fileName = exportImageName(
          _pages[index],
          index,
          numbered: _settings.numberedExportNames,
        );
        var overwrite = overwriteAll;
        if (!overwrite && await exportImageExists(directory, fileName)) {
          final choice = await _askExistingImage(fileName);
          if (!mounted || choice == _ExistingImageChoice.cancel) break;
          if (choice == _ExistingImageChoice.skip) {
            skipped++;
            continue;
          }
          overwriteAll = choice == _ExistingImageChoice.overwriteAll;
          overwrite = true;
        }
        final rendered = await renderPageForExport(
          _pages[index],
          index,
          numbered: _settings.numberedExportNames,
        );
        await writeExportImage(
          directory,
          rendered.fileName,
          rendered.bytes,
          overwrite: overwrite,
        );
        exported++;
        if (mounted) setState(() {});
        await Future<void>.delayed(Duration.zero);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '导出完成：已直接写入 $exported 张 PNG${skipped == 0 ? '' : '，跳过 $skipped 张'}\n$directory')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<_ExistingImageChoice> _askExistingImage(String fileName) async {
    return await showDialog<_ExistingImageChoice>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('图片已存在'),
            content: Text('“$fileName”已在导出目录中。是否用当前修改后的成图覆盖它？'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.cancel),
                child: const Text('取消导出'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.skip),
                child: const Text('跳过此图'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.overwriteAll),
                child: const Text('全部覆盖'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.overwrite),
                child: const Text('覆盖此图'),
              ),
            ],
          ),
        ) ??
        _ExistingImageChoice.cancel;
  }

  Future<void> _saveProject() async {
    if (_pages.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final projectBytes = encodeProject(
        _pages,
        _script.text,
        fonts: _fontBytes,
      );
      final safeName =
          _projectName == '未命名工程' ? '漫画气泡字幕工程.bcs.json' : _projectName;
      final path = await saveBinaryFile(
        title: '保存气泡字幕工程',
        fileName:
            safeName.endsWith('.bcs.json') ? safeName : '$safeName.bcs.json',
        bytes: projectBytes,
        kind: 'project',
      );
      if (!mounted || path == null) return;
      await saveLocalProject(
        widget.projectId,
        widget.projectName,
        projectBytes,
        thumbnailBase64: _projectThumbnailBase64,
      );
      await saveLocalProjectEdits(
        widget.projectId,
        widget.projectName,
        encodeProjectEdits(_pages, _script.text),
        thumbnailBase64: _projectThumbnailBase64,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _structureDirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('工程已保存：$path')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存工程失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openProject() async {
    if (_saving || _processing) return;
    if (_dirty && _pages.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('打开其他工程？'),
          content: const Text('当前工程有未保存修改。继续打开会放弃这些修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃并打开'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    try {
      final file = await openProjectFile();
      if (file == null) return;
      setState(() => _processing = true);
      final project = await decodeProject(file.bytes);
      final thumbnail = project.pages.isEmpty
          ? null
          : await encodeThumbnailBase64(project.pages.first.image);
      _ensureBubbleIds(project.pages);
      if (!mounted) return;
      setState(() {
        _pages
          ..clear()
          ..addAll(project.pages);
        _script.text = _scriptForPages(project.pages);
        _projectThumbnailBase64 = thumbnail;
        _selectedPage = 0;
        _selectedBubble = 0;
        _selectionVisible =
            _pages.isNotEmpty && _pages.first.placements.isNotEmpty;
        _dirty = true;
        _structureDirty = true;
        _isDemoProject = false;
        _processing = false;
        _undoStack.clear();
        _redoStack.clear();
      });
      await _persistLocalProject(forceFull: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已打开工程：${file.name}')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法打开工程'),
          content: Text('$error\n\n请确认文件由本软件生成，且内容未被破坏。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showScriptEditor() async {
    final draft = TextEditingController(text: _script.text);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('匹配字幕脚本'),
          content: SizedBox(
            width: 620,
            height: 460,
            child: TextField(
              controller: draft,
              expands: true,
              maxLines: null,
              minLines: null,
              contextMenuBuilder: buildAppTextContextMenu,
              style: const TextStyle(fontFamily: 'monospace', height: 1.5),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _importScriptFile(draft),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('导入 TXT'),
            ),
            TextButton.icon(
              onPressed: _exportScriptTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('导出当前模板'),
            ),
            TextButton.icon(
              onPressed: _showFormatGuide,
              icon: const Icon(Icons.rule_outlined),
              label: const Text('格式规范'),
            ),
            TextButton.icon(
              onPressed: _showAiScriptGuide,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('AI 生成指南'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                _script.text = draft.text;
                setState(() => _dirty = true);
                Navigator.pop(context);
                _autoArrange();
              },
              child: const Text('应用并自动排版'),
            ),
          ],
        ),
      );
    } finally {
      draft.dispose();
    }
  }

  Future<void> _importScriptFile(TextEditingController target) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: true,
      );
      final file = result?.files.singleOrNull;
      if (file?.bytes == null) return;
      var text = utf8.decode(file!.bytes!, allowMalformed: false);
      if (text.startsWith('\ufeff')) text = text.substring(1);
      target.text = text;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字幕文件读取失败：$error')));
      }
    }
  }

  Future<void> _exportScriptTemplate() async {
    if (_pages.isEmpty) return;
    try {
      final text = _scriptForPages(_pages);
      final path = await saveBinaryFile(
        title: '导出精准字幕模板',
        fileName: '精准字幕模板.txt',
        bytes: Uint8List.fromList(utf8.encode(text)),
        kind: 'text',
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字幕模板已保存：$path')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('模板导出失败：$error')));
      }
    }
  }

  void _showFormatGuide() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('精准字幕格式规范'),
          content: const SizedBox(
            width: 700,
            height: 540,
            child: SingleChildScrollView(
              child: SelectableText(
                '@格式=BCS顺序字幕脚本\n@版本=2\n@坐标单位=px\n\n'
                '[图片 1]\n@原文件名=示例.png\n@原图尺寸=1080x1920\n\n'
                '@气泡ID=p1-b1\n@矩形=80,100,520,260\n@尾巴=右下\n@气泡=对话气泡\n@字体=Microsoft YaHei\n@字号=34\n@颜色=#141518\n@行距=1.25\n@描边=2\n这里替换对话\n\n'
                '说明：\n'
                '• [图片 1]、[图片 2] 严格对应确认后的第 1、2 张图片；文件名只作提示。\n'
                '• 每张必须填写 @原图尺寸=宽x高，应用时会与实际图片严格校验。\n'
                '• @矩形=x,y,宽,高，全部使用原图像素；图片左上角为 0,0。\n'
                '• @气泡ID 在工程内必须稳定，用于重新应用时保留手工位置。\n'
                '• 尾巴只能是左上、右上、左下、右下。\n'
                '• 尾部固定在气泡边缘，不可拖动；只需选择左上、右上、左下或右下。\n'
                '• 气泡可用对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡。心理气泡为云朵主体和连续圆点尾；耳语气泡使用虚线轮廓；旁白框不显示尾巴。\n'
                '• 模板固定使用白色或浅灰填充、黑色细描边；@颜色 只改变内部字体颜色。\n'
                '• 每个气泡块之间必须留一个空行。\n'
                '• 旧版 [文件名] 脚本可导入，软件会按段落出现顺序迁移，绝不会再按文件名匹配。',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.55,
                ),
                contextMenuBuilder: buildAppTextContextMenu,
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );

  String _currentProjectContext() {
    final images = _pages.indexed
        .map(
          (entry) =>
              '图片 ${entry.$1 + 1}：${entry.$2.name}，原图尺寸=${entry.$2.originalWidth}x${entry.$2.originalHeight}',
        )
        .join('\n');
    return '# 当前项目的精确输入\n\n'
        '下面的数据由软件直接生成。图片顺序和尺寸是强制约束，不允许 AI 修改或重新排序。\n\n'
        '## 图片顺序与原图尺寸\n\n$images\n\n'
        '## 当前项目完整模板\n\n'
        '```text\n${_scriptForPages(_pages)}\n```\n\n'
        '请把实际图片、需要加入的对白或旁白，与以上规范和模板一起提供给 AI。AI 必须只返回最终的 BCS 纯文本脚本。';
  }

  Future<void> _showAiScriptGuide() async {
    final exactGuide = await rootBundle.loadString('AI字幕脚本生成指南.md');
    if (!mounted) return;
    final prompt = '$exactGuide\n\n---\n\n${_currentProjectContext()}';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('完整 AI 字幕脚本生成指南'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '以下内容直接读取 AI字幕脚本生成指南.md，并在末尾附加当前项目的真实顺序、原图尺寸和完整模板。',
                  style: TextStyle(
                    color: AppColors.pink,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  prompt,
                  style: const TextStyle(fontFamily: 'monospace', height: 1.5),
                  contextMenuBuilder: buildAppTextContextMenu,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: prompt));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('完整规范、图片顺序、原图尺寸和当前模板已复制')),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制精确规范 + 当前模板'),
          ),
        ],
      ),
    );
  }

  void _showHelp() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.menu_book_outlined, color: AppColors.pink),
              SizedBox(width: 10),
              Text('使用指南'),
            ],
          ),
          content: const SizedBox(
            width: 560,
            child: Text(
              '1. 软件启动后先进入项目页。可以创建、删除或切换项目；名称留空时会按创建时间自动命名。\n\n2. 点击“添加图片”后，图片默认按文件名自然排序，例如 1、2、10。可以在顺序确认窗口继续拖动调整。\n\n3. 点击顶部“字幕”。每个 [图片 N] 段必须包含 @原图尺寸；气泡使用原图像素 @矩形=x,y,宽,高。字幕只按确认顺序对应，不按文件名匹配。\n\n4. 字幕编辑器采用草稿模式；点击取消不会改变工程。稳定的 @气泡ID 可在再次应用时保留手工位置和样式。\n\n5. 在画布上拖动气泡或八个缩放点，右侧可修改文字、形状、字体、颜色、字号、行距、描边和尾巴方向。点击画布空白处可取消选框。\n\n6. 导出位于右上角，不属于编辑流程。设置中可以选择默认保存目录、是否每次询问位置、命名方式和自动保存间隔。\n\n图片和字幕始终只在当前设备处理，不会上传。',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showFormatGuide();
              },
              icon: const Icon(Icons.rule_outlined),
              label: const Text('精准格式'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveProject,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _openProject,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            _duplicateBubble,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteBubble,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: _processing
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _header(wide),
                      const Divider(height: 1),
                      Expanded(child: wide ? _desktopBody() : _compactBody()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool wide) => Container(
        height: wide ? 104 : 72,
        color: AppColors.panel,
        padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 12),
        child: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/mascot.png',
                width: wide ? 62 : 46,
                height: wide ? 62 : 46,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            if (wide)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '浪白漫画字幕工坊',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${_dirty ? '● ' : ''}$_projectName',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.pink, fontSize: 12),
                  ),
                ],
              )
            else
              const Expanded(
                child: Text(
                  '浪白漫画字幕工坊',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            if (wide) ...[
              const SizedBox(width: 28),
              Expanded(child: _workflowBar()),
            ],
            const SizedBox(width: 12),
            if (wide)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _dirty ? Icons.sync : Icons.check_circle,
                    color: _dirty ? AppColors.warning : AppColors.success,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _dirty ? '有未保存修改' : '已保存 · 本地',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            IconButton(
              onPressed: _returnToProjects,
              tooltip: '切换项目',
              icon: const Icon(Icons.grid_view_outlined),
            ),
            IconButton(
              onPressed: _openProject,
              tooltip: '打开工程',
              icon: const Icon(Icons.folder_open_outlined),
            ),
            IconButton(
              onPressed: _saving ? null : _saveProject,
              tooltip: '保存工程',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
            IconButton(
              onPressed: _showHelp,
              tooltip: '使用指南',
              icon: const Icon(Icons.help_outline),
            ),
            IconButton(
              onPressed: _showSettings,
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
            ),
            if (wide)
              FilledButton.icon(
                onPressed: _exporting ? null : _exportAll,
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('批量导出'),
              )
            else
              IconButton(
                onPressed: _exporting ? null : _exportAll,
                tooltip: '批量导出',
                icon: const Icon(Icons.file_download_outlined),
              ),
          ],
        ),
      );

  Widget _workflowBar() {
    final total = _pages.length;
    final matched = _pages.where((page) => page.captions.isNotEmpty).length;
    final active = total == 0
        ? 0
        : matched < total
            ? 1
            : 2;
    final items = [
      (
        Icons.collections_outlined,
        '图片',
        total == 0 ? '开始添加' : '$total 张',
        () => _pickImages(),
      ),
      (
        Icons.subtitles_outlined,
        '字幕',
        total == 0 ? '等待图片' : '$matched/$total 已匹配',
        _showScriptEditor,
      ),
      (
        Icons.auto_fix_high_outlined,
        '排版',
        matched == 0 ? '等待字幕' : '重新自动排版',
        _runLayoutStep,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: i == active ? AppColors.blush : Colors.white,
                border: Border.all(
                  color: i == active ? AppColors.pink : AppColors.line,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: items[i].$4,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        items[i].$1,
                        size: 19,
                        color: i == active ? AppColors.pink : AppColors.ink,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[i].$2,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              items[i].$3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: i == active
                                    ? AppColors.pink
                                    : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (i < items.length - 1) ...[
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.line),
            const SizedBox(width: 3),
          ],
        ],
      ],
    );
  }

  Widget _desktopBody() => Row(
        children: [
          SizedBox(width: 394, child: _pageRail()),
          const VerticalDivider(width: 1),
          Expanded(child: _workspace()),
          if (_inspectorVisible) ...[
            Container(
              width: 348,
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: _inspector(),
            ),
          ],
        ],
      );

  Widget _compactBody() => Column(
        children: [
          SizedBox(height: 100, child: _horizontalPages()),
          const Divider(height: 1),
          Expanded(child: _workspace(compact: true)),
          SizedBox(height: 255, child: _inspector(compact: true)),
        ],
      );

  Widget _pageRail() {
    final visible = <MapEntry<int, ImagePage>>[
      for (var i = 0; i < _pages.length; i++) MapEntry(i, _pages[i]),
    ];
    final matched = _pages.where((page) => page.captions.isNotEmpty).length;
    return ColoredBox(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '章节：第01话 初遇',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '共${_pages.length}张',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                _statusPill(
                  Icons.subtitles_outlined,
                  '$matched/${_pages.length} 已匹配字幕',
                  matched == _pages.length && _pages.isNotEmpty
                      ? AppColors.success
                      : AppColors.muted,
                ),
                const Spacer(),
                const Text(
                  '按确认顺序',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, row) {
                final index = visible[row].key;
                final page = visible[row].value;
                final selected = index == _selectedPage;
                final preview = page.captions
                    .map((caption) => caption.text.trim())
                    .where((text) => text.isNotEmpty)
                    .join(' / ');
                final statusColor =
                    page.captions.isEmpty ? AppColors.muted : AppColors.success;
                final statusText = page.captions.isEmpty ? '未匹配' : '已匹配';
                return InkWell(
                  onTap: () => _selectPage(index),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.blush : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected ? AppColors.pink : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${index + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                              color: selected ? AppColors.pink : AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: RawImage(
                            image: page.image,
                            width: 82,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                page.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                preview.isEmpty ? '等待匹配字幕' : preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: selected
                                      ? AppColors.pinkPressed
                                      : AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      page.captions.isEmpty
                                          ? '等待字幕'
                                          : '${page.captions.length} 条字幕',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    page.captions.isEmpty
                                        ? Icons.remove_circle_outline
                                        : Icons.check_circle,
                                    size: 13,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: statusColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImages(),
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 18,
                    ),
                    label: const Text('添加图片'),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多图片选项',
                  onSelected: (value) {
                    if (value == 'replace') {
                      _pickImages(replaceProject: true);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'replace', child: Text('清空图片并重新导入')),
                  ],
                ),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _showScriptEditor,
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('匹配字幕'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _horizontalPages() => ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        itemCount: _pages.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _selectPage(i),
          child: Container(
            width: 84,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: i == _selectedPage ? AppColors.pink : AppColors.line,
                width: i == _selectedPage ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RawImage(image: _pages[i].image, fit: BoxFit.cover),
                Positioned(
                  left: 4,
                  bottom: 3,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _workspace({bool compact = false}) {
    final page = _page;
    if (page == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _pickImages(),
          icon: const Icon(Icons.folder_open),
          label: const Text('导入图片'),
        ),
      );
    }
    return ColoredBox(
      color: AppColors.canvas,
      child: Column(
        children: [
          if (!compact)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: AppColors.panel,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '当前：第01话 · ${page.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    '对比：',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showRendered = false),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          !_showRendered ? AppColors.pink : AppColors.muted,
                      minimumSize: const Size(42, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    child: const Text('原图'),
                  ),
                  Switch(
                    value: _showRendered,
                    onChanged: (value) => setState(() => _showRendered = value),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showRendered = true),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          _showRendered ? AppColors.pink : AppColors.muted,
                      minimumSize: const Size(42, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    child: const Text('渲染'),
                  ),
                  const VerticalDivider(indent: 11, endIndent: 11),
                  IconButton(
                    onPressed: _undoStack.isEmpty ? null : _undo,
                    tooltip: '撤销',
                    icon: const Icon(Icons.undo, size: 20),
                  ),
                  IconButton(
                    onPressed: _redoStack.isEmpty ? null : _redo,
                    tooltip: '重做',
                    icon: const Icon(Icons.redo, size: 20),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '气泡编辑命令',
                    icon: const Icon(Icons.edit_note, size: 21),
                    onSelected: (value) {
                      switch (value) {
                        case 'new':
                          _addBubble();
                        case 'duplicate':
                          _duplicateBubble();
                        case 'back':
                          _moveLayer(-1);
                        case 'front':
                          _moveLayer(1);
                        case 'delete':
                          _deleteBubble();
                        case 'inspector':
                          setState(() => _inspectorVisible = true);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'new',
                        child: ListTile(
                          leading: Icon(Icons.add_comment_outlined),
                          title: Text('新建气泡'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        enabled: _bubble != null,
                        child: const ListTile(
                          leading: Icon(Icons.content_copy_outlined),
                          title: Text('复制气泡'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'back',
                        enabled: _bubble != null,
                        child: const ListTile(
                          leading: Icon(Icons.flip_to_back_outlined),
                          title: Text('下移一层'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'front',
                        enabled: _bubble != null,
                        child: const ListTile(
                          leading: Icon(Icons.flip_to_front_outlined),
                          title: Text('上移一层'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: _bubble != null,
                        child: const ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('删除气泡'),
                          dense: true,
                        ),
                      ),
                      if (!_inspectorVisible)
                        PopupMenuItem(
                          value: 'inspector',
                          enabled: _bubble != null,
                          child: const ListTile(
                            leading: Icon(Icons.tune),
                            title: Text('打开属性面板'),
                            dense: true,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${page.originalWidth} × ${page.originalHeight}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) {
                final ratio = page.aspectRatio;
                var height = box.maxHeight * .93 * _zoom;
                var width = height * ratio;
                if (width > box.maxWidth * .93 * _zoom) {
                  width = box.maxWidth * .93 * _zoom;
                  height = width / ratio;
                }
                final sx = width / page.originalWidth;
                final sy = height / page.originalHeight;
                int hitTest(Offset local) {
                  final point = Offset(local.dx / sx, local.dy / sy);
                  for (var i = page.placements.length - 1; i >= 0; i--) {
                    final b = page.placements[i];
                    if (Rect.fromLTWH(
                      b.x,
                      b.y,
                      b.width,
                      b.height,
                    ).inflate(18).contains(point)) {
                      return i;
                    }
                  }
                  return -1;
                }

                _DragMode? hitHandle(Offset local, BubblePlacement bubble) {
                  final point = Offset(local.dx / sx, local.dy / sy);
                  final rect = Rect.fromLTWH(
                    bubble.x,
                    bubble.y,
                    bubble.width,
                    bubble.height,
                  );
                  final scale = (sx + sy) / 2;
                  final radius = 22 / scale;
                  final handles = bubbleResizeHandles(rect);
                  const modes = [
                    _DragMode.topLeft,
                    _DragMode.top,
                    _DragMode.topRight,
                    _DragMode.right,
                    _DragMode.bottomRight,
                    _DragMode.bottom,
                    _DragMode.bottomLeft,
                    _DragMode.left,
                  ];
                  for (var i = 0; i < handles.length; i++) {
                    if ((point - handles[i]).distance <= radius) {
                      return modes[i];
                    }
                  }
                  return null;
                }

                (int, _DragMode)? interactionAt(Offset local) {
                  if (!_showRendered) return null;
                  if (_selectionVisible &&
                      page.placements.isNotEmpty &&
                      _selectedBubble < page.placements.length) {
                    final selectedMode = hitHandle(
                      local,
                      page.placements[_selectedBubble],
                    );
                    if (selectedMode != null) {
                      return (_selectedBubble, selectedMode);
                    }
                  }
                  final index = hitTest(local);
                  if (index < 0) return null;
                  return (
                    index,
                    hitHandle(local, page.placements[index]) ?? _DragMode.move,
                  );
                }

                MouseCursor cursorFor(_DragMode? mode) => switch (mode) {
                      _DragMode.topLeft ||
                      _DragMode.bottomRight =>
                        SystemMouseCursors.resizeUpLeftDownRight,
                      _DragMode.topRight ||
                      _DragMode.bottomLeft =>
                        SystemMouseCursors.resizeUpRightDownLeft,
                      _DragMode.top ||
                      _DragMode.bottom =>
                        SystemMouseCursors.resizeUpDown,
                      _DragMode.left ||
                      _DragMode.right =>
                        SystemMouseCursors.resizeLeftRight,
                      _DragMode.move => SystemMouseCursors.move,
                      null => SystemMouseCursors.basic,
                    };

                return InteractiveViewer(
                  panEnabled: false,
                  scaleEnabled: false,
                  child: Center(
                    child: MouseRegion(
                      cursor: cursorFor(_dragMode ?? _hoverMode),
                      onHover: (event) {
                        if (_dragMode != null) return;
                        final mode = interactionAt(event.localPosition)?.$2;
                        if (mode != _hoverMode) {
                          setState(() => _hoverMode = mode);
                        }
                      },
                      onExit: (_) {
                        if (_dragMode == null && _hoverMode != null) {
                          setState(() => _hoverMode = null);
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapDown: (details) {
                          final interaction = interactionAt(
                            details.localPosition,
                          );
                          if (interaction != null) {
                            setState(() {
                              _selectedBubble = interaction.$1;
                              _selectionVisible = true;
                              _inspectorVisible = true;
                            });
                          } else {
                            setState(() => _selectionVisible = false);
                          }
                        },
                        onPanStart: (details) {
                          final interaction = interactionAt(
                            details.localPosition,
                          );
                          if (interaction == null) return;
                          setState(() {
                            _selectedBubble = interaction.$1;
                            _selectionVisible = true;
                            _dragMode = interaction.$2;
                            _hoverMode = interaction.$2;
                            _inspectorVisible = true;
                          });
                          _remember();
                        },
                        onPanUpdate: (details) {
                          final b = _bubble;
                          final mode = _dragMode;
                          if (b == null || mode == null) return;
                          final dx = details.delta.dx / sx;
                          final dy = details.delta.dy / sy;
                          const minWidth = 80.0;
                          const minHeight = 56.0;
                          var left = b.x;
                          var top = b.y;
                          var right = b.x + b.width;
                          var bottom = b.y + b.height;
                          switch (mode) {
                            case _DragMode.move:
                              left = (left + dx).clamp(
                                0,
                                page.originalWidth - b.width,
                              );
                              top = (top + dy).clamp(
                                0,
                                page.originalHeight - b.height,
                              );
                              right = left + b.width;
                              bottom = top + b.height;
                            case _DragMode.topLeft:
                              left = (left + dx).clamp(0, right - minWidth);
                              top = (top + dy).clamp(0, bottom - minHeight);
                            case _DragMode.top:
                              top = (top + dy).clamp(0, bottom - minHeight);
                            case _DragMode.topRight:
                              right = (right + dx).clamp(
                                left + minWidth,
                                page.originalWidth.toDouble(),
                              );
                              top = (top + dy).clamp(0, bottom - minHeight);
                            case _DragMode.right:
                              right = (right + dx).clamp(
                                left + minWidth,
                                page.originalWidth.toDouble(),
                              );
                            case _DragMode.bottomRight:
                              right = (right + dx).clamp(
                                left + minWidth,
                                page.originalWidth.toDouble(),
                              );
                              bottom = (bottom + dy).clamp(
                                top + minHeight,
                                page.originalHeight.toDouble(),
                              );
                            case _DragMode.bottom:
                              bottom = (bottom + dy).clamp(
                                top + minHeight,
                                page.originalHeight.toDouble(),
                              );
                            case _DragMode.bottomLeft:
                              left = (left + dx).clamp(0, right - minWidth);
                              bottom = (bottom + dy).clamp(
                                top + minHeight,
                                page.originalHeight.toDouble(),
                              );
                            case _DragMode.left:
                              left = (left + dx).clamp(0, right - minWidth);
                          }
                          _replaceBubble(
                            b.copyWith(
                              x: left,
                              y: top,
                              width: right - left,
                              height: bottom - top,
                            ),
                          );
                        },
                        onPanEnd: (_) => setState(() => _dragMode = null),
                        onPanCancel: () => setState(() => _dragMode = null),
                        child: Container(
                          width: width,
                          height: height,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.ink, width: 2),
                            color: Colors.white,
                          ),
                          child: CustomPaint(
                            painter: PagePainter(
                              page: page,
                              showBubbles: _showRendered,
                              selectedIndex: !_showRendered ||
                                      !_selectionVisible ||
                                      page.placements.isEmpty
                                  ? null
                                  : _selectedBubble,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: AppColors.panel,
            child: Row(
              children: [
                IconButton(
                  onPressed: () =>
                      setState(() => _zoom = (_zoom - .1).clamp(.6, 1.5)),
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  '${(_zoom * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _zoom = (_zoom + .1).clamp(.6, 1.5)),
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _zoom = 1),
                  icon: const Icon(Icons.fit_screen, size: 17),
                  label: const Text('适应画布'),
                ),
                const Spacer(),
                Text(
                  '${_selectedPage + 1} / ${_pages.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showScriptEditor,
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('匹配字幕'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inspector({bool compact = false}) {
    final bubble = _bubble;
    if (bubble == null) {
      return ColoredBox(
        color: AppColors.panel,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.blush,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.pink,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '这张图片还没有可编辑气泡',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _page?.name ?? '请先添加图片',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '原图里已经存在的文字属于图片像素，不能直接编辑。你可以匹配字幕，也可以先添加一个空白气泡。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _showScriptEditor,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('为图片匹配字幕'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _page == null ? null : _addBubble,
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('添加空白气泡'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final page = _page!;
    return ColoredBox(
      color: AppColors.panel,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '气泡属性',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetCurrentPageLayout,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('重置'),
                ),
                IconButton(
                  onPressed: () => setState(() => _inspectorVisible = false),
                  tooltip: '关闭属性面板',
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                switch (bubble.shape) {
                  BubbleShape.ellipse => '对话气泡 · 四向斜角指向尾巴',
                  BubbleShape.rounded => '旁白框 · 浅灰底，无尾巴',
                  BubbleShape.shout => '惊喊气泡 · 尖锐轮廓，适合强烈情绪',
                  BubbleShape.thought => '心理气泡 · 云朵主体，圆点指向角色',
                  BubbleShape.whisper => '耳语气泡 · 虚线轮廓，四向指向尾巴',
                },
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            if (!compact) ...[
              const SizedBox(height: 4),
              const Text(
                '文本内容',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
            ],
            TextFormField(
              key: ValueKey(
                '${page.name}-$_selectedBubble-${bubble.caption.text}',
              ),
              initialValue: bubble.caption.text,
              minLines: compact ? 1 : 3,
              maxLines: compact ? 2 : 5,
              maxLength: 200,
              contextMenuBuilder: buildAppTextContextMenu,
              onTap: _remember,
              onChanged: (value) => _replaceBubble(
                bubble.copyWith(caption: bubble.caption.copyWith(text: value)),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '气泡样式',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final shape in const [
                  BubbleShape.ellipse,
                  BubbleShape.rounded,
                  BubbleShape.thought,
                  BubbleShape.whisper,
                  BubbleShape.shout,
                ])
                  SizedBox(
                    width: 58,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: _shapeButton(shape, bubble),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                const SizedBox(
                  width: 70,
                  child: Text(
                    '字体',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: bubble.fontFamily,
                    items: [
                      ...const [
                        ('Microsoft YaHei', '微软雅黑'),
                        ('SimSun', '宋体'),
                        ('SimHei', '黑体'),
                        ('KaiTi', '楷体'),
                        ('Arial', 'Arial'),
                        ('Noto Sans CJK SC', 'Noto Sans'),
                      ].map(
                        (item) => DropdownMenuItem(
                          value: item.$1,
                          child: Text(
                            item.$2,
                            style: TextStyle(fontFamily: item.$1),
                          ),
                        ),
                      ),
                      for (final family in _importedFonts)
                        DropdownMenuItem(
                          value: family,
                          child: Text(
                            '已导入 · $family',
                            style: TextStyle(fontFamily: family),
                          ),
                        ),
                      if (!_importedFonts.contains(bubble.fontFamily) &&
                          !const {
                            'Microsoft YaHei',
                            'SimSun',
                            'SimHei',
                            'KaiTi',
                            'Arial',
                            'Noto Sans CJK SC',
                          }.contains(bubble.fontFamily))
                        DropdownMenuItem(
                          value: bubble.fontFamily,
                          child: Text(bubble.fontFamily),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _replaceBubble(
                          bubble.copyWith(fontFamily: value),
                          remember: true,
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  onPressed: _importFont,
                  tooltip: '导入 TTF / OTF 字体',
                  icon: const Icon(Icons.file_open_outlined, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 70,
                  child: Text(
                    '字体颜色',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final color in const [
                  Color(0xff141518),
                  Color(0xffffffff),
                  Color(0xffd52f4f),
                  Color(0xff356db5),
                  Color(0xffe94d72),
                  Color(0xffe7a329),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: InkWell(
                      onTap: () => _replaceBubble(
                        bubble.copyWith(fontColorValue: color.value),
                        remember: true,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: bubble.fontColorValue == color.value
                                ? AppColors.pink
                                : AppColors.line,
                            width: bubble.fontColorValue == color.value ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton.outlined(
                  onPressed: () => _pickFontColor(bubble),
                  tooltip: '全部颜色 / 输入 HEX',
                  icon: const Icon(Icons.colorize, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _sliderRow(
              '字体大小',
              bubble.fontSize,
              18,
              64,
              (value) => _replaceBubble(bubble.copyWith(fontSize: value)),
            ),
            _sliderRow(
              '行间距',
              bubble.lineHeight,
              1,
              1.8,
              (value) => _replaceBubble(bubble.copyWith(lineHeight: value)),
            ),
            _sliderRow(
              '描边粗细',
              bubble.strokeWidth,
              1,
              8,
              (value) => _replaceBubble(bubble.copyWith(strokeWidth: value)),
            ),
            if (bubbleHasPointer(bubble.shape)) ...[
              const SizedBox(height: 8),
              const Text(
                '指向方向',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final item in const [
                    (Icons.south_west, TailDirection.downLeft, '左下'),
                    (Icons.north_west, TailDirection.upLeft, '左上'),
                    (Icons.north_east, TailDirection.upRight, '右上'),
                    (Icons.south_east, TailDirection.downRight, '右下'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: IconButton.filledTonal(
                          onPressed: () => _replaceBubble(
                            bubble.copyWith(tailDirection: item.$2),
                            remember: true,
                          ),
                          tooltip: item.$3,
                          icon: Icon(item.$1, size: 19),
                          style: IconButton.styleFrom(
                            backgroundColor: bubble.tailDirection == item.$2
                                ? AppColors.blush
                                : Colors.white,
                            side: BorderSide(
                              color: bubble.tailDirection == item.$2
                                  ? AppColors.pink
                                  : AppColors.line,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '尾部位置固定，不可拖动',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  _remember();
                  for (final p in _pages) {
                    for (var i = 0; i < p.placements.length; i++) {
                      p.placements[i] = p.placements[i].copyWith(
                        fontSize: bubble.fontSize,
                        lineHeight: bubble.lineHeight,
                        strokeWidth: bubble.strokeWidth,
                        shape: bubble.shape,
                        fontFamily: bubble.fontFamily,
                        fontColorValue: bubble.fontColorValue,
                        tailDirection: bubble.tailDirection,
                      );
                    }
                  }
                  setState(() => _dirty = true);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('样式已应用到全部气泡')));
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('应用样式到全部气泡'),
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _deleteBubble();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除此气泡'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _shapeButton(BubbleShape shape, BubblePlacement bubble) {
    final selected = shape == bubble.shape;
    final icon = switch (shape) {
      BubbleShape.ellipse => Icons.chat_bubble_outline,
      BubbleShape.rounded => Icons.rounded_corner,
      BubbleShape.shout => Icons.brightness_7_outlined,
      BubbleShape.thought => Icons.cloud_outlined,
      BubbleShape.whisper => Icons.blur_on_outlined,
    };
    final label = switch (shape) {
      BubbleShape.ellipse => '对话气泡',
      BubbleShape.rounded => '旁白框',
      BubbleShape.shout => '惊喊气泡',
      BubbleShape.thought => '心理气泡',
      BubbleShape.whisper => '耳语气泡',
    };
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? AppColors.blush : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: selected ? AppColors.pink : AppColors.line),
        ),
        child: InkWell(
          onTap: () =>
              _replaceBubble(bubble.copyWith(shape: shape), remember: true),
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.pink : AppColors.ink,
                ),
                const SizedBox(height: 2),
                Text(
                  label.replaceAll('气泡', ''),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.pink : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChangeStart: (_) => _remember(),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                label == '尾巴位置'
                    ? '${(value * 100).round()}%'
                    : value.toStringAsFixed(label == '行间距' ? 1 : 0),
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}
