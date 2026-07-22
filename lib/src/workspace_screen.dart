import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'app_localization.dart';
import 'bcs_script_exporter.dart';
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
    Iterable<int> pageIndexes,
  ) =>
      _ProjectSnapshot(
        pages: {
          for (final index in pageIndexes)
            index: _PageEditState.capture(pages[index]),
        },
        selectedPage: selectedPage,
        selectedBubble: selectedBubble,
      );

  final Map<int, _PageEditState> pages;
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

enum _BubbleStyleProperty {
  fontFamily,
  fontColor,
  fontSize,
  lineHeight,
  strokeWidth,
  shape,
  tailDirection,
  fillOpacity,
}

SnackBar _quickFeedback(String message) => SnackBar(
      content: LText(message),
      duration: const Duration(milliseconds: 700),
    );

enum _ExistingImageChoice { overwrite, overwriteAll, skip, cancel }

enum WorkspaceLayoutMode { desktop, mobilePortrait, mobileLandscape }

WorkspaceLayoutMode workspaceLayoutModeFor(Size size) {
  if (size.width >= 1180) return WorkspaceLayoutMode.desktop;
  return size.height >= size.width
      ? WorkspaceLayoutMode.mobilePortrait
      : WorkspaceLayoutMode.mobileLandscape;
}

Size workspaceDialogContentSize(
  Size viewport, {
  required double maxWidth,
  required double maxHeight,
}) =>
    Size(
      math.min(maxWidth, math.max(220, viewport.width - 48)),
      math.min(maxHeight, math.max(120, viewport.height - 190)),
    );

Widget workspaceDialogContent(
  BuildContext context, {
  required double maxWidth,
  required double maxHeight,
  required Widget child,
}) {
  final size = workspaceDialogContentSize(
    MediaQuery.sizeOf(context),
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
  return SizedBox(width: size.width, height: size.height, child: child);
}

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
  final ValueNotifier<int> _canvasRevision = ValueNotifier(0);
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
  bool _selectionVisible = false;
  bool _structureDirty = false;
  int _editRevision = 0;
  AppSettings _settings = const AppSettings();
  final List<String> _importedFonts = [];
  final Map<String, Uint8List> _fontBytes = {};
  String? _projectThumbnailBase64;
  ui.Image? _activeSourceImage;
  String? _activeSourcePageId;
  String? _loadingSourcePageId;
  int _sourceLoadGeneration = 0;
  int _mobileDestination = 2;

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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _settings = await loadAppSettings();
    if (mounted) setState(() {});
  }

  Future<void> _showSettings() async {
    final settings = await showAppSettingsDialog(context, _settings);
    if (settings == null || !mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _importFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final base = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final family =
        'Imported_${base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}_${bytes.length}';
    if (!_importedFonts.contains(family)) {
      try {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            _quickFeedback('字体无法加载，请确认文件未损坏且格式受支持'),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _importedFonts.add(family);
          _fontBytes[family] = Uint8List.fromList(bytes);
          _markDirty();
          _structureDirty = true;
        });
      }
    }
    final bubble = _bubble;
    if (bubble != null) {
      _replaceBubble(bubble.copyWith(fontFamily: family), remember: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _quickFeedback('字体已导入并应用到当前气泡'),
        );
      }
    }
  }

  Future<void> _pickFontColor(BubblePlacement bubble) async {
    var selected = Color(bubble.fontColorValue);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LText('选择任意字体颜色'),
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
            child: LText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: LText('应用颜色'),
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
    if (_dirty && _pages.isNotEmpty) unawaited(_persistLocalProject());
    _clearActiveSourceImage();
    _disposePages(_pages);
    _canvasRevision.dispose();
    _script.dispose();
    super.dispose();
  }

  void _disposePages(Iterable<ImagePage> pages) {
    for (final page in pages) {
      page.dispose();
    }
  }

  void _clearActiveSourceImage() {
    _sourceLoadGeneration++;
    _activeSourceImage?.dispose();
    _activeSourceImage = null;
    _activeSourcePageId = null;
    _loadingSourcePageId = null;
  }

  Future<void> _loadSelectedPageSource() async {
    final page = _page;
    if (page == null ||
        _activeSourcePageId == page.pageId ||
        _loadingSourcePageId == page.pageId) {
      return;
    }
    final pageId = page.pageId;
    final generation = ++_sourceLoadGeneration;
    final previous = _activeSourceImage;
    if (mounted) {
      setState(() {
        _activeSourceImage = null;
        _activeSourcePageId = null;
        _loadingSourcePageId = pageId;
      });
    }
    previous?.dispose();
    ui.Image source;
    try {
      source = await decodeOriginalImage(page.bytes);
    } catch (_) {
      if (mounted && generation == _sourceLoadGeneration) {
        setState(() => _loadingSourcePageId = null);
      }
      return;
    }
    if (!mounted ||
        generation != _sourceLoadGeneration ||
        _page?.pageId != pageId) {
      source.dispose();
      return;
    }
    setState(() {
      _activeSourceImage = source;
      _activeSourcePageId = pageId;
      _loadingSourcePageId = null;
      _canvasRevision.value++;
    });
  }

  void _markDirty() {
    _editRevision++;
    _dirty = true;
  }

  Future<void> _loadStoredProject() async {
    try {
      final manifest = supportsIncrementalProjectStorage
          ? await loadLocalProjectManifest(widget.projectId)
          : null;
      final legacyBytes =
          manifest == null ? await loadLocalProject(widget.projectId) : null;
      if (manifest == null && legacyBytes == null) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      final project = manifest != null
          ? await decodeProjectManifest(
              manifest,
              (pageId) => loadLocalProjectImage(widget.projectId, pageId),
            )
          : await decodeProject(legacyBytes!);
      final needsMigration =
          manifest == null && supportsIncrementalProjectStorage;
      final thumbnail = project.pages.isEmpty
          ? null
          : await encodeThumbnailBase64(project.pages.first.image);
      final edits = await loadLocalProjectEdits(widget.projectId);
      String? editedScript;
      var recoveredLegacyPages = 0;
      if (edits != null) {
        try {
          final result = applyProjectEdits(edits, project.pages);
          recoveredLegacyPages = result.preservedManifestPages;
          editedScript = result.recoveredLegacyData
              ? buildBcsScript(project.pages)
              : result.script;
        } catch (_) {
          // The full project remains usable even if an optional edit layer fails.
        }
      }
      _ensureBubbleIds(project.pages);
      if (!mounted) {
        _disposePages(project.pages);
        return;
      }
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
        _script.text = editedScript ?? buildBcsScript(project.pages);
        _projectThumbnailBase64 = thumbnail;
        _selectedPage = 0;
        _selectedBubble = 0;
        _selectionVisible = false;
        _processing = false;
        _dirty = needsMigration || recoveredLegacyPages > 0;
        _editRevision = 0;
        _structureDirty = needsMigration;
      });
      unawaited(_loadSelectedPageSource());
      // Opening a project is read-only. In particular, never rewrite the edit
      // layer during load: doing so used to make a stale/empty overlay
      // permanently erase recoverable manifest bubbles.
      if (needsMigration) await _persistLocalProject(forceFull: true);
      if (mounted && recoveredLegacyPages > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          _quickFeedback(
            '已从项目主数据恢复 $recoveredLegacyPages 页气泡；请点击保存确认恢复结果。',
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText('项目无法打开'),
          content: LText('本地项目数据可能已经损坏：$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: LText('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _persistLocalProject({bool forceFull = false}) async {
    if (_pages.isEmpty || _saving) return;
    _saving = true;
    final savingRevision = _editRevision;
    final savingStructure = forceFull || _structureDirty;
    try {
      if (savingStructure) {
        if (supportsIncrementalProjectStorage) {
          await _saveIncrementalProject();
        } else {
          await saveLocalProject(
            widget.projectId,
            widget.projectName,
            encodeProject(_pages, _script.text, fonts: _fontBytes),
            thumbnailBase64: _projectThumbnailBase64,
          );
        }
      }
      await saveLocalProjectEdits(
        widget.projectId,
        widget.projectName,
        encodeProjectEdits(_pages, _script.text),
        thumbnailBase64: _projectThumbnailBase64,
      );
      if (mounted && savingRevision == _editRevision) {
        setState(() {
          _dirty = false;
          if (savingStructure) _structureDirty = false;
        });
      }
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveIncrementalProject() async {
    for (final page in _pages) {
      await saveLocalProjectImage(widget.projectId, page.pageId, page.bytes);
      await Future<void>.delayed(Duration.zero);
    }
    await saveLocalProjectManifest(
      widget.projectId,
      widget.projectName,
      encodeProjectManifest(_pages, _script.text, fonts: _fontBytes),
      thumbnailBase64: _projectThumbnailBase64,
    );
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

  Future<void> _pickImages({bool replaceProject = false}) async {
    final replace = replaceProject || _isDemoProject || _pages.isEmpty;
    if (replaceProject && _dirty && _pages.isNotEmpty && !_isDemoProject) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText('新建图片项目？'),
          content: LText('这会替换当前工程。请先保存需要保留的修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: LText('放弃并新建'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    final pickedFiles = await pickImageFiles();
    if (pickedFiles == null) return;
    setState(() => _processing = true);
    final pages = <ImagePage>[];
    final failed = <String>[];
    final previewDimension = previewDimensionForPageCount(pickedFiles.length);
    for (final file in pickedFiles) {
      final name = file.name;
      final bytes = file.bytes;
      try {
        final sourceBytes = bytes;
        final preview = await decodeImagePreview(
          sourceBytes,
          maxDimension: previewDimension,
        );
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
      ).showSnackBar(SnackBar(content: LText('没有读取到有效图片，请检查文件格式或文件是否损坏。')));
      return;
    }
    if (!mounted) {
      _disposePages(pages);
      return;
    }
    setState(() => _processing = false);
    pages.sort((a, b) => compareNaturalNames(a.name, b.name));
    final orderedPages = await _confirmImageOrder(pages);
    if (orderedPages == null || !mounted) {
      _disposePages(pages);
      return;
    }
    final existingCount = replace ? 0 : _pages.length;
    final selectedPageId = orderedPages.first.pageId;
    final replacedPages =
        replace ? List<ImagePage>.of(_pages) : const <ImagePage>[];
    _clearActiveSourceImage();
    setState(() {
      final merged = mergeImagePages(_pages, orderedPages, replace: replace);
      _pages
        ..clear()
        ..addAll(merged);
      _selectedPage = _pages.indexWhere(
        (page) => page.pageId == selectedPageId,
      );
      _selectedBubble = 0;
      _selectionVisible = false;
      _processing = false;
      if (replace) _projectName = '未命名工程';
      _markDirty();
      _structureDirty = true;
      _isDemoProject = false;
      _undoStack.clear();
      _redoStack.clear();
    });
    unawaited(_loadSelectedPageSource());
    _disposePages(replacedPages);
    _script.text = buildBcsScript(_pages);
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
      ).showSnackBar(SnackBar(content: LText(messages.join(' '))));
    }
  }

  Future<List<ImagePage>?> _confirmImageOrder(List<ImagePage> source) async {
    final ordered = [...source];
    return showDialog<List<ImagePage>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LText('确认图片顺序'),
          content: workspaceDialogContent(
            context,
            maxWidth: 620,
            maxHeight: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText('当前默认按文件名自然排序；可以拖动调整。字幕将严格按确认后的第 1、2、3 张依次对应。'),
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
                        subtitle: LText(
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
              child: LText('取消导入'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [...ordered]),
              child: LText('确认此顺序'),
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
          title: LText('字幕脚本无法应用'),
          content: LText(blocking.take(8).join('\n\n')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: LText('返回修改'),
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
      _selectionVisible = false;
      _markDirty();
    });
    if (migratedLegacy) _script.text = buildBcsScript(_pages);
    final bubbleCount = _pages.fold<int>(
      0,
      (total, page) => total + page.placements.length,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      _quickFeedback(
        '字幕已应用并完成排版：${_pages.length} 张图片，共 $bubbleCount 个气泡。脚本中的矩形坐标和样式已生效。',
      ),
    );
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
          title: LText('字幕格式检查'),
          content: LText(messages.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: LText('返回修改'),
            ),
          ],
        ),
      );
    }
  }

  void _resetCurrentPageLayout() {
    final page = _page;
    if (page == null || page.captions.isEmpty) return;
    _remember(currentPageOnly: true);
    setState(() {
      page.placements = _engine.arrange(
        page.captions,
        imageWidth: page.originalWidth,
        imageHeight: page.originalHeight,
      );
      page.approved = false;
      _selectedBubble = 0;
      _selectionVisible = false;
      _markDirty();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_quickFeedback('仅重置了当前图片的气泡排版'));
  }

  Future<void> _runLayoutStep() async {
    final pagesWithCaptions = _pages.where((page) => page.captions.isNotEmpty);
    if (pagesWithCaptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LText('当前没有可排版字幕，请先进入“字幕”导入或添加气泡。')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LText('重新自动排版'),
        content: LText(
          '将根据图片尺寸重新计算 ${pagesWithCaptions.length} 张图片中的气泡位置。'
          '手动调整过的位置会被替换，但文字、字体、颜色和气泡样式不会改变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: LText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: LText('开始排版'),
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
      _selectionVisible = false;
      _markDirty();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      _quickFeedback(
        '排版完成：${pagesWithCaptions.length} 张图片，共 $bubbleCount 个气泡。可继续手动微调。',
      ),
    );
  }

  void _remember({bool currentPageOnly = false}) {
    if (_pages.isEmpty) return;
    _undoStack.add(
      _ProjectSnapshot.capture(
        _pages,
        _selectedPage,
        _selectedBubble,
        currentPageOnly
            ? [_selectedPage]
            : List.generate(_pages.length, (i) => i),
      ),
    );
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_pages.isEmpty || _undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    _redoStack.add(
      _ProjectSnapshot.capture(
        _pages,
        _selectedPage,
        _selectedBubble,
        snapshot.pages.keys,
      ),
    );
    _restoreSnapshot(snapshot);
  }

  void _redo() {
    if (_pages.isEmpty || _redoStack.isEmpty) return;
    final snapshot = _redoStack.removeLast();
    _undoStack.add(
      _ProjectSnapshot.capture(
        _pages,
        _selectedPage,
        _selectedBubble,
        snapshot.pages.keys,
      ),
    );
    _restoreSnapshot(snapshot);
  }

  void _restoreSnapshot(_ProjectSnapshot snapshot) {
    setState(() {
      for (final entry in snapshot.pages.entries) {
        if (entry.key < _pages.length) entry.value.restore(_pages[entry.key]);
      }
      _selectedPage = snapshot.selectedPage.clamp(0, _pages.length - 1);
      final count = _pages[_selectedPage].placements.length;
      _selectedBubble =
          count == 0 ? 0 : snapshot.selectedBubble.clamp(0, count - 1);
      _selectionVisible = false;
      _markDirty();
    });
    unawaited(_loadSelectedPageSource());
  }

  void _replaceBubble(BubblePlacement bubble, {bool remember = false}) {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    if (remember) _remember(currentPageOnly: true);
    setState(() {
      page.placements[_selectedBubble] = bubble;
      page.captions[_selectedBubble] = bubble.caption;
      page.approved = false;
      _markDirty();
    });
    _canvasRevision.value++;
  }

  void _replaceBubbleDuringDrag(BubblePlacement bubble) {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    page.placements[_selectedBubble] = bubble;
    page.captions[_selectedBubble] = bubble.caption;
    page.approved = false;
    _markDirty();
    _canvasRevision.value++;
  }

  Future<void> _applySelectedStyleToAll(BubblePlacement source) async {
    final selected = <_BubbleStyleProperty>{};
    final labels = <_BubbleStyleProperty, String>{
      _BubbleStyleProperty.fontFamily: '字体',
      _BubbleStyleProperty.fontColor: '字体颜色',
      _BubbleStyleProperty.fontSize: '字体大小',
      _BubbleStyleProperty.lineHeight: '行间距',
      _BubbleStyleProperty.strokeWidth: '描边粗细',
      _BubbleStyleProperty.shape: '气泡样式',
      _BubbleStyleProperty.tailDirection: '尾部方向',
      _BubbleStyleProperty.fillOpacity: '白底透明度',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LText('选择应用到全部气泡的属性'),
          content: SizedBox(
            width: 430,
            height: math.min(470, MediaQuery.sizeOf(context).height * .65),
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(
                        () => selected.addAll(_BubbleStyleProperty.values),
                      ),
                      child: LText('全选'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(selected.clear),
                      child: LText('清空'),
                    ),
                    const Spacer(),
                    LText('已选 ${selected.length} 项'),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      for (final property in _BubbleStyleProperty.values)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(property),
                          title: LText(labels[property]!),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selected.add(property);
                            } else {
                              selected.remove(property);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: LText('取消'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: LText('应用'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _remember();
    var changed = 0;
    for (final page in _pages) {
      for (var i = 0; i < page.placements.length; i++) {
        final target = page.placements[i];
        page.placements[i] = target.copyWith(
          fontFamily: selected.contains(_BubbleStyleProperty.fontFamily)
              ? source.fontFamily
              : null,
          fontColorValue: selected.contains(_BubbleStyleProperty.fontColor)
              ? source.fontColorValue
              : null,
          fontSize: selected.contains(_BubbleStyleProperty.fontSize)
              ? source.fontSize
              : null,
          lineHeight: selected.contains(_BubbleStyleProperty.lineHeight)
              ? source.lineHeight
              : null,
          strokeWidth: selected.contains(_BubbleStyleProperty.strokeWidth)
              ? source.strokeWidth
              : null,
          shape: selected.contains(_BubbleStyleProperty.shape)
              ? source.shape
              : null,
          tailDirection: selected.contains(_BubbleStyleProperty.tailDirection)
              ? source.tailDirection
              : null,
          fillOpacity: selected.contains(_BubbleStyleProperty.fillOpacity)
              ? source.fillOpacity
              : null,
        );
        page.approved = false;
        changed++;
      }
    }
    setState(_markDirty);
    ScaffoldMessenger.of(context).showSnackBar(
      _quickFeedback('已将 ${selected.length} 项属性应用到 $changed 个气泡'),
    );
  }

  void _addBubble() {
    final page = _page;
    if (page == null) return;
    _remember(currentPageOnly: true);
    final index = page.placements.length;
    final caption = CaptionLine(
      speaker: '',
      text: trArgs('新字幕 {index}', {'index': index + 1}),
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
      _selectionVisible = false;
      page.approved = false;
      _markDirty();
    });
  }

  void _duplicateBubble() {
    final page = _page;
    final source = _bubble;
    if (page == null || source == null) return;
    _remember(currentPageOnly: true);
    final caption = source.caption.copyWith(
      text: '${source.caption.text}${tr('（副本）')}',
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
      _selectionVisible = false;
      page.approved = false;
      _markDirty();
    });
  }

  void _deleteBubble() {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    _remember(currentPageOnly: true);
    setState(() {
      page.placements.removeAt(_selectedBubble);
      page.captions.removeAt(_selectedBubble);
      _selectedBubble = page.placements.isEmpty
          ? 0
          : _selectedBubble.clamp(0, page.placements.length - 1);
      _selectionVisible = false;
      page.approved = false;
      _markDirty();
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
    _remember(currentPageOnly: true);
    setState(() {
      final bubble = page.placements.removeAt(_selectedBubble);
      final caption = page.captions.removeAt(_selectedBubble);
      page.placements.insert(target, bubble);
      page.captions.insert(target, caption);
      _selectedBubble = target;
      page.approved = false;
      _markDirty();
    });
  }

  void _selectPage(int index) {
    setState(() {
      _selectedPage = index;
      _selectedBubble = 0;
      _selectionVisible = false;
      _undoStack.clear();
      _redoStack.clear();
    });
    unawaited(_loadSelectedPageSource());
  }

  Future<void> _exportAll() async {
    if (_pages.isEmpty || _exporting) return;
    final selectedIndexes = await _chooseExportPages();
    if (selectedIndexes == null || selectedIndexes.isEmpty || !mounted) return;
    if (!await _confirmLargeExport(selectedIndexes) || !mounted) return;
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
      for (final index in selectedIndexes) {
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
        await Future<void>.delayed(Duration.zero);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _quickFeedback(
            '导出完成：已直接写入 $exported 张 PNG${skipped == 0 ? '' : '，跳过 $skipped 张'}\n$directory',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText('导出失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<bool> _confirmLargeExport(List<int> indexes) async {
    var largestBytes = 0;
    ImagePage? largestPage;
    for (final index in indexes) {
      final page = _pages[index];
      final estimate = page.originalWidth * page.originalHeight * 4;
      if (estimate > largestBytes) {
        largestBytes = estimate;
        largestPage = page;
      }
    }
    const warningThreshold = 220 * 1024 * 1024;
    if (largestBytes < warningThreshold || largestPage == null) return true;
    final megabytes = (largestBytes / 1024 / 1024).round();
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: LText('检测到超大图片'),
            content: LText(
              '${largestPage!.name} 为 ${largestPage.originalWidth} × ${largestPage.originalHeight}。'
              '单张渲染画布至少需要约 $megabytes MB 内存，PNG 编码期间还会额外占用内存。\n\n'
              '软件会逐张导出且使用二进制写盘，但该图片编码时仍可能短暂停顿。建议先关闭其他大型程序。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: LText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: LText('继续逐张导出'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<List<int>?> _chooseExportPages() async {
    final selected = <int>{for (var i = 0; i < _pages.length; i++) i};
    return showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LText('选择要导出的图片'),
          content: SizedBox(
            width: 560,
            height: math.min(520, MediaQuery.sizeOf(context).height * .68),
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(List.generate(_pages.length, (i) => i));
                      }),
                      child: LText('全选'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(selected.clear),
                      child: LText('清空'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..add(_selectedPage);
                      }),
                      child: LText('仅当前图片'),
                    ),
                    const Spacer(),
                    LText('已选 ${selected.length} / ${_pages.length}'),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return CheckboxListTile(
                        value: selected.contains(index),
                        controlAffinity: ListTileControlAffinity.leading,
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: RawImage(
                              image: page.image,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        title: Text('${index + 1}. ${page.name}'),
                        subtitle: LText(
                          '${page.originalWidth} × ${page.originalHeight} · ${page.placements.length} 个气泡',
                        ),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selected.add(index);
                          } else {
                            selected.remove(index);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: LText('取消'),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        selected.toList()..sort(),
                      ),
              icon: const Icon(Icons.folder_open_outlined),
              label: LText('选择目录并导出 ${selected.length} 张'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_ExistingImageChoice> _askExistingImage(String fileName) async {
    return await showDialog<_ExistingImageChoice>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: LText('图片已存在'),
            content: LText('“$fileName”已在导出目录中。是否用当前修改后的成图覆盖它？'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.cancel),
                child: LText('取消导出'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.skip),
                child: LText('跳过此图'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.overwriteAll),
                child: LText('全部覆盖'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _ExistingImageChoice.overwrite),
                child: LText('覆盖此图'),
              ),
            ],
          ),
        ) ??
        _ExistingImageChoice.cancel;
  }

  Future<void> _saveProject() async {
    if (_pages.isEmpty || _saving) return;
    setState(() => _saving = true);
    final savingRevision = _editRevision;
    try {
      final projectBytes = encodeProject(
        _pages,
        _script.text,
        fonts: _fontBytes,
      );
      final safeName =
          _projectName == '未命名工程' ? '漫画气泡字幕工程.bcs.json' : _projectName;
      final path = await saveBinaryFile(
        title: tr('保存气泡字幕工程'),
        fileName:
            safeName.endsWith('.bcs.json') ? safeName : '$safeName.bcs.json',
        bytes: projectBytes,
        kind: 'project',
      );
      if (!mounted || path == null) return;
      if (supportsIncrementalProjectStorage) {
        await _saveIncrementalProject();
      } else {
        await saveLocalProject(
          widget.projectId,
          widget.projectName,
          projectBytes,
          thumbnailBase64: _projectThumbnailBase64,
        );
      }
      await saveLocalProjectEdits(
        widget.projectId,
        widget.projectName,
        encodeProjectEdits(_pages, _script.text),
        thumbnailBase64: _projectThumbnailBase64,
      );
      if (!mounted) return;
      if (savingRevision == _editRevision) {
        setState(() {
          _dirty = false;
          _structureDirty = false;
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(_quickFeedback('工程已保存：$path'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText('保存工程失败：$error')));
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
          title: LText('打开其他工程？'),
          content: LText('当前工程有未保存修改。继续打开会放弃这些修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: LText('放弃并打开'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    ProjectData? decodedProject;
    try {
      final file = await openProjectFile();
      if (file == null) return;
      setState(() => _processing = true);
      final project = decodedProject = await decodeProject(file.bytes);
      final thumbnail = project.pages.isEmpty
          ? null
          : await encodeThumbnailBase64(project.pages.first.image);
      _ensureBubbleIds(project.pages);
      if (!mounted) {
        _disposePages(project.pages);
        decodedProject = null;
        return;
      }
      final replacedPages = List<ImagePage>.of(_pages);
      _clearActiveSourceImage();
      setState(() {
        _pages
          ..clear()
          ..addAll(project.pages);
        _script.text = buildBcsScript(project.pages);
        _projectThumbnailBase64 = thumbnail;
        _selectedPage = 0;
        _selectedBubble = 0;
        _selectionVisible = false;
        _markDirty();
        _structureDirty = true;
        _isDemoProject = false;
        _processing = false;
        _undoStack.clear();
        _redoStack.clear();
      });
      unawaited(_loadSelectedPageSource());
      _disposePages(replacedPages);
      decodedProject = null;
      await _persistLocalProject(forceFull: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(_quickFeedback('已打开工程：${file.name}'));
    } catch (error) {
      if (decodedProject != null) _disposePages(decodedProject.pages);
      if (!mounted) return;
      setState(() => _processing = false);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText('无法打开工程'),
          content: LText('$error\n\n请确认文件由本软件生成，且内容未被破坏。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: LText('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showScriptEditor() async {
    final draft = TextEditingController(text: _script.text);
    try {
      final appliedScript = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText('匹配字幕脚本'),
          content: workspaceDialogContent(
            context,
            maxWidth: 620,
            maxHeight: 460,
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
              label: LText('导入 TXT'),
            ),
            TextButton.icon(
              onPressed: _exportCurrentBcsScript,
              icon: const Icon(Icons.download_outlined),
              label: LText('导出完整 BCS 字幕'),
            ),
            TextButton.icon(
              onPressed: _showFormatGuide,
              icon: const Icon(Icons.rule_outlined),
              label: LText('格式规范'),
            ),
            TextButton.icon(
              onPressed: _showAiScriptGuide,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: LText('AI 生成指南'),
            ),
            TextButton.icon(
              onPressed: () => _showScriptMatchPreview(draft.text),
              icon: const Icon(Icons.fact_check_outlined),
              label: LText('检查匹配'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft.text),
              child: LText('应用并自动排版'),
            ),
          ],
        ),
      );
      if (appliedScript == null || !mounted) return;
      _script.text = appliedScript;
      setState(_markDirty);
      _autoArrange();
    } finally {
      draft.dispose();
    }
  }

  Future<void> _showScriptMatchPreview(String source) async {
    final parsed = parseCaptionScript(source);
    final blocking = validateScriptForPages(parsed, _pages);
    final lines = <String>[];
    if (blocking.isEmpty) {
      for (var index = 0;
          index < _pages.length && index < parsed.sections.length;
          index++) {
        lines.add(
          '图片 ${index + 1} → ${_pages[index].name}：'
          '${parsed.sections[index].captions.length} 个气泡',
        );
      }
      if (lines.length > 12) {
        final hidden = lines.length - 12;
        lines
          ..removeRange(12, lines.length)
          ..add('另有 $hidden 张图片，匹配规则相同。');
      }
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: LText(blocking.isEmpty ? '字幕匹配检查通过' : '字幕匹配检查未通过'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: LText(
              blocking.isEmpty
                  ? [
                      '脚本按 [图片 1]、[图片 2] 的出现顺序对应项目图片，不按文件名匹配。',
                      '',
                      ...lines,
                      if (parsed.warnings.isNotEmpty) '',
                      ...parsed.warnings.take(5),
                    ].join('\n')
                  : blocking.take(10).join('\n\n'),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: LText('知道了'),
          ),
        ],
      ),
    );
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
        ).showSnackBar(SnackBar(content: LText('字幕文件读取失败：$error')));
      }
    }
  }

  Future<void> _exportCurrentBcsScript() async {
    if (_pages.isEmpty) return;
    try {
      final text = buildBcsScript(_pages);
      final path = await saveBinaryFile(
        title: tr('导出完整 BCS 字幕脚本'),
        fileName: bcsScriptFileName(_projectName),
        bytes: Uint8List.fromList(utf8.encode(text)),
        kind: 'text',
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(_quickFeedback('BCS 字幕脚本已保存：$path'));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText('导出失败：$error')));
      }
    }
  }

  String _formatGuideText() {
    const sample = '@格式=BCS顺序字幕脚本\n@版本=2\n@坐标单位=px\n\n'
        '[图片 1]\n@原文件名=example.png\n@原图尺寸=1080x1920\n\n'
        '@气泡ID=p1-b1\n@矩形=80,100,520,260\n@尾巴=右下\n@气泡=对话气泡\n@字体=Noto Sans SC\n@字号=34\n@颜色=#141518\n@行距=1.25\n@描边=2\n@白底透明度=100\nCaption text\n\n';
    return switch (AppLocaleController.instance.languageCode) {
      'en' => '$sample'
          'Notes:\n'
          '• [图片 1], [图片 2] follow the confirmed image order; file names are hints only.\n'
          '• Every section requires the exact @原图尺寸=widthxheight.\n'
          '• @矩形=x,y,width,height uses source-image pixels from top-left 0,0.\n'
          '• Keep @气泡ID stable and unique to preserve manual edits.\n'
          '• @尾巴 only accepts 左上, 右上, 左下, 右下; the tail is fixed and cannot be dragged.\n'
          '• @气泡 only accepts 对话气泡, 心理气泡, 旁白框, 耳语气泡, 惊喊气泡.\n'
          '• @颜色 changes text only. @白底透明度 is 0–100 and changes only the fill.\n'
          '• Leave one blank line between bubble blocks. Protocol fields remain Chinese.',
      'ja' => '$sample'
          '説明：\n'
          '• [图片 1]、[图片 2] は確認済み画像順に対応し、ファイル名はヒントだけです。\n'
          '• 各画像段に正確な @原图尺寸=幅x高さ が必要です。\n'
          '• @矩形=x,y,幅,高さ は元画像ピクセルで、左上が 0,0 です。\n'
          '• @气泡ID は一意かつ安定させ、手動編集を保持します。\n'
          '• @尾巴 は 左上、右上、左下、右下 のみで、しっぽは固定されドラッグできません。\n'
          '• @气泡 は 对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡 のみです。\n'
          '• @颜色 は文字だけ、@白底透明度 は 0～100 で背景だけを変更します。\n'
          '• ブロック間に空行を一つ入れ、プロトコル欄は中国語のままにします。',
      'ko' => '$sample'
          '설명:\n'
          '• [图片 1], [图片 2]는 확인한 이미지 순서에 대응하며 파일명은 힌트일 뿐입니다.\n'
          '• 모든 구간에 정확한 @原图尺寸=너비x높이가 필요합니다.\n'
          '• @矩形=x,y,너비,높이는 원본 픽셀이며 왼쪽 위가 0,0입니다.\n'
          '• @气泡ID는 고유하고 안정적으로 유지해 수동 편집을 보존합니다.\n'
          '• @尾巴는 左上, 右上, 左下, 右下만 허용되며 꼬리는 고정되어 드래그할 수 없습니다.\n'
          '• @气泡는 对话气泡, 心理气泡, 旁白框, 耳语气泡, 惊喊气泡만 허용됩니다.\n'
          '• @颜色은 글자만, @白底透明度는 0–100으로 배경만 변경합니다.\n'
          '• 말풍선 블록 사이에 빈 줄 하나를 두고 프로토콜 필드는 중국어로 유지합니다.',
      'zh_TW' => '$sample'
          '說明：\n'
          '• [图片 1]、[图片 2] 嚴格對應確認後的圖片順序；檔名只作提示。\n'
          '• 每段必須填寫精確的 @原图尺寸=寬x高。\n'
          '• @矩形=x,y,寬,高 使用原圖像素；左上角為 0,0。\n'
          '• @气泡ID 必須唯一且穩定，用於保留手動編輯。\n'
          '• @尾巴 只能使用 左上、右上、左下、右下；尾部固定且不可拖曳。\n'
          '• @气泡 只能使用 对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡。\n'
          '• @颜色 只改變文字；@白底透明度 為 0–100，只影響底色。\n'
          '• 氣泡區塊之間留一個空行；協定欄位保持簡體中文。',
      _ => '$sample'
          '说明：\n'
          '• [图片 1]、[图片 2] 严格对应确认后的图片顺序；文件名只作提示。\n'
          '• 每张必须填写准确的 @原图尺寸=宽x高。\n'
          '• @矩形=x,y,宽,高 使用原图像素；左上角为 0,0。\n'
          '• @气泡ID 必须唯一且稳定，用于保留手工编辑。\n'
          '• @尾巴 只能使用左上、右上、左下、右下；尾部固定不可拖动。\n'
          '• @气泡 只能使用对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡。\n'
          '• @颜色 只改变文字；@白底透明度 为 0–100，只影响底色。\n'
          '• 每个气泡块之间留一个空行。',
    };
  }

  void _showFormatGuide() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText('精准字幕格式规范'),
          content: workspaceDialogContent(
            context,
            maxWidth: 700,
            maxHeight: 540,
            child: SingleChildScrollView(
              child: SelectableText(
                _formatGuideText(),
                style: const TextStyle(
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
              child: LText('知道了'),
            ),
          ],
        ),
      );

  String _currentProjectContext() {
    final language = AppLocaleController.instance.languageCode;
    final images = _pages.indexed
        .map(
          (entry) => trArgs(
            '图片 {index}：{name}，原图尺寸={width}x{height}',
            {
              'index': entry.$1 + 1,
              'name': entry.$2.name,
              'width': entry.$2.originalWidth,
              'height': entry.$2.originalHeight,
            },
            languageCode: language,
          ),
        )
        .join('\n');
    return '# ${tr('当前项目的精确输入', languageCode: language)}\n\n'
        '${tr('下面的数据由软件直接生成。图片顺序和尺寸是强制约束，不允许 AI 修改或重新排序。', languageCode: language)}\n\n'
        '## ${tr('图片顺序与原图尺寸', languageCode: language)}\n\n$images\n\n'
        '## ${tr('当前项目完整模板', languageCode: language)}\n\n'
        '```text\n${buildBcsScript(_pages)}\n```\n\n'
        '${tr('请把实际图片、需要加入的对白或旁白，与以上规范和模板一起提供给 AI。AI 必须只返回最终的 BCS 纯文本脚本。', languageCode: language)}';
  }

  Future<void> _showAiScriptGuide() async {
    final language = AppLocaleController.instance.languageCode;
    final guideAsset = switch (language) {
      'zh_TW' => 'guides/ai_guide_zh_TW.md',
      'en' => 'guides/ai_guide_en.md',
      'ja' => 'guides/ai_guide_ja.md',
      'ko' => 'guides/ai_guide_ko.md',
      _ => 'AI字幕脚本生成指南.md',
    };
    final exactGuide = await rootBundle.loadString(guideAsset);
    if (!mounted) return;
    final prompt = '$exactGuide\n\n---\n\n${_currentProjectContext()}';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: LText('完整 AI 字幕脚本生成指南'),
        content: workspaceDialogContent(
          context,
          maxWidth: 760,
          maxHeight: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  '以下内容使用当前界面的 AI 指南语言，并在末尾附加当前项目的真实顺序、原图尺寸和完整模板。',
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
            child: LText('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: prompt));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  _quickFeedback('完整规范、图片顺序、原图尺寸和当前模板已复制'),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: LText('复制精确规范 + 当前模板'),
          ),
        ],
      ),
    );
  }

  void _showHelp() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.menu_book_outlined, color: AppColors.pink),
              const SizedBox(width: 10),
              LText('使用指南'),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: LText(
              '1. 软件启动后先进入项目页。可以创建、删除或切换项目；名称留空时会按创建时间自动命名。\n\n2. 点击“添加图片”后，图片默认按文件名自然排序，例如 1、2、10。可以在顺序确认窗口继续拖动调整。\n\n3. 点击顶部“字幕”。每个 [图片 N] 段必须包含 @原图尺寸；气泡使用原图像素 @矩形=x,y,宽,高。字幕只按确认顺序对应，不按文件名匹配。\n\n4. 字幕编辑器采用草稿模式；点击取消不会改变工程。稳定的 @气泡ID 可在再次应用时保留手工位置和样式。\n\n5. 单击气泡会立即显示选框；单击画布空白处会关闭选框，直到再次单击气泡。右侧可修改文字、形状、字体、颜色、字号、行距、描边和尾巴方向。\n\n6. 项目不再持续自动保存。点击右上角保存按钮，或切换回项目页时保存一次。导出位于右上角，不属于编辑流程。\n\n图片和字幕始终只在当前设备处理，不会上传。',
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showFormatGuide();
              },
              icon: const Icon(Icons.rule_outlined),
              label: LText('精准格式'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: LText('知道了'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final layoutMode = workspaceLayoutModeFor(MediaQuery.sizeOf(context));
    final desktop = layoutMode == WorkspaceLayoutMode.desktop;
    final portrait = layoutMode == WorkspaceLayoutMode.mobilePortrait;
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
          bottomNavigationBar:
              portrait && !_processing ? _mobileNavigationBar() : null,
          body: SafeArea(
            child: _processing
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      desktop ? _header(true) : _mobileHeader(portrait),
                      const Divider(height: 1),
                      Expanded(
                        child: switch (layoutMode) {
                          WorkspaceLayoutMode.desktop => _desktopBody(),
                          WorkspaceLayoutMode.mobilePortrait =>
                            _mobilePortraitBody(),
                          WorkspaceLayoutMode.mobileLandscape =>
                            _mobileLandscapeBody(),
                        },
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _mobileHeader(bool portrait) => Container(
        height: portrait ? 60 : 56,
        color: AppColors.panel,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: _returnToProjects,
              tooltip: tr('切换项目'),
              icon: const Icon(Icons.arrow_back),
            ),
            ClipOval(
              child: Image.asset(
                'assets/mascot.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        _dirty ? Icons.circle : Icons.check_circle,
                        size: 10,
                        color: _dirty ? AppColors.warning : AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      LText(
                        _dirty ? '有未保存修改' : '已保存 · 本地',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _saving ? null : _saveProject,
              tooltip: tr('保存工程'),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
            IconButton(
              onPressed: _exporting ? null : _exportAll,
              tooltip: tr('批量导出'),
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: tr('更多操作'),
              onSelected: (value) {
                switch (value) {
                  case 'exportBcs':
                    _exportCurrentBcsScript();
                  case 'open':
                    _openProject();
                  case 'help':
                    _showHelp();
                  case 'settings':
                    _showSettings();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'exportBcs',
                  enabled: _pages.isNotEmpty,
                  child: LText('导出完整 BCS 字幕'),
                ),
                PopupMenuItem(value: 'open', child: LText('打开工程')),
                PopupMenuItem(value: 'help', child: LText('使用指南')),
                PopupMenuItem(value: 'settings', child: LText('设置')),
              ],
            ),
          ],
        ),
      );

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
                  LText(
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
              Expanded(
                child: LText(
                  '浪白漫画字幕工坊',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900),
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
                  LText(
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
              tooltip: tr('切换项目'),
              icon: const Icon(Icons.grid_view_outlined),
            ),
            if (wide)
              IconButton(
                onPressed: _openProject,
                tooltip: tr('打开工程'),
                icon: const Icon(Icons.folder_open_outlined),
              ),
            IconButton(
              onPressed: _saving ? null : _saveProject,
              tooltip: tr('保存工程'),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
            if (wide) ...[
              IconButton(
                onPressed: _showHelp,
                tooltip: tr('使用指南'),
                icon: const Icon(Icons.help_outline),
              ),
              IconButton(
                onPressed: _showSettings,
                tooltip: tr('设置'),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
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
                label: LText('批量导出'),
              )
            else
              IconButton(
                onPressed: _exporting ? null : _exportAll,
                tooltip: tr('批量导出'),
                icon: const Icon(Icons.file_download_outlined),
              ),
            PopupMenuButton<String>(
              tooltip: tr('更多操作'),
              onSelected: (value) {
                switch (value) {
                  case 'exportBcs':
                    _exportCurrentBcsScript();
                  case 'open':
                    _openProject();
                  case 'help':
                    _showHelp();
                  case 'settings':
                    _showSettings();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'exportBcs',
                  enabled: _pages.isNotEmpty,
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: LText('导出完整 BCS 字幕'),
                  ),
                ),
                if (!wide)
                  PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: const Icon(Icons.folder_open_outlined),
                      title: LText('打开工程'),
                    ),
                  ),
                if (!wide)
                  PopupMenuItem(
                    value: 'help',
                    child: ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: LText('使用指南'),
                    ),
                  ),
                if (!wide)
                  PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: LText('设置'),
                    ),
                  ),
              ],
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
                            LText(
                              items[i].$2,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            LText(
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

  Widget _mobilePortraitBody() => _workspace(compact: true);

  Widget _mobileLandscapeBody() => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;
          final pagesWidth = narrow ? 184.0 : 224.0;
          final inspectorWidth = narrow ? 224.0 : 284.0;
          return Row(
            children: [
              SizedBox(
                width: pagesWidth,
                child: _mobilePagePanel(compact: true),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _workspace(compact: true)),
              const VerticalDivider(width: 1),
              SizedBox(
                width: inspectorWidth,
                child: _inspector(compact: true, allowClose: false),
              ),
            ],
          );
        },
      );

  Widget _mobileNavigationBar() => NavigationBar(
        height: 64,
        selectedIndex: _mobileDestination,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _openMobileDestination,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_outlined),
            selectedIcon: Icon(Icons.collections),
            label: '图片',
          ),
          NavigationDestination(
            icon: Icon(Icons.subtitles_outlined),
            selectedIcon: Icon(Icons.subtitles),
            label: '字幕',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit),
            label: '画布',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_fix_high_outlined),
            selectedIcon: Icon(Icons.auto_fix_high),
            label: '排版',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '属性',
          ),
        ],
      );

  Future<void> _openMobileDestination(int index) async {
    setState(() => _mobileDestination = index);
    switch (index) {
      case 0:
        await _showMobilePagesSheet();
      case 1:
        await _showScriptEditor();
      case 2:
        return;
      case 3:
        await _runLayoutStep();
      case 4:
        await _showMobileInspectorSheet();
    }
    if (mounted) setState(() => _mobileDestination = 2);
  }

  Future<void> _showMobilePagesSheet() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => DraggableScrollableSheet(
          initialChildSize: .72,
          minChildSize: .38,
          maxChildSize: .94,
          expand: false,
          builder: (context, controller) => _mobileSheet(
            child: _mobilePagePanel(
              controller: controller,
              onPageSelected: () => Navigator.pop(sheetContext),
            ),
          ),
        ),
      );

  Future<void> _showMobileInspectorSheet() {
    if (_bubble == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        _quickFeedback('请先点击一个气泡，再打开属性'),
      );
      return Future.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .68,
        minChildSize: .34,
        maxChildSize: .96,
        expand: false,
        builder: (context, controller) => _mobileSheet(
          child: _inspector(
            compact: true,
            controller: controller,
            onClose: () => Navigator.pop(sheetContext),
          ),
        ),
      ),
    );
  }

  Widget _mobileSheet({required Widget child}) => Material(
        color: AppColors.panel,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: child),
          ],
        ),
      );

  Widget _mobilePagePanel({
    ScrollController? controller,
    VoidCallback? onPageSelected,
    bool compact = false,
  }) {
    final matched = _pages.where((page) => page.captions.isNotEmpty).length;
    return ColoredBox(
      color: AppColors.panel,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 10, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: LText(
                    '图片 · ${_pages.length} 张',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _statusPill(
                  Icons.subtitles_outlined,
                  '$matched/${_pages.length}',
                  matched == _pages.length && _pages.isNotEmpty
                      ? AppColors.success
                      : AppColors.muted,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _pages.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: () => _pickImages(),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: LText('添加图片'),
                    ),
                  )
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    itemCount: _pages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      final selected = index == _selectedPage;
                      return Material(
                        color: selected ? AppColors.blush : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                          side: BorderSide(
                            color:
                                selected ? AppColors.pink : Colors.transparent,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () {
                            _selectPage(index);
                            onPageSelected?.call();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: RawImage(
                                    image: page.image,
                                    width: compact ? 52 : 64,
                                    height: compact ? 52 : 64,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${index + 1}. ${page.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      LText(
                                        page.captions.isEmpty
                                            ? '等待匹配字幕'
                                            : '${page.captions.length} 条字幕',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: page.captions.isEmpty
                                              ? AppColors.muted
                                              : AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: AppColors.pink,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImages(),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 12,
                      ),
                    ),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: LText('添加'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _showScriptEditor,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 12,
                      ),
                    ),
                    icon: const Icon(Icons.link),
                    label: LText('匹配字幕'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                Expanded(
                  child: LText(
                    '章节：第01话 初遇',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                LText(
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
                LText(
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
                          child: LText(
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
                                preview.isEmpty ? tr('等待匹配字幕') : preview,
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
                                    child: LText(
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
                                  LText(
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
                    label: LText('添加图片'),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('更多图片选项'),
                  onSelected: (value) {
                    if (value == 'replace') {
                      _pickImages(replaceProject: true);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'replace', child: LText('清空图片并重新导入')),
                  ],
                ),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _showScriptEditor,
                    icon: const Icon(Icons.link, size: 18),
                    label: LText('匹配字幕'),
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
            LText(
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

  Widget _compactCanvasToolbar(ImagePage page) => Container(
        height: 44,
        padding: const EdgeInsets.only(left: 10, right: 2),
        color: AppColors.panel,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedPage + 1}. ${page.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _showRendered = !_showRendered),
              tooltip: tr(_showRendered ? '查看原图' : '查看渲染'),
              icon: Icon(
                _showRendered ? Icons.visibility : Icons.visibility_off,
                size: 19,
              ),
            ),
            IconButton(
              onPressed: _undoStack.isEmpty ? null : _undo,
              tooltip: tr('撤销'),
              icon: const Icon(Icons.undo, size: 19),
            ),
            IconButton(
              onPressed: _redoStack.isEmpty ? null : _redo,
              tooltip: tr('重做'),
              icon: const Icon(Icons.redo, size: 19),
            ),
            IconButton(
              onPressed: _addBubble,
              tooltip: tr('新建气泡'),
              icon: const Icon(Icons.add_comment_outlined, size: 19),
            ),
            IconButton(
              onPressed: _bubble == null ? null : _showMobileInspectorSheet,
              tooltip: tr('气泡属性'),
              icon: const Icon(Icons.tune, size: 19),
            ),
          ],
        ),
      );

  Widget _workspace({bool compact = false}) {
    final page = _page;
    if (page == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _pickImages(),
          icon: const Icon(Icons.folder_open),
          label: LText('导入图片'),
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
                    child: LText(
                      '当前：第01话 · ${page.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  LText(
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
                    child: LText('原图'),
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
                    child: LText('渲染'),
                  ),
                  const VerticalDivider(indent: 11, endIndent: 11),
                  IconButton(
                    onPressed: _undoStack.isEmpty ? null : _undo,
                    tooltip: tr('撤销'),
                    icon: const Icon(Icons.undo, size: 20),
                  ),
                  IconButton(
                    onPressed: _redoStack.isEmpty ? null : _redo,
                    tooltip: tr('重做'),
                    icon: const Icon(Icons.redo, size: 20),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr('气泡编辑命令'),
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
                      PopupMenuItem(
                        value: 'new',
                        child: ListTile(
                          leading: const Icon(Icons.add_comment_outlined),
                          title: LText('新建气泡'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        enabled: _bubble != null,
                        child: ListTile(
                          leading: const Icon(Icons.content_copy_outlined),
                          title: LText('复制气泡'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'back',
                        enabled: _bubble != null,
                        child: ListTile(
                          leading: const Icon(Icons.flip_to_back_outlined),
                          title: LText('下移一层'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'front',
                        enabled: _bubble != null,
                        child: ListTile(
                          leading: const Icon(Icons.flip_to_front_outlined),
                          title: LText('上移一层'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: _bubble != null,
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: LText('删除气泡'),
                          dense: true,
                        ),
                      ),
                      if (!_inspectorVisible)
                        PopupMenuItem(
                          value: 'inspector',
                          enabled: _bubble != null,
                          child: ListTile(
                            leading: const Icon(Icons.tune),
                            title: LText('打开属性面板'),
                            dense: true,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  LText(
                    '${page.originalWidth} × ${page.originalHeight}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            )
          else
            _compactCanvasToolbar(page),
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
                  return hitTestBubble(page.placements, point);
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

                void applyPointerSelection(
                  (int, _DragMode)? interaction, {
                  bool beginDrag = false,
                }) {
                  setState(() {
                    if (interaction == null) {
                      _selectionVisible = false;
                      _dragMode = null;
                      _hoverMode = null;
                      return;
                    }
                    _selectedBubble = interaction.$1;
                    _selectionVisible = true;
                    _inspectorVisible = true;
                    if (beginDrag) {
                      _dragMode = interaction.$2;
                      _hoverMode = interaction.$2;
                    }
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _canvasRevision.value++;
                  });
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
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          applyPointerSelection(
                            interactionAt(event.localPosition),
                          );
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onTapUp: (details) {
                            applyPointerSelection(
                              interactionAt(details.localPosition),
                            );
                          },
                          onPanStart: (details) {
                            final interaction = interactionAt(
                              details.localPosition,
                            );
                            if (interaction == null) return;
                            applyPointerSelection(
                              interaction,
                              beginDrag: true,
                            );
                            _remember(currentPageOnly: true);
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
                            _replaceBubbleDuringDrag(
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
                              border:
                                  Border.all(color: AppColors.ink, width: 2),
                              color: Colors.white,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                RepaintBoundary(
                                  child: CustomPaint(
                                    key: ValueKey((
                                      page.pageId,
                                      _selectionVisible ? _selectedBubble : -1,
                                    )),
                                    painter: PagePainter(
                                      page: page,
                                      sourceImage:
                                          _activeSourcePageId == page.pageId
                                              ? _activeSourceImage
                                              : null,
                                      showBubbles: _showRendered,
                                      repaint: _canvasRevision,
                                      selectedIndex: !_showRendered ||
                                              !_selectionVisible ||
                                              page.placements.isEmpty
                                          ? null
                                          : _selectedBubble,
                                    ),
                                  ),
                                ),
                                if (_loadingSourcePageId == page.pageId)
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(.72),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(
                                              width: 13,
                                              height: 13,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            LText(
                                              '正在加载高清原图',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
            height: compact ? 48 : 54,
            padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 14),
            color: AppColors.panel,
            child: Row(
              children: [
                IconButton(
                  onPressed: () =>
                      setState(() => _zoom = (_zoom - .1).clamp(.6, 1.5)),
                  icon: const Icon(Icons.remove),
                ),
                LText(
                  '${(_zoom * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _zoom = (_zoom + .1).clamp(.6, 1.5)),
                  icon: const Icon(Icons.add),
                ),
                if (!compact) const SizedBox(width: 8),
                if (!compact)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _zoom = 1),
                    icon: const Icon(Icons.fit_screen, size: 17),
                    label: LText('适应画布'),
                  ),
                const Spacer(),
                LText(
                  '${_selectedPage + 1} / ${_pages.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (compact)
                  IconButton(
                    onPressed: _showScriptEditor,
                    tooltip: tr('匹配字幕'),
                    icon: const Icon(Icons.description_outlined, size: 19),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _showScriptEditor,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: LText('匹配字幕'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inspector({
    bool compact = false,
    ScrollController? controller,
    VoidCallback? onClose,
    bool allowClose = true,
  }) {
    final bubble = _bubble;
    if (bubble == null) {
      return ColoredBox(
        color: AppColors.panel,
        child: Center(
          child: SingleChildScrollView(
            controller: controller,
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
                  LText(
                    '这张图片还没有可编辑气泡',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  LText(
                    _page?.name ?? '请先添加图片',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LText(
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
                      label: LText('为图片匹配字幕'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _page == null ? null : _addBubble,
                      icon: const Icon(Icons.add_comment_outlined),
                      label: LText('添加空白气泡'),
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
        controller: controller,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LText(
                    '气泡属性',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetCurrentPageLayout,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: LText('重置'),
                ),
                if (allowClose)
                  IconButton(
                    onPressed: onClose ??
                        () => setState(() => _inspectorVisible = false),
                    tooltip: tr('关闭属性面板'),
                    icon: const Icon(Icons.close, size: 19),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            LText(
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
              LText(
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
            LText(
              '气泡样式',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final shape in const [
                  BubbleShape.ellipse,
                  BubbleShape.rounded,
                  BubbleShape.thought,
                  BubbleShape.whisper,
                  BubbleShape.shout,
                ])
                  SizedBox(
                    width: compact ? 48 : 58,
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
                SizedBox(
                  width: 70,
                  child: LText(
                    '字体',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: bubble.fontFamily,
                    items: [
                      ...const [
                        ('Noto Sans SC', '思源黑体'),
                        ('ZCOOL XiaoWei', '站酷小薇体'),
                        ('Ma Shan Zheng', '马善政毛笔体'),
                      ].map(
                        (item) => DropdownMenuItem(
                          value: item.$1,
                          child: LText(
                            item.$2,
                            style: TextStyle(fontFamily: item.$1),
                          ),
                        ),
                      ),
                      for (final family in _importedFonts)
                        DropdownMenuItem(
                          value: family,
                          child: LText(
                            '已导入 · $family',
                            style: TextStyle(fontFamily: family),
                          ),
                        ),
                      if (!_importedFonts.contains(bubble.fontFamily) &&
                          !const {
                            'Noto Sans SC',
                            'ZCOOL XiaoWei',
                            'Ma Shan Zheng',
                          }.contains(bubble.fontFamily))
                        DropdownMenuItem(
                          value: bubble.fontFamily,
                          child: LText(bubble.fontFamily),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _replaceBubble(
                          bubble.copyWith(fontFamily: value),
                          remember: true,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          _quickFeedback('字体已切换，画布已刷新'),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  onPressed: _importFont,
                  tooltip: tr('导入 TTF / OTF / TTC 字体'),
                  icon: const Icon(Icons.file_open_outlined, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 2,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 70,
                  child: LText(
                    '字体颜色',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
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
                  tooltip: tr('全部颜色 / 输入 HEX'),
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
            _sliderRow(
              '白底透明度',
              bubble.fillOpacity * 100,
              0,
              100,
              (value) => _replaceBubble(
                bubble.copyWith(fillOpacity: value / 100),
              ),
              percent: true,
            ),
            if (bubbleHasPointer(bubble.shape)) ...[
              const SizedBox(height: 8),
              LText(
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
                          tooltip: tr(item.$3),
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
              LText(
                '尾部位置固定，不可拖动',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _applySelectedStyleToAll(bubble),
                icon: const Icon(Icons.copy_all_outlined),
                label: LText('选择属性并应用到全部'),
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
                  label: LText('删除此气泡'),
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
      message: tr(label),
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
                LText(
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
    ValueChanged<double> onChanged, {
    bool percent = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: LText(
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
                onChangeStart: (_) => _remember(currentPageOnly: true),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 42,
              child: LText(
                percent
                    ? '${value.round()}%'
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
