import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
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
import 'bubble_text_editor.dart';
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
import 'sticker_library.dart';
import 'text_context_menu.dart';
import 'project_document.dart';
import 'script_merge.dart';
import 'revision_save_queue.dart';
import 'text_layout_service.dart';
import 'font_library.dart';
import 'font_picker.dart';

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
  rotate,
}

enum _CanvasSelection { none, bubble, image }

enum _BubbleStyleProperty {
  fontFamily,
  fontColor,
  fontSize,
  lineHeight,
  strokeWidth,
  shape,
  tailDirection,
  fillOpacity,
  textSizeMode,
  letterSpacing,
  textAlign,
  textStrokeWidth,
  textStrokeColor,
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

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WidgetsBindingObserver {
  final _engine = const LayoutEngine();
  final _script = TextEditingController();
  final List<ImagePage> _pages = [];
  final _history = EditorHistory();
  final _commandFocus = FocusNode(debugLabel: 'ProjectCommands');
  final _documentAssets = DocumentAssetPool();
  ProjectDocument? _document;
  ProjectDocument? _pendingBefore;
  String _commandLabel = '编辑对象';
  String? _commandGroup;
  DateTime? _lastTextChange;
  final _saveQueue = RevisionSaveQueue();
  List<DocumentCommand> get _undoStack => _history.undoEntries;
  List<DocumentCommand> get _redoStack => _history.redoEntries;
  final ValueNotifier<int> _canvasRevision = ValueNotifier(0);
  Timer? _autoSaveTimer;
  ProjectDocument? _lastSavedCheckpoint;
  ProjectDocument? _previousSavedCheckpoint;
  int _selectedPage = 0;
  int _selectedBubble = 0;
  int _selectedImage = 0;
  _CanvasSelection _canvasSelection = _CanvasSelection.none;
  bool _processing = true;
  bool _exporting = false;
  bool _saving = false;
  bool _autoSaving = false;
  bool _autoSaveFailed = false;
  String? _saveError;
  bool _dirty = false;
  bool _isDemoProject = false;
  bool _showRendered = true;
  bool _inspectorVisible = true;
  String _projectName = '未命名工程';
  late String _activeProjectId;
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
  List<StickerAsset> _stickers = const [];
  bool _showChapterText = false;
  final Set<String> _multiSelected = {};
  final _exportProgress = ValueNotifier<int>(0);
  bool _cancelExport = false;
  bool _useBrowserDownloads = false;
  int _exportDone = 0;
  int _exportTotal = 0;
  final List<int> _failedExportIndexes = [];

  static const _autoSaveDelay = Duration(seconds: 1);
  static const _autoSaveRetryDelay = Duration(seconds: 3);

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

  PlacedImage? get _placedImage {
    final page = _page;
    if (page == null || page.placedImages.isEmpty) return null;
    return page
        .placedImages[_selectedImage.clamp(0, page.placedImages.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _projectName = widget.projectName;
    _activeProjectId = widget.projectId;
    _loadStoredProject();
    _loadSettings();
    _loadStickerAssets();
    unawaited(FontLibrary.instance.load().catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_quickFeedback('字体库读取失败：$e'));
      }
    }));
  }

  Future<void> _loadStickerAssets() async {
    final assets = await loadStickerLibrary();
    if (mounted) setState(() => _stickers = assets);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoSaveTimer?.cancel();
      unawaited(_flushAutoSave());
    }
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

  Future<T?> _showTextDialog<T>(TextEditingController controller,
      {required BuildContext context, required WidgetBuilder builder}) {
    final route = DialogRoute<T>(context: context, builder: builder);
    unawaited(route.completed.then((_) => controller.dispose()));
    return Navigator.of(context, rootNavigator: true).push<T>(route);
  }

  Future<void> _importFont() async {
    final bubble = _canvasSelection == _CanvasSelection.bubble ? _bubble : null;
    final asset = await showDialog<FontAsset>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: LText('全局字体库'),
                content: workspaceDialogContent(dialogContext,
                    maxWidth: 760,
                    maxHeight: 620,
                    child: FontPicker(
                        sampleText: bubble?.caption.text ?? '漫画对白：你好，世界！',
                        selectedFamily: bubble?.fontFamily,
                        selectedAssetId: bubble?.fontAssetId,
                        onSelected: (asset) =>
                            Navigator.pop(dialogContext, asset))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: LText('关闭'))
                ]));
    if (asset == null || !mounted || bubble == null) return;
    final current = _bubble;
    if (current == null ||
        current.caption.bubbleId != bubble.caption.bubbleId) {
      return;
    }
    _finishEdit();
    _remember(label: '修改字体');
    if (asset.record.source != FontSource.builtIn) {
      _fontBytes[asset.runtimeFamily] = asset.bytes;
      if (!_importedFonts.contains(asset.runtimeFamily)) {
        _importedFonts.add(asset.runtimeFamily);
      }
      _structureDirty = true;
    }
    _replaceBubble(current.copyWith(
        fontFamily: asset.runtimeFamily,
        fontAssetId: asset.id,
        fontDisplayName: asset.displayName));
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
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    if (_dirty && _pages.isNotEmpty) {
      unawaited(_persistLocalProject(includeManifest: true));
    }
    _clearActiveSourceImage();
    _disposePages(_pages);
    _canvasRevision.dispose();
    _exportProgress.dispose();
    _script.dispose();
    _commandFocus.dispose();
    _history.clear();
    _documentAssets.dispose();
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

  ProjectDocument _captureDocument() =>
      ProjectDocument.capture(_pages, _documentAssets,
          revision: _editRevision,
          script: buildBcsScript(_pages),
          selectedPage: _selectedPage,
          selectedBubble: _selectedBubble,
          fonts: _fontBytes);

  void _synchronizeTextObjects() {
    for (final page in _pages) {
      page.placements = page.placements
          .map((b) => b.copyWith(
                  caption: b.caption.copyWith(
                      layout: CaptionLayoutSpec(
                x: b.x,
                y: b.y,
                width: b.width,
                height: b.height,
                shape: b.shape,
                tailDirection: b.tailDirection,
                fontFamily: b.fontFamily,
                fontDisplayName: b.fontDisplayName,
                fontAssetId: b.fontAssetId,
                fontColorValue: b.fontColorValue,
                fontSize: b.fontSize,
                lineHeight: b.lineHeight,
                textSizeMode: b.textSizeMode,
                textStrokeWidth: b.textStrokeWidth,
                textStrokeColorValue: b.textStrokeColorValue,
                letterSpacing: b.letterSpacing,
                textAlign: b.textAlign,
                styleId: b.styleId,
                strokeWidth: b.strokeWidth,
                fillOpacity: b.fillOpacity,
              ))))
          .toList();
      page.captions = page.placements.map((b) => b.caption).toList();
    }
    _script.text = buildBcsScript(_pages);
  }

  bool _restoringDocument = false;
  void _markDirty() {
    final before = _pendingBefore ?? _document ?? _captureDocument();
    _synchronizeTextObjects();
    _editRevision++;
    final after = _captureDocument();
    if (!_restoringDocument) {
      _history.record(before, after, _commandLabel, group: _commandGroup);
    }
    _pendingBefore = null;
    _document = after;
    _dirty = true;
    _autoSaveFailed = false;
    _saveError = null;
    _canvasRevision.value++;
    _scheduleAutoSave();
  }

  void _finishEdit() {
    _history.finishGroup();
    _commandGroup = null;
    _commandLabel = '编辑对象';
    _pendingBefore = null;
  }

  void _editText(BubblePlacement bubble, String value) {
    if (bubble.caption.text == value) return;
    final now = DateTime.now();
    if (_lastTextChange == null ||
        now.difference(_lastTextChange!).inMilliseconds > 1000) {
      _finishEdit();
    }
    _lastTextChange = now;
    _commandGroup = 'text:${bubble.caption.bubbleId}';
    _commandLabel = '修改文字';
    _replaceBubble(
        bubble.copyWith(caption: bubble.caption.copyWith(text: value)),
        remember: true);
  }

  void _scheduleAutoSave([Duration delay = _autoSaveDelay]) {
    _autoSaveTimer?.cancel();
    if (_pages.isEmpty || _processing || _isDemoProject) return;
    _autoSaveTimer = Timer(
      delay,
      () => unawaited(_runAutoSave()),
    );
  }

  Future<void> _flushAutoSave() async {
    _autoSaveTimer?.cancel();
    if (_dirty) await _runAutoSave();
  }

  Future<void> _runAutoSave() async {
    if (!mounted || _pages.isEmpty || !_dirty || _saving || _autoSaving) {
      if (_dirty && (_saving || _autoSaving)) _scheduleAutoSave();
      return;
    }
    setState(() => _autoSaving = true);
    var failed = false;
    try {
      // A compact manifest checkpoint writes captions and geometry without
      // copying source image bytes again. The edit layer remains a second,
      // independently recoverable copy.
      await _persistLocalProject(includeManifest: true);
    } catch (error) {
      _saveError = error.toString();
      debugPrint('Local project save failed: $error');
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _autoSaving = false;
          _autoSaveFailed = failed;
        });
        if (_dirty) {
          _scheduleAutoSave(
            failed ? _autoSaveRetryDelay : _autoSaveDelay,
          );
        }
      }
    }
  }

  String get _saveStatusText {
    if (_autoSaving || _saving) return '正在保存';
    if (_autoSaveFailed) return '保存失败 · 正在重试';
    if (_dirty) return '等待自动保存';
    return '已保存 · 本地';
  }

  IconData get _saveStatusIcon {
    if (_autoSaving || _saving) return Icons.sync;
    if (_autoSaveFailed) return Icons.error_outline;
    if (_dirty) return Icons.schedule;
    return Icons.check_circle;
  }

  Color get _saveStatusColor {
    if (_autoSaveFailed) return AppColors.warning;
    if (_autoSaving || _saving || _dirty) return AppColors.warning;
    return AppColors.success;
  }

  void _recordSavedCheckpoint({bool resetHistory = false}) {
    if (resetHistory) {
      _previousSavedCheckpoint = null;
    } else if (_lastSavedCheckpoint != null &&
        !_lastSavedCheckpoint!.sameContent(_document ?? _captureDocument())) {
      _previousSavedCheckpoint = _lastSavedCheckpoint;
    }
    _document ??= _captureDocument();
    _lastSavedCheckpoint = _document;
  }

  Future<void> _loadStoredProject() async {
    try {
      final manifest = supportsIncrementalProjectStorage
          ? await loadLocalProjectManifest(_activeProjectId)
          : null;
      final legacyBytes =
          manifest == null ? await loadLocalProject(_activeProjectId) : null;
      if (manifest == null && legacyBytes == null) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      final project = manifest != null
          ? await decodeProjectManifest(
              manifest,
              (pageId) => loadLocalProjectImage(_activeProjectId, pageId),
              (assetId) => loadLocalProjectAsset(_activeProjectId, assetId),
            )
          : await decodeProject(legacyBytes!);
      final needsMigration = supportsIncrementalProjectStorage &&
          (manifest == null || project.schemaVersion < 3);
      var loadedRevision = project.revision ?? 0;
      final thumbnail = project.pages.isEmpty
          ? null
          : await encodeThumbnailBase64(project.pages.first.image);
      final edits = await loadLocalProjectEdits(_activeProjectId);
      String? editedScript;
      var recoveredLegacyPages = 0;
      if (edits != null) {
        try {
          final result = await applyProjectEdits(edits, project.pages,
              fontAliases: project.fontAliases,
              projectRevision: project.revision);
          loadedRevision = math.max(loadedRevision, result.revision ?? 0);
          recoveredLegacyPages = result.preservedManifestPages;
          editedScript = result.recoveredLegacyData
              ? buildBcsScript(project.pages)
              : result.script;
        } catch (_) {
          // The full project remains usable even if an optional edit layer fails.
        }
      }
      _restoredFontRefs
        ..clear()
        ..addAll(project.fontAssetReferences);
      if (mounted && project.fontWarnings.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(project.fontWarnings.join('\n'))));
          }
        });
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
        _editRevision = loadedRevision;
        _structureDirty = needsMigration;
      });
      _recordSavedCheckpoint(resetHistory: true);
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

  final Map<String, String> _fontStorageReferences = {};
  final Map<String, String> _restoredFontRefs = {};
  final Set<String> _storedFontAssets = {};
  Future<void> _persistLocalProject(
      {bool forceFull = false, bool includeManifest = false}) async {
    if (_pages.isEmpty) return;
    final snapshot = _document ?? _captureDocument();
    final pages = snapshot.toPages();
    final revision = _editRevision;
    final structural = forceFull || _structureDirty;
    final thumbnail = _projectThumbnailBase64;
    final projectId = _activeProjectId;
    final projectName = _projectName;
    // Capture before awaiting: one write transaction cannot mix two revisions.
    try {
      await _saveQueue.enqueue(revision, () async {
        if (mounted) setState(() => _saving = true);
        try {
          if (supportsIncrementalProjectStorage) {
            if (structural) {
              for (final page in pages) {
                await saveLocalProjectImage(projectId, page.pageId, page.bytes);
                for (final image in page.placedImages) {
                  await saveLocalProjectAsset(projectId, image.id, image.bytes);
                }
                await Future<void>.delayed(Duration.zero);
              }
            }
            final fontRefs = <String, String>{};
            for (final entry in snapshot.fonts.entries) {
              final cacheKey = '${entry.key}:${identityHashCode(entry.value)}';
              final assetId = _fontStorageReferences.putIfAbsent(
                  cacheKey, () => 'font-${sha256.convert(entry.value)}');
              fontRefs[entry.key] = assetId;
              if (!_storedFontAssets.contains(assetId)) {
                await saveLocalProjectAsset(projectId, assetId, entry.value);
                _storedFontAssets.add(assetId);
              }
            }
            await saveLocalProjectManifest(
                projectId,
                projectName,
                encodeProjectManifest(pages, snapshot.script,
                    revision: revision,
                    fonts: snapshot.fonts,
                    fontAssetReferences: {..._restoredFontRefs, ...fontRefs}),
                thumbnailBase64: thumbnail,
                revision: revision);
          } else {
            await saveLocalProject(
                projectId,
                projectName,
                encodeProject(pages, snapshot.script,
                    fonts: snapshot.fonts, revision: snapshot.revision),
                thumbnailBase64: thumbnail,
                revision: revision);
          }
          await saveLocalProjectEdits(projectId, projectName,
              encodeProjectEdits(pages, snapshot.script, revision: revision),
              thumbnailBase64: thumbnail);
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      });
      if (mounted && revision == _editRevision) {
        setState(() {
          _dirty = false;
          _autoSaveFailed = false;
          if (structural) _structureDirty = false;
        });
        _recordSavedCheckpoint();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dirty = true;
          _autoSaveFailed = true;
        });
      }
      rethrow;
    } finally {
      // The queue may replace this pending write, but its immutable pages still
      // belong to this call and must be released after the await completes.
      _disposePages(pages);
    }
  }

  Future<void> _returnToProjects() async {
    try {
      _finishEdit();
      _autoSaveTimer?.cancel();
      if (_dirty && _pages.isNotEmpty) {
        await _persistLocalProject(includeManifest: true);
      }
      await _saveQueue.flush();
      if (mounted) widget.onExitToProjects();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('尚未安全保存，已留在当前项目：$error')));
      }
    }
  }

  void _ensureBubbleIds(List<ImagePage> pages) {
    final seen = <String>{};
    for (final page in pages) {
      final localCounts = <String, int>{};
      for (final caption in page.captions) {
        localCounts.update(caption.bubbleId, (v) => v + 1, ifAbsent: () => 1);
      }
      for (var i = 0; i < page.captions.length; i++) {
        final caption = page.captions[i];
        if (caption.bubbleId.isNotEmpty && seen.add(caption.bubbleId)) continue;
        var suffix = i + 1;
        var id = '${page.pageId}-b$suffix';
        while (!seen.add(id)) {
          id = '${page.pageId}-b${++suffix}';
        }
        final migrated = caption.copyWith(bubbleId: id);
        page.captions[i] = migrated;
        if (i < page.placements.length) {
          page.placements[i] = page.placements[i].copyWith(caption: migrated);
        }
        if (caption.bubbleId.isNotEmpty && localCounts[caption.bubbleId] == 1) {
          page.placedImages = [
            for (final image in page.placedImages)
              image.bubbleId == caption.bubbleId
                  ? image.copyWith(bubbleId: id)
                  : image
          ];
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
    _finishEdit();
    _remember(label: replace ? '替换图片' : '添加图片');
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
      _markDirty();
      _structureDirty = true;
      _isDemoProject = false;
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

  Future<void> _resolveDocumentFonts() async {
    for (final page in _pages) {
      for (var i = 0; i < page.placements.length; i++) {
        final bubble = page.placements[i];
        final result = await FontLibrary.instance.resolve(bubble.fontFamily,
            assetId: bubble.fontAssetId, text: bubble.caption.text);
        final asset = result.asset;
        if (asset == null || result.missingFont) continue;
        page.placements[i] = bubble.copyWith(
            fontFamily: asset.runtimeFamily,
            fontAssetId: asset.id,
            fontDisplayName: asset.displayName);
        if (asset.record.source != FontSource.builtIn) {
          _fontBytes[asset.runtimeFamily] = asset.bytes;
          _structureDirty = true;
        }
      }
    }
  }

  bool _autoArrange(
      {ScriptImportOptions options = const ScriptImportOptions(),
      String? baselineSource}) {
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
      return false;
    }
    final baseline =
        parseCaptionScript(baselineSource ?? buildBcsScript(_pages));
    final migratedLegacy = parsed.sections.any(
      (section) => section.legacyHeader,
    );
    final candidates = _captureDocument().toPages();
    final beforeFlat = _pages.expand((p) => p.placements).toList();
    try {
      for (var pageIndex = 0; pageIndex < candidates.length; pageIndex++) {
        final page = candidates[pageIndex];
        final incoming = parsed.sections[pageIndex].captions;
        final generated = _engine.arrange(
          incoming,
          imageWidth: page.originalWidth,
          imageHeight: page.originalHeight,
        );
        final oldPlacements = page.placements;
        final placements = baselineSource == null
            ? preserveEditedPlacements(oldPlacements, generated, incoming)
            : mergeScriptPlacements(
                oldPlacements,
                generated,
                pageIndex < baseline.sections.length
                    ? baseline.sections[pageIndex].captions
                    : const [],
                options: options);
        final changed = page.captions.length != incoming.length ||
            List.generate(
              incoming.length,
              (i) =>
                  i >= page.captions.length ||
                  page.captions[i].speaker != incoming[i].speaker ||
                  page.captions[i].text != incoming[i].text,
            ).any((value) => value);
        page
          ..captions = placements.map((b) => b.caption).toList()
          ..placements = placements;
        final ids = placements.map((b) => b.caption.bubbleId).toSet();
        final oldById = {for (final b in oldPlacements) b.caption.bubbleId: b};
        final nextById = {for (final b in placements) b.caption.bubbleId: b};
        page.placedImages = [
          for (final image in page.placedImages)
            if (image.bubbleId != null && !ids.contains(image.bubbleId))
              image.copyWith(bubbleId: null)
            else if (oldById[image.bubbleId] case final before?)
              if (nextById[image.bubbleId] case final next?)
                image.copyWith(
                    x: next.x +
                        (image.x - before.x) * next.width / before.width,
                    y: next.y +
                        (image.y - before.y) * next.height / before.height,
                    width: image.width * next.width / before.width,
                    height: image.height * next.height / before.height)
              else
                image
            else
              image
        ];
        if (changed) page.approved = false;
      }
      _ensureBubbleIds(candidates);
      final merged = mergeLinkedStyleChanges(
          beforeFlat, candidates.expand((p) => p.placements).toList(),
          applyStyle: options.style);
      var offset = 0;
      for (final page in candidates) {
        final count = page.placements.length;
        page.placements = merged.sublist(offset, offset + count);
        page.captions = page.placements.map((b) => b.caption).toList();
        offset += count;
      }
    } catch (error) {
      _disposePages(candidates);
      _script.text = buildBcsScript(_pages);
      showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('脚本未应用，当前项目保持不变'),
                  content: Text(error.toString()),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('返回修改'))
                  ]));
      return false;
    }
    final oldPages = List<ImagePage>.of(_pages);
    _remember(label: '应用字幕脚本');
    setState(() {
      _pages
        ..clear()
        ..addAll(candidates);
      _selectedBubble = 0;
      _selectionVisible = false;
      _markDirty();
    });
    _disposePages(oldPages);
    if (migratedLegacy) _script.text = buildBcsScript(_pages);
    if (mounted && (parsed.warnings.isNotEmpty || migratedLegacy)) {
      final messages = <String>[
        if (migratedLegacy) '旧版文件名脚本已按段落出现顺序迁移为 v3；文件名不再参与匹配。',
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
    return true;
  }

  int _applyGeometricLayout(List<ImagePage> pages, {Set<String>? ids}) {
    var count = 0;
    for (final page in pages) {
      final slots = [
        for (var i = 0; i < page.placements.length; i++)
          if (ids == null || ids.contains(page.placements[i].caption.bubbleId))
            i
      ];
      if (slots.isEmpty) continue;
      final generated = _engine.arrange([
        for (final slot in slots)
          CaptionLine(
              speaker: '',
              text: page.placements[slot].caption.text,
              bubbleId: page.placements[slot].caption.bubbleId)
      ], imageWidth: page.originalWidth, imageHeight: page.originalHeight);
      for (var i = 0; i < slots.length; i++) {
        final old = page.placements[slots[i]], next = generated[i];
        page.placements[slots[i]] = old.copyWith(
            x: next.x, y: next.y, width: next.width, height: next.height);
        for (var j = 0; j < page.placedImages.length; j++) {
          final image = page.placedImages[j];
          if (image.bubbleId != old.caption.bubbleId) continue;
          page.placedImages[j] = image.copyWith(
              x: next.x + (image.x - old.x) * next.width / old.width,
              y: next.y + (image.y - old.y) * next.height / old.height,
              width: image.width * next.width / old.width,
              height: image.height * next.height / old.height);
        }
        count++;
      }
      page.approved = false;
    }
    return count;
  }

  void _resetCurrentPageLayout() {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    _finishEdit();
    _remember(label: '重排当前图片');
    setState(() {
      _applyGeometricLayout([page]);
      _markDirty();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(_quickFeedback('已重排当前图片，保留文字、样式和素材绑定；可撤销'));
  }

  Future<void> _runLayoutStep() async {
    if (_pages.every((p) => p.placements.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(_quickFeedback('当前没有可排版字幕，请先导入脚本或添加文字'));
      return;
    }
    var scope = 'page';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, setDialogState) => AlertDialog(
                    title: const Text('重新自动排版'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButton<String>(
                          value: scope,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                                value: 'page', child: Text('当前图片')),
                            DropdownMenuItem(
                                value: 'selected',
                                enabled: _multiSelected.isNotEmpty,
                                child: const Text('章节文本中勾选的对象')),
                            const DropdownMenuItem(
                                value: 'all', child: Text('整个章节'))
                          ],
                          onChanged: (v) => setDialogState(() => scope = v!)),
                      const Text(
                          '只重算位置和框尺寸，保留文字、字号、颜色、气泡类型、关联样式及素材绑定。不判断画面语义，重要人物附近仍需手动检查。')
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('开始排版'))
                    ])));
    if (confirmed != true || !mounted) return;
    _finishEdit();
    _remember(label: '重新排版');
    var count = 0;
    setState(() {
      count = _applyGeometricLayout(scope == 'page' ? [_page!] : _pages,
          ids: scope == 'selected' ? _multiSelected : null);
      _selectedBubble = 0;
      _selectionVisible = false;
      _markDirty();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(_quickFeedback('已重排 $count 个对象，保留文字和样式；可撤销'));
  }

  void _remember({bool currentPageOnly = false, String? label}) {
    _pendingBefore = _captureDocument();
    if (label != null) _commandLabel = label;
  }

  void _undo() {
    final label = _undoStack.isEmpty ? '' : _undoStack.last.label;
    final document = _history.undo();
    if (document == null) return;
    _restoreDocument(document);
    ScaffoldMessenger.of(context).showSnackBar(_quickFeedback('已撤销：$label'));
  }

  void _redo() {
    final label = _redoStack.isEmpty ? '' : _redoStack.last.label;
    final document = _history.redo();
    if (document == null) return;
    _restoreDocument(document);
    ScaffoldMessenger.of(context).showSnackBar(_quickFeedback('已重做：$label'));
  }

  void _restoreDocument(ProjectDocument document,
      {bool record = false, String label = '恢复保存版本'}) {
    _finishEdit();
    if (record) _remember(label: label);
    final oldPages = List<ImagePage>.of(_pages);
    _clearActiveSourceImage();
    _restoringDocument = !record;
    setState(() {
      _pages
        ..clear()
        ..addAll(document.toPages());
      _fontBytes
        ..clear()
        ..addAll(document.fonts);
      _importedFonts
        ..clear()
        ..addAll(document.fonts.keys);
      _selectedPage = _pages.isEmpty
          ? 0
          : document.selectedPage.clamp(0, _pages.length - 1);
      _selectedBubble = _page == null || _page!.placements.isEmpty
          ? 0
          : document.selectedBubble.clamp(0, _page!.placements.length - 1);
      _selectionVisible = false;
      _canvasSelection = _CanvasSelection.none;
      _structureDirty = true;
      _markDirty();
    });
    _restoringDocument = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commandFocus.requestFocus();
    });
    _disposePages(oldPages);
    unawaited(_loadSelectedPageSource());
  }

  ProjectDocument? get _rollbackCheckpoint =>
      _dirty ? _lastSavedCheckpoint : _previousSavedCheckpoint;

  bool get _canRollbackToLastSave {
    final checkpoint = _rollbackCheckpoint;
    return checkpoint != null &&
        checkpoint.pages.length == _pages.length &&
        !_saving &&
        !_autoSaving;
  }

  void _rollbackToLastSave() {
    final checkpoint = _rollbackCheckpoint;
    if (checkpoint == null) return;
    _finishEdit();
    _restoreDocument(checkpoint, record: true);
    ScaffoldMessenger.of(context)
        .showSnackBar(_quickFeedback('已恢复保存版本，正在保存；可用撤销恢复操作前的修改'));
  }

  void _replaceBubble(BubblePlacement bubble, {bool remember = false}) {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    final previous = page.placements[_selectedBubble];
    final textEdit = previous.caption.text != bubble.caption.text &&
        (_commandGroup?.startsWith('text:') ?? false);
    if (remember && !textEdit) {
      _finishEdit();
      _commandLabel = previous.fontFamily != bubble.fontFamily
          ? '修改字体'
          : previous.fontSize != bubble.fontSize
              ? '修改字号'
              : previous.fontColorValue != bubble.fontColorValue
                  ? '修改字体颜色'
                  : previous.shape != bubble.shape
                      ? '修改气泡样式'
                      : '修改对象属性';
    }
    if (remember) _remember(currentPageOnly: true);
    setState(() {
      page.placements[_selectedBubble] = bubble;
      page.captions[_selectedBubble] = bubble.caption;
      if (bubble.styleId != null &&
          previous.styleId == bubble.styleId &&
          _textStyleKey(previous) != _textStyleKey(bubble)) {
        for (final targetPage in _pages) {
          for (var i = 0; i < targetPage.placements.length; i++) {
            final target = targetPage.placements[i];
            if (target.styleId == bubble.styleId &&
                target.caption.bubbleId != bubble.caption.bubbleId) {
              targetPage.placements[i] =
                  _copyTextStyle(target, bubble, bubble.styleId);
            }
          }
        }
      }
      page.approved = false;
      _markDirty();
    });
    _canvasRevision.value++;
  }

  void _replaceBubbleDuringDrag(BubblePlacement bubble) {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    final previous = page.placements[_selectedBubble];
    page.placements[_selectedBubble] = bubble;
    page.captions[_selectedBubble] = bubble.caption;
    final scaleX = previous.width == 0 ? 1 : bubble.width / previous.width;
    final scaleY = previous.height == 0 ? 1 : bubble.height / previous.height;
    for (var i = 0; i < page.placedImages.length; i++) {
      final image = page.placedImages[i];
      if (image.bubbleId != previous.caption.bubbleId) continue;
      page.placedImages[i] = image.copyWith(
        x: bubble.x + (image.x - previous.x) * scaleX,
        y: bubble.y + (image.y - previous.y) * scaleY,
        width: image.width * scaleX,
        height: image.height * scaleY,
      );
    }
    page.approved = false;
    _markDirty();
    _canvasRevision.value++;
  }

  Future<void> _applySelectedStyleToAll(BubblePlacement source) async {
    final selected = <_BubbleStyleProperty>{};
    var scope = 'page';
    final chosenPageIds = <String>{if (_page != null) _page!.pageId};
    final labels = <_BubbleStyleProperty, String>{
      _BubbleStyleProperty.fontFamily: '字体',
      _BubbleStyleProperty.fontColor: '字体颜色',
      _BubbleStyleProperty.fontSize: '字体大小',
      _BubbleStyleProperty.lineHeight: '行间距',
      _BubbleStyleProperty.strokeWidth: '气泡边框',
      _BubbleStyleProperty.textSizeMode: '字号模式',
      _BubbleStyleProperty.letterSpacing: '字距',
      _BubbleStyleProperty.textAlign: '文字对齐',
      _BubbleStyleProperty.textStrokeWidth: '文字描边',
      _BubbleStyleProperty.textStrokeColor: '文字描边颜色',
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
                DropdownButton<String>(
                    value: scope,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'page', child: Text('当前图片全部对象')),
                      DropdownMenuItem(
                          value: 'pages', child: Text('指定多张图片全部对象')),
                      DropdownMenuItem(
                          value: 'selected', child: Text('章节文本中勾选的对象')),
                      DropdownMenuItem(value: 'all', child: Text('整个章节全部对象'))
                    ],
                    onChanged: (v) => setDialogState(() => scope = v!)),
                if (scope == 'pages')
                  TextButton.icon(
                      icon: const Icon(Icons.collections_outlined),
                      label: Text(
                          '选择图片（已选 ${chosenPageIds.length} / ${_pages.length}）'),
                      onPressed: () async {
                        final working = Set<String>.of(chosenPageIds);
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (c) => StatefulBuilder(
                                builder: (c, setPages) => AlertDialog(
                                        title: const Text('选择批量格式化的图片'),
                                        content: workspaceDialogContent(c,
                                            maxWidth: 540,
                                            maxHeight: 420,
                                            child: ListView(children: [
                                              for (var i = 0;
                                                  i < _pages.length;
                                                  i++)
                                                CheckboxListTile(
                                                    value: working.contains(
                                                        _pages[i].pageId),
                                                    title: Text(
                                                        '${i + 1}. ${_pages[i].name}'),
                                                    subtitle: Text(
                                                        '${_pages[i].placements.length} 个文字对象'),
                                                    onChanged: (v) =>
                                                        setPages(() {
                                                          if (v == true) {
                                                            working.add(
                                                                _pages[i]
                                                                    .pageId);
                                                          } else {
                                                            working.remove(
                                                                _pages[i]
                                                                    .pageId);
                                                          }
                                                        }))
                                            ])),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('取消')),
                                          FilledButton(
                                              onPressed: working.isEmpty
                                                  ? null
                                                  : () =>
                                                      Navigator.pop(c, true),
                                              child: const Text('确认图片'))
                                        ])));
                        if (confirmed == true && dialogContext.mounted) {
                          setDialogState(() {
                            chosenPageIds
                              ..clear()
                              ..addAll(working);
                          });
                        }
                      }),
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
    _finishEdit();
    _remember(label: '批量应用样式');
    var changed = 0;
    for (final page in _pages) {
      if (scope == 'page' && page != _page) continue;
      if (scope == 'pages' && !chosenPageIds.contains(page.pageId)) continue;
      for (var i = 0; i < page.placements.length; i++) {
        final target = page.placements[i];
        if (scope == 'selected' &&
            !_multiSelected.contains(target.caption.bubbleId)) continue;
        page.placements[i] = target.copyWith(
          fontFamily: selected.contains(_BubbleStyleProperty.fontFamily)
              ? source.fontFamily
              : null,
          fontAssetId: selected.contains(_BubbleStyleProperty.fontFamily)
              ? source.fontAssetId
              : target.fontAssetId,
          fontDisplayName: selected.contains(_BubbleStyleProperty.fontFamily)
              ? source.fontDisplayName
              : target.fontDisplayName,
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
          textSizeMode: selected.contains(_BubbleStyleProperty.textSizeMode)
              ? source.textSizeMode
              : null,
          letterSpacing: selected.contains(_BubbleStyleProperty.letterSpacing)
              ? source.letterSpacing
              : null,
          textAlign: selected.contains(_BubbleStyleProperty.textAlign)
              ? source.textAlign
              : null,
          textStrokeWidth:
              selected.contains(_BubbleStyleProperty.textStrokeWidth)
                  ? source.textStrokeWidth
                  : null,
          textStrokeColorValue:
              selected.contains(_BubbleStyleProperty.textStrokeColor)
                  ? source.textStrokeColorValue
                  : null,
          // Selective formatting detaches the target to avoid a misleading linked style.
          styleId: null,
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

  void _deleteSelection() {
    _finishEdit();
    if (_canvasSelection == _CanvasSelection.image) {
      _deletePlacedImage();
    } else if (_canvasSelection == _CanvasSelection.bubble) {
      _deleteBubble();
    }
  }

  Future<void> _pickTextStrokeColor(BubblePlacement bubble) async {
    var color = Color(bubble.textStrokeColorValue);
    final selected = await showDialog<Color>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('文字描边颜色'),
                content: SingleChildScrollView(
                    child: ColorPicker(
                        pickerColor: color,
                        onColorChanged: (value) => color = value,
                        enableAlpha: false)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, color),
                      child: const Text('应用'))
                ]));
    if (selected != null && mounted) {
      _replaceBubble(bubble.copyWith(textStrokeColorValue: selected.value),
          remember: true);
    }
  }

  String _textStyleKey(BubblePlacement b) => linkedTextStyleKey(b);

  BubblePlacement _copyTextStyle(
          BubblePlacement target, BubblePlacement source, String? styleId) =>
      target.copyWith(
          fontFamily: source.fontFamily,
          fontAssetId: source.fontAssetId,
          fontDisplayName: source.fontDisplayName,
          fontSize: source.fontSize,
          fontColorValue: source.fontColorValue,
          lineHeight: source.lineHeight,
          textSizeMode: source.textSizeMode,
          letterSpacing: source.letterSpacing,
          textAlign: source.textAlign,
          textStrokeWidth: source.textStrokeWidth,
          textStrokeColorValue: source.textStrokeColorValue,
          styleId: styleId);

  Widget _textMetricsLabel(BubblePlacement bubble) {
    final result = const TextLayoutService().layout(bubble);
    final effective = result.effectiveFontSize;
    final overflow = result.overflow;
    result.dispose();
    return Text(
        overflow
            ? '文字超框：固定字号未缩小，请调整框或主动选择自动适应'
            : bubble.textSizeMode == TextSizeMode.fit
                ? '实际字号 ${effective.toStringAsFixed(1)} / 设置 ${bubble.fontSize.toStringAsFixed(1)}'
                : '固定字号 ${bubble.fontSize.toStringAsFixed(1)} · 拉框不会改变字号',
        style: TextStyle(
            fontSize: 11,
            color: overflow ? Colors.deepOrange : AppColors.muted));
  }

  Widget _linkedStyleControls(BubblePlacement bubble) {
    final styles = <String, BubblePlacement>{};
    for (final page in _pages) {
      for (final b in page.placements) {
        if (b.styleId != null) styles[b.styleId!] = b;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Text(
          bubble.styleId == null
              ? '文字样式：独立编辑'
              : '关联样式：${bubble.styleId}（修改会同步关联对象）',
          style: const TextStyle(fontSize: 11)),
      Wrap(spacing: 4, children: [
        TextButton.icon(
            onPressed: () async {
              final controller = TextEditingController();
              final name = await _showTextDialog<String>(controller,
                  context: context,
                  builder: (c) => AlertDialog(
                          title: const Text('创建 / 更新关联文字样式'),
                          content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                  labelText: '样式名称',
                                  helperText: '同名会更新全部已关联对象')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('取消')),
                            FilledButton(
                                onPressed: () {
                                  if (controller.text.trim().isNotEmpty) {
                                    Navigator.pop(c, controller.text.trim());
                                  }
                                },
                                child: const Text('保存'))
                          ]));
              // Controller ownership ends when the route transition completes.
              if (name == null || !mounted) return;
              _finishEdit();
              _remember(label: '更新关联文字样式');
              setState(() {
                for (final page in _pages) {
                  for (var i = 0; i < page.placements.length; i++) {
                    final target = page.placements[i];
                    if (target.styleId == name ||
                        target.caption.bubbleId == bubble.caption.bubbleId) {
                      page.placements[i] = _copyTextStyle(target, bubble, name);
                    }
                  }
                }
                _markDirty();
              });
            },
            icon: const Icon(Icons.bookmark_add_outlined, size: 16),
            label: const Text('保存关联样式')),
        if (bubble.styleId != null)
          TextButton(
              onPressed: () => _replaceBubble(bubble.copyWith(styleId: null),
                  remember: true),
              child: const Text('解除关联')),
      ]),
      if (styles.isNotEmpty)
        DropdownButton<String>(
            hint: const Text('应用已有文字样式'),
            isExpanded: true,
            items: styles.keys
                .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                .toList(),
            onChanged: (id) {
              if (id != null) {
                _replaceBubble(_copyTextStyle(bubble, styles[id]!, id),
                    remember: true);
              }
            }),
    ]);
  }

  Future<void> _showMobileTextList() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (c) => ValueListenableBuilder<int>(
            valueListenable: _canvasRevision,
            builder: (context, _, child) => _chapterTextDock()));
  }

  Widget _chapterTextDock() {
    if (!_showChapterText) return const SizedBox.shrink();
    final items = [
      for (var p = 0; p < _pages.length; p++)
        for (var b = 0; b < _pages[p].placements.length; b++) (p, b)
    ];
    return SizedBox(
        height: 220,
        child: Material(
            color: AppColors.panel,
            child: Column(children: [
              Row(children: [
                const SizedBox(width: 12),
                Text('章节文字 · ${_multiSelected.length} 个已选对象'),
                const Spacer(),
                TextButton(
                    onPressed: _showScriptEditor,
                    child: const Text('当前 BCS / 导入草稿')),
                IconButton(
                    onPressed: () => setState(() => _showChapterText = false),
                    icon: const Icon(Icons.close))
              ]),
              Expanded(
                  child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final (pageIndex, bubbleIndex) = items[index];
                        final bubble =
                            _pages[pageIndex].placements[bubbleIndex];
                        return CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _multiSelected
                                .contains(bubble.caption.bubbleId),
                            onChanged: (value) => setState(() {
                                  if (value == true) {
                                    _multiSelected.add(bubble.caption.bubbleId);
                                  } else {
                                    _multiSelected
                                        .remove(bubble.caption.bubbleId);
                                  }
                                  _canvasRevision.value++;
                                }),
                            title: Text(
                                '${pageIndex + 1} · ${bubble.caption.text}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            secondary: IconButton(
                                tooltip: '定位对象',
                                icon: const Icon(Icons.my_location),
                                onPressed: () {
                                  _selectPage(pageIndex);
                                  setState(() {
                                    _selectedBubble = bubbleIndex;
                                    _canvasSelection = _CanvasSelection.bubble;
                                    _selectionVisible = true;
                                    _inspectorVisible = true;
                                  });
                                }));
                      })),
            ])));
  }

  void _duplicateSelection() {
    if (_canvasSelection == _CanvasSelection.bubble) {
      _duplicateBubble();
      return;
    }
    final image =
        _canvasSelection == _CanvasSelection.image ? _placedImage : null;
    if (image == null || _page == null) return;
    _remember(label: '复制图片元素');
    setState(() {
      _page!.placedImages.add(image.copyWith(
          id: 'image-${DateTime.now().microsecondsSinceEpoch}',
          image: image.image.clone(),
          x: image.x + 12,
          y: image.y + 12));
      _selectedImage = _page!.placedImages.length - 1;
      _structureDirty = true;
      _markDirty();
    });
  }

  void _addPlainText() => _addBubble(shape: BubbleShape.plainText);

  void _addBubble({BubbleShape shape = BubbleShape.ellipse}) {
    final page = _page;
    if (page == null) return;
    _remember(currentPageOnly: true);
    final index = page.placements.length;
    _commandLabel = shape == BubbleShape.plainText ? '添加文字' : '添加气泡';
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
      shape: shape,
      textSizeMode: TextSizeMode.fixed,
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
      _canvasSelection = _CanvasSelection.bubble;
      _selectionVisible = true;
      _showRendered = true;
      _inspectorVisible = true;
      page.approved = false;
      _markDirty();
    });
    _canvasRevision.value++;
    ScaffoldMessenger.of(context).showSnackBar(
      _quickFeedback(shape == BubbleShape.plainText
          ? '已添加纯文字，可输入文字并拖动调整位置'
          : '已添加气泡，直接在右侧输入文字或拖动调整位置'),
    );
  }

  bool _supportedPlacedImageName(String name) =>
      RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(name);

  Future<void> _addImageElement({bool insideBubble = false}) async {
    final files = await pickImageFiles();
    if (files == null || files.isEmpty || !mounted) return;
    final file = files.firstWhere(
      (item) => _supportedPlacedImageName(item.name),
      orElse: () => files.first,
    );
    if (!_supportedPlacedImageName(file.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        _quickFeedback('图片元素仅支持 PNG、JPG 和静态 WebP'),
      );
      return;
    }
    await _insertPlacedImage(
      name: file.name,
      bytes: file.bytes,
      insideBubble: insideBubble,
    );
  }

  Future<void> _insertPlacedImage({
    required String name,
    required Uint8List bytes,
    required bool insideBubble,
  }) async {
    final page = _page;
    if (page == null) return;
    var targetBubble = insideBubble ? _bubble : null;
    final insertionProjectId = _activeProjectId;
    if (insideBubble && targetBubble == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        _quickFeedback('请先选择一个气泡，再把图片放进气泡'),
      );
      return;
    }
    ui.Image decoded;
    try {
      decoded = await decodeOriginalImage(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _quickFeedback('图片无法读取，请确认它是有效的 PNG、JPG 或静态 WebP'),
        );
      }
      return;
    }
    if (!mounted ||
        insertionProjectId != _activeProjectId ||
        !identical(_page, page)) {
      decoded.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_quickFeedback('页面已切换或回退，图片未添加，请重新选择'));
      }
      return;
    }
    if (targetBubble != null) {
      final matching = page.placements
          .where((b) => b.caption.bubbleId == targetBubble!.caption.bubbleId)
          .toList();
      if (matching.isEmpty) {
        decoded.dispose();
        return;
      }
      targetBubble = matching.single;
    }
    _remember(label: '添加图片元素');
    final maxWidth = page.originalWidth * (insideBubble ? .22 : .28);
    final aspect = decoded.width / decoded.height;
    var width = maxWidth;
    var height = width / aspect;
    final maxHeight = page.originalHeight * (insideBubble ? .14 : .24);
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }
    final centerX = targetBubble?.x != null
        ? targetBubble!.x + targetBubble.width / 2
        : page.originalWidth / 2;
    final centerY = targetBubble?.y != null
        ? targetBubble!.y + targetBubble.height / 2
        : page.originalHeight / 2;
    final image = PlacedImage(
      id: newPlacedImageId(),
      name: name,
      bytes: Uint8List.fromList(bytes),
      image: decoded,
      x: (centerX - width / 2).clamp(0, page.originalWidth - width),
      y: (centerY - height / 2).clamp(0, page.originalHeight - height),
      width: width,
      height: height,
      bubbleId: targetBubble?.caption.bubbleId,
    );
    setState(() {
      page.placedImages.add(image);
      _selectedImage = page.placedImages.length - 1;
      _canvasSelection = _CanvasSelection.image;
      _selectionVisible = true;
      _inspectorVisible = true;
      page.approved = false;
      _markDirty();
    });
    if (supportsIncrementalProjectStorage) {
      try {
        await saveLocalProjectAsset(_activeProjectId, image.id, image.bytes);
      } catch (_) {
        if (mounted) setState(() => _structureDirty = true);
      }
    }
    if (!mounted) return;
    _canvasRevision.value++;
    ScaffoldMessenger.of(context).showSnackBar(
      _quickFeedback(
          insideBubble ? '图片已放入气泡，可继续移动、缩放和旋转' : '图片元素已添加，可直接在画布上调整'),
    );
  }

  Future<String?> _askShortText({
    required String title,
    required String initialValue,
    required String label,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await _showTextDialog<String>(
        controller,
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: LText(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(labelText: tr(label)),
            onSubmitted: (value) => Navigator.pop(
              dialogContext,
              value.trim(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: LText('确定'),
            ),
          ],
        ),
      );
    } finally {
      // Controller ownership ends when the route transition completes.
    }
  }

  Future<void> _importStickers(String category) async {
    final files = await pickImageFiles();
    if (files == null || files.isEmpty) return;
    final supported =
        files.where((file) => _supportedPlacedImageName(file.name));
    if (supported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          _quickFeedback('表情包库仅支持 PNG、JPG 和静态 WebP'),
        );
      }
      return;
    }
    final now = DateTime.now().toUtc();
    final additions = [
      for (final file in supported)
        StickerAsset(
          id: 'sticker-${now.microsecondsSinceEpoch}-${file.name.hashCode}',
          name: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          category: category.isEmpty ? '未分类' : category,
          bytes: Uint8List.fromList(file.bytes),
          createdAt: now,
        ),
    ];
    setState(() => _stickers = [...additions, ..._stickers]);
    await saveStickerLibrary(_stickers);
  }

  Future<void> _showStickerLibrary() async {
    var query = '';
    var category = '全部';
    final search = TextEditingController();
    try {
      await _showTextDialog<void>(
        search,
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final categories = <String>{
              '全部',
              '最近使用',
              '收藏',
              ..._stickers.map((asset) => asset.category),
            }.toList();
            final filtered = _stickers.where((asset) {
              final queryMatches = query.isEmpty ||
                  asset.name.toLowerCase().contains(query.toLowerCase()) ||
                  asset.category.toLowerCase().contains(query.toLowerCase());
              final categoryMatches = switch (category) {
                '全部' => true,
                '最近使用' => asset.lastUsedAt != null,
                '收藏' => asset.favorite,
                _ => asset.category == category,
              };
              return queryMatches && categoryMatches;
            }).toList()
              ..sort((a, b) {
                if (category == '最近使用') {
                  return (b.lastUsedAt ??
                          DateTime.fromMillisecondsSinceEpoch(0))
                      .compareTo(a.lastUsedAt ??
                          DateTime.fromMillisecondsSinceEpoch(0));
                }
                return b.createdAt.compareTo(a.createdAt);
              });

            Future<void> persist() => saveStickerLibrary(_stickers);

            Future<void> useAsset(StickerAsset asset, bool insideBubble) async {
              final used = asset.copyWith(lastUsedAt: DateTime.now().toUtc());
              setState(() {
                _stickers = [
                  for (final item in _stickers)
                    item.id == asset.id ? used : item,
                ];
              });
              await persist();
              if (!dialogContext.mounted || !mounted) return;
              Navigator.pop(dialogContext);
              await _insertPlacedImage(
                name: asset.name,
                bytes: asset.bytes,
                insideBubble: insideBubble,
              );
            }

            final size = workspaceDialogContentSize(
              MediaQuery.sizeOf(context),
              maxWidth: 860,
              maxHeight: 680,
            );
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.emoji_emotions_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: LText('全局表情包库')),
                  FilledButton.icon(
                    onPressed: () async {
                      var targetCategory = category;
                      if (const {'全部', '最近使用', '收藏'}.contains(targetCategory)) {
                        targetCategory = '未分类';
                      }
                      await _importStickers(targetCategory);
                      if (dialogContext.mounted) setDialogState(() {});
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: LText('加入表情包'),
                  ),
                ],
              ),
              content: SizedBox(
                width: size.width,
                height: size.height,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: tr('搜索名称或分类'),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  search.clear();
                                  setDialogState(() => query = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          if (index == categories.length) {
                            return ActionChip(
                              avatar: const Icon(
                                  Icons.create_new_folder_outlined,
                                  size: 18),
                              label: LText('新建分类'),
                              onPressed: () async {
                                final value = await _askShortText(
                                  title: '新建表情包分类',
                                  initialValue: '',
                                  label: '分类名称',
                                );
                                if (value != null &&
                                    value.isNotEmpty &&
                                    dialogContext.mounted) {
                                  setDialogState(() => category = value);
                                }
                              },
                            );
                          }
                          final item = categories[index];
                          return FilterChip(
                            label: LText(item),
                            selected: category == item,
                            onSelected: (_) =>
                                setDialogState(() => category = item),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_library_outlined,
                                      size: 52, color: AppColors.muted),
                                  const SizedBox(height: 10),
                                  LText(query.isEmpty
                                      ? '表情包库还是空的，点击右上角加入图片'
                                      : '没有找到匹配的表情包'),
                                ],
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                mainAxisExtent: 205,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final asset = filtered[index];
                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => useAsset(asset, false),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: ColoredBox(
                                            color: AppColors.canvas,
                                            child: Image.memory(
                                              asset.bytes,
                                              fit: BoxFit.contain,
                                              gaplessPlayback: true,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                Icons.broken_image_outlined,
                                                color: AppColors.muted,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              9, 7, 5, 3),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  asset.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                              ),
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                tooltip: tr(asset.favorite
                                                    ? '取消收藏'
                                                    : '收藏'),
                                                onPressed: () async {
                                                  setState(() {
                                                    _stickers = [
                                                      for (final item
                                                          in _stickers)
                                                        item.id == asset.id
                                                            ? item.copyWith(
                                                                favorite: !item
                                                                    .favorite)
                                                            : item,
                                                    ];
                                                  });
                                                  await persist();
                                                  if (dialogContext.mounted) {
                                                    setDialogState(() {});
                                                  }
                                                },
                                                icon: Icon(
                                                  asset.favorite
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color: asset.favorite
                                                      ? AppColors.warning
                                                      : AppColors.muted,
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                tooltip: tr('更多操作'),
                                                onSelected: (value) async {
                                                  if (value == 'bubble') {
                                                    await useAsset(asset, true);
                                                    return;
                                                  }
                                                  if (value == 'rename') {
                                                    final name =
                                                        await _askShortText(
                                                      title: '重命名表情包',
                                                      initialValue: asset.name,
                                                      label: '表情包名称',
                                                    );
                                                    if (name != null &&
                                                        name.isNotEmpty) {
                                                      setState(() {
                                                        _stickers = [
                                                          for (final item
                                                              in _stickers)
                                                            item.id == asset.id
                                                                ? item.copyWith(
                                                                    name: name)
                                                                : item,
                                                        ];
                                                      });
                                                    }
                                                  } else if (value ==
                                                      'category') {
                                                    final value =
                                                        await _askShortText(
                                                      title: '修改分类',
                                                      initialValue:
                                                          asset.category,
                                                      label: '分类名称',
                                                    );
                                                    if (value != null &&
                                                        value.isNotEmpty) {
                                                      setState(() {
                                                        _stickers = [
                                                          for (final item
                                                              in _stickers)
                                                            item.id == asset.id
                                                                ? item.copyWith(
                                                                    category:
                                                                        value)
                                                                : item,
                                                        ];
                                                      });
                                                    }
                                                  } else if (value ==
                                                      'delete') {
                                                    setState(() {
                                                      _stickers = [
                                                        for (final item
                                                            in _stickers)
                                                          if (item.id !=
                                                              asset.id)
                                                            item,
                                                      ];
                                                    });
                                                  }
                                                  await persist();
                                                  if (dialogContext.mounted) {
                                                    setDialogState(() {});
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  PopupMenuItem(
                                                    value: 'bubble',
                                                    enabled: _bubble != null,
                                                    child: LText('放进当前气泡'),
                                                  ),
                                                  PopupMenuItem(
                                                      value: 'rename',
                                                      child: LText('重命名')),
                                                  PopupMenuItem(
                                                      value: 'category',
                                                      child: LText('修改分类')),
                                                  PopupMenuItem(
                                                      value: 'delete',
                                                      child: LText('从库中删除')),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              9, 0, 9, 8),
                                          child: Text(
                                            asset.category,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.muted),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                  child: LText('关闭'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      // Controller ownership ends when the route transition completes.
    }
  }

  void _replacePlacedImage(PlacedImage image, {bool remember = false}) {
    final page = _page;
    if (page == null || page.placedImages.isEmpty) return;
    if (remember) _remember(currentPageOnly: true);
    setState(() {
      page.placedImages[_selectedImage] = image;
      page.approved = false;
      _markDirty();
    });
    _canvasRevision.value++;
  }

  void _replacePlacedImageDuringDrag(PlacedImage image) {
    final page = _page;
    if (page == null || page.placedImages.isEmpty) return;
    page.placedImages[_selectedImage] = image;
    page.approved = false;
    _markDirty();
    _canvasRevision.value++;
  }

  void _deletePlacedImage() {
    final page = _page;
    final image = _placedImage;
    if (page == null || image == null) return;
    _remember(currentPageOnly: true);
    setState(() {
      page.placedImages.removeAt(_selectedImage).image.dispose();
      _selectedImage = page.placedImages.isEmpty
          ? 0
          : _selectedImage.clamp(0, page.placedImages.length - 1);
      _canvasSelection = _CanvasSelection.none;
      _selectionVisible = false;
      page.approved = false;
      _markDirty();
    });
    _canvasRevision.value++;
  }

  void _movePlacedImageLayer(int delta) {
    final page = _page;
    if (page == null || page.placedImages.length < 2) return;
    final target =
        (_selectedImage + delta).clamp(0, page.placedImages.length - 1);
    if (target == _selectedImage) return;
    _remember(currentPageOnly: true);
    setState(() {
      final image = page.placedImages.removeAt(_selectedImage);
      page.placedImages.insert(target, image);
      _selectedImage = target;
      _markDirty();
    });
    _canvasRevision.value++;
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
      x: (source.x + 24)
          .clamp(0, math.max(0.0, page.originalWidth - source.width)),
      y: (source.y + 24)
          .clamp(0, math.max(0.0, page.originalHeight - source.height)),
    );
    setState(() {
      final boundCopies = [
        for (final image in page.placedImages)
          if (image.bubbleId == source.caption.bubbleId)
            image.copyWith(
                id: newPlacedImageId(),
                image: image.image.clone(),
                bubbleId: caption.bubbleId,
                x: image.x + bubble.x - source.x,
                y: image.y + bubble.y - source.y)
      ];
      page.placedImages.addAll(boundCopies);
      if (boundCopies.isNotEmpty) _structureDirty = true;
      page.captions.add(caption);
      page.placements.add(bubble);
      _selectedBubble = page.placements.length - 1;
      _selectionVisible = true;
      _canvasSelection = _CanvasSelection.bubble;
      _inspectorVisible = true;
      page.approved = false;
      _markDirty();
    });
  }

  void _deleteBubble() {
    final page = _page;
    if (page == null || page.placements.isEmpty) return;
    _remember(currentPageOnly: true);
    final removedBubbleId = page.placements[_selectedBubble].caption.bubbleId;
    setState(() {
      page.placements.removeAt(_selectedBubble);
      page.captions.removeAt(_selectedBubble);
      page.placedImages = [
        for (final image in page.placedImages)
          image.bubbleId == removedBubbleId
              ? image.copyWith(bubbleId: null)
              : image,
      ];
      _selectedBubble = page.placements.isEmpty
          ? 0
          : _selectedBubble.clamp(0, page.placements.length - 1);
      _selectionVisible = false;
      _canvasSelection = _CanvasSelection.none;
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
    _finishEdit();
    setState(() {
      _selectedPage = index;
      _selectedBubble = 0;
      _selectedImage = 0;
      _canvasSelection = _CanvasSelection.none;
      _selectionVisible = false;
      // Keep project undo/redo history while navigating pages.
    });
    unawaited(_loadSelectedPageSource());
  }

  Future<void> _exportAll({List<int>? retryIndexes}) async {
    if (_pages.isEmpty || _exporting) return;
    final selectedIndexes = retryIndexes ?? await _chooseExportPages();
    if (selectedIndexes == null || selectedIndexes.isEmpty || !mounted) return;
    if (!await _confirmLargeExport(selectedIndexes) || !mounted) return;
    final snapshot = _document ?? _captureDocument();
    final pages = snapshot.toPages();
    BuildContext? progressContext;
    var dialogVisible = false;
    try {
      final warnings = <String>[];
      for (final index in selectedIndexes) {
        for (final bubble in pages[index].placements) {
          final font = await FontLibrary.instance.resolve(bubble.fontFamily,
              assetId: bubble.fontAssetId, text: bubble.caption.text);
          if (font.hasWarning) {
            warnings.add(
                '${index + 1} · ${bubble.caption.bubbleId}：字体缺失/缺字，将使用替代字形');
          }
          final layout = const TextLayoutService().layout(bubble);
          if (layout.overflow) {
            warnings
                .add('${index + 1} · ${bubble.caption.bubbleId}：文字超框，可遮挡其他内容');
          }
          final widestLine = layout.painter.computeLineMetrics().fold<double>(
              layout.painter.width, (w, line) => math.max(w, line.width));
          final painted = Rect.fromLTWH(
                  bubble.x + layout.paintOffset.dx,
                  bubble.y + layout.paintOffset.dy,
                  widestLine,
                  layout.painter.height)
              .inflate(bubble.textStrokeWidth / 2);
          if (painted.left < 0 ||
              painted.top < 0 ||
              painted.right > pages[index].originalWidth ||
              painted.bottom > pages[index].originalHeight) {
            warnings
                .add('${index + 1} · ${bubble.caption.bubbleId}：文字出界，将被整页边界裁切');
          }
          layout.dispose();
        }
      }
      if (!mounted) return;
      if (warnings.isNotEmpty) {
        final proceed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('导出技术预检'),
                    content: SingleChildScrollView(
                        child: Text(
                            '${warnings.take(20).join('\n')}\n\n继续会保留预览中的字号和断行，不自动缩字；文字可越框，但整页边界仍裁切。')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('返回调整')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('确认并继续'))
                    ]));
        if (proceed != true) return;
      }
      final directory =
          _useBrowserDownloads && supportsIndividualBrowserDownloads
              ? 'browser-download:individual-png'
              : await chooseImageExportDirectory(
                  initialDirectory: _settings.exportDirectory.isEmpty
                      ? null
                      : _settings.exportDirectory);
      if (directory == null || !mounted) return;
      _failedExportIndexes.clear();
      _cancelExport = false;
      _exportDone = 0;
      _exportTotal = selectedIndexes.length;
      setState(() => _exporting = true);
      dialogVisible = true;
      unawaited(showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (c) {
            progressContext = c;
            return PopScope(
                canPop: false,
                child: ValueListenableBuilder<int>(
                    valueListenable: _exportProgress,
                    builder: (context, _, child) => AlertDialog(
                            title: const Text('正在导出图片'),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LinearProgressIndicator(
                                      value: _exportTotal == 0
                                          ? 0
                                          : _exportDone / _exportTotal),
                                  const SizedBox(height: 12),
                                  Text(
                                      '$_exportDone / $_exportTotal · 修订 ${snapshot.revision}'),
                                  Text(exportTargetLabel(directory),
                                      style: const TextStyle(fontSize: 11))
                                ]),
                            actions: [
                              TextButton(
                                  onPressed: () {
                                    _cancelExport = true;
                                    _exportProgress.value++;
                                  },
                                  child: Text(
                                      _cancelExport ? '正在取消（当前文件完成后）' : '取消'))
                            ])));
          }).whenComplete(() => dialogVisible = false));
      var exported = 0, skipped = 0;
      var overwriteAll = false;
      final errors = <String>[];
      for (final index in selectedIndexes) {
        if (_cancelExport || !mounted) break;
        final fileName = exportImageName(pages[index], index,
            numbered: _settings.numberedExportNames);
        var overwrite = overwriteAll;
        if (!overwrite && await exportImageExists(directory, fileName)) {
          final choice = await _askExistingImage(fileName);
          if (choice == _ExistingImageChoice.cancel) {
            _cancelExport = true;
            break;
          }
          if (choice == _ExistingImageChoice.skip) {
            skipped++;
            _exportDone++;
            _exportProgress.value++;
            continue;
          }
          overwriteAll = choice == _ExistingImageChoice.overwriteAll;
          overwrite = true;
        }
        try {
          final rendered = await renderPageForExport(pages[index], index,
              numbered: _settings.numberedExportNames);
          if (_cancelExport) break;
          await writeExportImage(directory, rendered.fileName, rendered.bytes,
              overwrite: overwrite);
          exported++;
        } catch (error) {
          _failedExportIndexes.add(index);
          errors.add('$fileName：$error');
        }
        _exportDone++;
        if (mounted) _exportProgress.value++;
        await Future<void>.delayed(Duration.zero);
      }
      if (dialogVisible && progressContext?.mounted == true) {
        Navigator.pop(progressContext!);
      }
      if (mounted) {
        setState(() => _exporting = false);
        await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
                    title: Text(_cancelExport
                        ? '导出已取消'
                        : errors.isNotEmpty
                            ? '部分图片导出失败'
                            : '导出结束'),
                    content: SingleChildScrollView(
                        child: Text(
                            '$exported 张${isBrowserDownloadExport(directory) ? '已交给浏览器下载（请检查下载记录）' : '已写入目录'}；跳过 $skipped 张，失败 ${errors.length} 张。\n${errors.take(10).join('\n')}\n'
                            '${isBrowserDownloadExport(directory) ? '若浏览器阻止连续下载，请允许该站点多文件下载，或使用下方逐图保存。' : exportTargetLabel(directory)}')),
                    actions: [
                      if (isBrowserDownloadExport(directory))
                        TextButton(
                            onPressed: () {
                              Navigator.pop(c);
                              _showManualDownloadList(pages, selectedIndexes);
                            },
                            child: const Text('逐图保存列表')),
                      if (_failedExportIndexes.isNotEmpty)
                        TextButton(
                            onPressed: () {
                              final retry = List<int>.of(_failedExportIndexes);
                              Navigator.pop(c);
                              _exportAll(retryIndexes: retry);
                            },
                            child: const Text('重试失败图片')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('关闭'))
                    ]));
      }
    } catch (error) {
      if (mounted) {
        if (dialogVisible && progressContext?.mounted == true) {
          Navigator.pop(progressContext!);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      _disposePages(pages);
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showManualDownloadList(
      List<ImagePage> pages, List<int> indexes) async {
    // Retain pixels independently from the job which may have completed.
    final copy = ProjectDocument.capture(pages, _documentAssets,
            revision: _editRevision,
            script: buildBcsScript(pages),
            selectedPage: 0,
            selectedBubble: 0)
        .toPages();
    try {
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('逐图保存'),
                  content: SizedBox(
                      width: 420,
                      height: 350,
                      child: ListView(children: [
                        for (final index in indexes)
                          ListTile(
                              title: Text(copy[index].name),
                              trailing: IconButton(
                                  icon: const Icon(Icons.download),
                                  onPressed: () async {
                                    final jobPage = DocumentPage.capture(
                                            copy[index], _documentAssets)
                                        .toPage();
                                    try {
                                      final rendered =
                                          await renderPageForExport(
                                              jobPage, index,
                                              numbered: _settings
                                                  .numberedExportNames);
                                      await writeExportImage(
                                          'browser-download:manual',
                                          rendered.fileName,
                                          rendered.bytes,
                                          overwrite: true);
                                    } catch (error) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content:
                                                    Text('单张导出失败：$error')));
                                      }
                                    } finally {
                                      jobPage.dispose();
                                    }
                                  }))
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('关闭'))
                  ]));
    } finally {
      _disposePages(copy);
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
            if (supportsIndividualBrowserDownloads)
              TextButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          _useBrowserDownloads = true;
                          Navigator.pop(
                              dialogContext, selected.toList()..sort());
                        },
                  child: Text('直接逐图下载 ${selected.length} 张')),
            FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      _useBrowserDownloads = false;
                      Navigator.pop(dialogContext, selected.toList()..sort());
                    },
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
    if (_pages.isEmpty) return;
    _finishEdit();
    _autoSaveTimer?.cancel();
    try {
      await _persistLocalProject(includeManifest: true);
      await _saveQueue.flush();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_quickFeedback('已保存当前项目 · 修订 $_editRevision'));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，修改仍保留：$error')));
      }
    }
  }

  Future<void> _showSavedVersions() async {
    try {
      _finishEdit();
      if (_dirty) await _persistLocalProject(includeManifest: true);
      await _saveQueue.flush();
      final versions = await listLocalProjectVersions(_activeProjectId);
      if (!mounted) return;
      final selected = await showDialog<LocalProjectVersion>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('保存版本历史'),
                  content: workspaceDialogContent(c,
                      maxWidth: 620,
                      maxHeight: 480,
                      child: versions.isEmpty
                          ? const Text('暂无保存版本')
                          : ListView(children: [
                              const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text(
                                      '保留最近 20 个已成功提交的版本。恢复会写入新版本，且可撤销；不会承诺恢复尚未提交的输入。')),
                              for (final version in versions)
                                ListTile(
                                    leading: const Icon(Icons.history),
                                    title: Text(version.createdAt
                                        .toLocal()
                                        .toString()
                                        .split('.')
                                        .first),
                                    subtitle: Text(
                                        '${version.isMigrationBackup ? "升级前永久备份 · " : ""}${version.name} · 修订 ${version.revision ?? "旧版"}'),
                                    onTap: () => Navigator.pop(c, version))
                            ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('取消'))
                  ]));
      if (selected == null || !mounted) return;
      final projectId = _activeProjectId;
      final bytes = await loadLocalProjectVersion(projectId, selected.id);
      if (bytes == null) throw StateError('版本不存在，当前项目未改动');
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final isManifest = payload['format'] == 'bubble-caption-studio-manifest';
      final project = isManifest
          ? await decodeProjectManifest(
              bytes,
              (pageId) => loadLocalProjectImage(projectId, pageId),
              (assetId) => loadLocalProjectAsset(projectId, assetId))
          : await decodeProject(bytes);
      if (!mounted || projectId != _activeProjectId) {
        _disposePages(project.pages);
        return;
      }
      _ensureBubbleIds(project.pages);
      final document = ProjectDocument.capture(project.pages, _documentAssets,
          revision: _editRevision,
          script: buildBcsScript(project.pages),
          selectedPage: 0,
          selectedBubble: 0,
          fonts: project.fonts);
      _restoredFontRefs.addAll(project.fontAssetReferences);
      _restoreDocument(document, record: true);
      _disposePages(project.pages);
      await _persistLocalProject(forceFull: true);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_quickFeedback('已恢复该保存版本；可撤销'));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('版本恢复失败：$error')));
      }
    }
  }

  Future<void> _exportProjectCopy() async {
    if (_pages.isEmpty) return;
    final snapshot = _document ?? _captureDocument();
    final pages = snapshot.toPages();
    try {
      final data = encodeProject(pages, snapshot.script,
          fonts: snapshot.fonts, revision: snapshot.revision);
      await saveBinaryFile(
          title: '备份工程（包含原图和字体）',
          fileName: '$_projectName.bcs.json',
          bytes: data,
          kind: 'project');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('工程备份失败：$error')));
      }
    } finally {
      _disposePages(pages);
    }
  }

  Future<void> _openProject() async {
    _finishEdit();
    _autoSaveTimer?.cancel();
    ProjectData? decodedProject;
    try {
      if (_dirty && _pages.isNotEmpty) {
        await _persistLocalProject(includeManifest: true);
      }
      await _saveQueue.flush();
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
      final newProject = await createLocalProject(
          file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
      final replacedPages = List<ImagePage>.of(_pages);
      _history.clear();
      _pendingBefore = null;
      _document = null;
      _lastSavedCheckpoint = null;
      _previousSavedCheckpoint = null;
      _documentAssets.dispose();
      _storedFontAssets.clear();
      _fontStorageReferences.clear();
      _restoredFontRefs.clear();
      _clearActiveSourceImage();
      setState(() {
        _activeProjectId = newProject.id;
        _projectName = newProject.name;
        _fontBytes
          ..clear()
          ..addAll(project.fonts);
        _importedFonts
          ..clear()
          ..addAll(project.fonts.keys);
        _restoredFontRefs.addAll(project.fontAssetReferences);
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
        _history.clear();
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
    _finishEdit();
    final baselineScript = buildBcsScript(_pages);
    var applyText = true, applyStyle = true, applyGeometry = true;
    final draft = TextEditingController(text: baselineScript);
    try {
      final appliedScript = await _showTextDialog<String>(
        draft,
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDraftState) => AlertDialog(
                  title: LText('当前字幕 / 导入草稿'),
                  content: workspaceDialogContent(
                    context,
                    maxWidth: 620,
                    maxHeight: 460,
                    child: Column(children: [
                      Wrap(children: [
                        FilterChip(
                            label: const Text('文字'),
                            selected: applyText,
                            onSelected: (v) =>
                                setDraftState(() => applyText = v)),
                        FilterChip(
                            label: const Text('样式'),
                            selected: applyStyle,
                            onSelected: (v) =>
                                setDraftState(() => applyStyle = v)),
                        FilterChip(
                            label: const Text('坐标'),
                            selected: applyGeometry,
                            onSelected: (v) =>
                                setDraftState(() => applyGeometry = v)),
                      ]),
                      const Text('只合并草稿中实际变更的字段；未修改字段保留当前编辑。',
                          style: TextStyle(fontSize: 11)),
                      Expanded(
                          child: TextField(
                        controller: draft,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        contextMenuBuilder: buildAppTextContextMenu,
                        style: const TextStyle(
                            fontFamily: 'monospace', height: 1.5),
                      )),
                    ]),
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
                      child: LText('应用字幕变更'),
                    ),
                  ],
                )),
      );
      if (appliedScript == null || !mounted) return;
      if (appliedScript == baselineScript) return;
      _remember(label: '应用字幕脚本');
      _script.text = appliedScript;
      _commandGroup = 'script-apply';
      if (!_autoArrange(
          options: ScriptImportOptions(
              text: applyText, style: applyStyle, geometry: applyGeometry),
          baselineSource: baselineScript)) return;
      try {
        // Applying a subtitle script is an explicit project milestone. Save a
        // fresh manifest as well as the lightweight edit layer before showing
        // success, so a normal app close cannot leave the next launch with
        // only the older empty manifest.
        setState(() => _processing = true);
        await _resolveDocumentFonts();
        if (mounted) setState(() => _processing = false);
        if (mounted) setState(_markDirty);
        _finishEdit();
        await _persistLocalProject(includeManifest: true);
        if (mounted) {
          final bubbleCount = _pages.fold<int>(
            0,
            (total, page) => total + page.placements.length,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            _quickFeedback(
              '字幕已应用并保存：${_pages.length} 张图片，共 $bubbleCount 个气泡。',
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: LText('字幕已应用，但本地保存失败：$error')),
          );
        }
      }
    } finally {
      // Controller ownership ends when the route transition completes.
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
      final version = await showDialog<int>(
          context: context,
          builder: (c) =>
              SimpleDialog(title: const Text('导出字幕脚本格式'), children: [
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, 3),
                    child: const Text('BCS v3（推荐，完整文字与文字样式）')),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, 2),
                    child: const Text('兼容 BCS v2（旧软件）'))
              ]));
      if (version == null || !mounted) return;
      if (version == 2) {
        final warnings = bcsV2CompatibilityWarnings(_pages);
        if (warnings.isNotEmpty) {
          final proceed = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                      title: const Text('v2 兼容导出会丢失属性'),
                      content: SingleChildScrollView(
                          child: Text(warnings.join('\n'))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('确认导出'))
                      ]));
          if (proceed != true) return;
        }
      }
      final text = buildBcsScript(_pages, version: version);
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
    const sample = '@格式=BCS顺序字幕脚本\n@版本=3\n@坐标单位=px\n\n'
        '[图片 1]\n@原文件名=example.png\n@原图尺寸=1080x1920\n\n'
        '@气泡ID=p1-b1\n@矩形=80,100,520,260\n@尾巴=右下\n@气泡=对话气泡\n@字体=Noto Sans SC\n@字号=34\n@颜色=#141518\n@行距=1.25\n@描边=2\n@白底透明度=100\n@字号模式=固定\n@文字描边=0\n@文字描边颜色=#000000\n@字距=0\n@对齐=居中\n@正文行数=1\nCaption text\n\n';
    return switch (AppLocaleController.instance.languageCode) {
      'en' => '$sample'
          'BCS v3: @正文行数 counts literal body lines; @字号模式=固定 does not shrink text. v1/v2 remain readable.\nNotes:\n'
          '• [图片 1], [图片 2] follow the confirmed image order; file names are hints only.\n'
          '• Every section requires the exact @原图尺寸=widthxheight.\n'
          '• @矩形=x,y,width,height uses source-image pixels from top-left 0,0.\n'
          '• Keep @气泡ID stable and unique to preserve manual edits.\n'
          '• @尾巴 only accepts 左上, 右上, 左下, 右下; the tail is fixed and cannot be dragged.\n'
          '• @气泡 only accepts 对话气泡, 心理气泡, 旁白框, 耳语气泡, 惊喊气泡, 纯文字.\n'
          '• @颜色 changes text only. @白底透明度 is 0–100 and changes only the fill.\n'
          '• Leave one blank line between bubble blocks. Protocol fields remain Chinese.',
      'ja' => '$sample'
          '説明：\n'
          '• [图片 1]、[图片 2] は確認済み画像順に対応し、ファイル名はヒントだけです。\n'
          '• 各画像段に正確な @原图尺寸=幅x高さ が必要です。\n'
          '• @矩形=x,y,幅,高さ は元画像ピクセルで、左上が 0,0 です。\n'
          '• @气泡ID は一意かつ安定させ、手動編集を保持します。\n'
          '• @尾巴 は 左上、右上、左下、右下 のみで、しっぽは固定されドラッグできません。\n'
          '• @气泡 は 对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡、纯文字 のみです。\n'
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
          '• @气泡 只能使用 对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡、纯文字。\n'
          '• @颜色 只改變文字；@白底透明度 為 0–100，只影響底色。\n'
          '• 氣泡區塊之間留一個空行；協定欄位保持簡體中文。',
      _ => '$sample'
          'BCS v3：@正文行数 是正文的准确行数（包括空行）；正文按原样读取。@字号模式=固定 不缩字；@文字描边、@文字描边颜色、@字距、@对齐 控制文字而非气泡边框。继续读取 v1/v2；兼容导出会提示属性损失。\n说明：\n'
          '• [图片 1]、[图片 2] 严格对应确认后的图片顺序；文件名只作提示。\n'
          '• 每张必须填写准确的 @原图尺寸=宽x高。\n'
          '• @矩形=x,y,宽,高 使用原图像素；左上角为 0,0。\n'
          '• @气泡ID 必须唯一且稳定，用于保留手工编辑。\n'
          '• @尾巴 只能使用左上、右上、左下、右下；尾部固定不可拖动。\n'
          '• @气泡 只能使用对话气泡、心理气泡、旁白框、耳语气泡、惊喊气泡、纯文字。\n'
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
              '1. 软件启动后先进入项目页。可以创建、删除或切换项目；名称留空时会按创建时间自动命名。\n\n2. 点击“添加图片”后，图片默认按文件名自然排序，例如 1、2、10。可以在顺序确认窗口继续拖动调整。\n\n3. 点击顶部“字幕”。每个 [图片 N] 段必须包含 @原图尺寸；气泡使用原图像素 @矩形=x,y,宽,高。字幕只按确认顺序对应，不按文件名匹配。\n\n4. 字幕编辑器采用草稿模式；点击取消不会改变工程。稳定的 @气泡ID 可在再次应用时保留手工位置和样式。\n\n5. 单击气泡会立即显示选框；单击画布空白处会关闭选框，直到再次单击气泡。右侧可修改文字、形状、字体、颜色、字号、行距、描边和尾巴方向。\n\n6. 编辑停止约一秒后会自动保存；保存后可使用“回退到最近保存”恢复上一个保存版本，也可用撤销恢复当前修改。导出位于右上角，不属于编辑流程。\n\n图片和字幕始终只在当前设备处理，不会上传。',
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
            _duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelection,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): _redo,
      },
      child: Focus(
        focusNode: _commandFocus,
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
                        _saveStatusIcon,
                        size: 10,
                        color: _saveStatusColor,
                      ),
                      const SizedBox(width: 4),
                      LText(
                        _saveStatusText,
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
              onPressed: (_saving || _autoSaving) ? null : _saveProject,
              tooltip:
                  _saveError == null ? tr('保存工程') : '保存失败：$_saveError · 点击重试',
              icon: (_saving || _autoSaving)
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
                  case 'backup':
                    _exportProjectCopy();
                  case 'versions':
                    _showSavedVersions();
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
                PopupMenuItem(value: 'backup', child: LText('备份工程')),
                PopupMenuItem(value: 'open', child: LText('打开工程')),
                PopupMenuItem(value: 'help', child: LText('使用指南')),
                PopupMenuItem(value: 'settings', child: LText('设置')),
              ],
            ),
          ],
        ),
      );

  Widget _header(bool wide) => Container(
        height: 76,
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
              Expanded(
                  child: Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: LText('导入图片')),
                TextButton.icon(
                    onPressed: _showScriptEditor,
                    icon: const Icon(Icons.subtitles_outlined),
                    label: LText('字幕脚本')),
                TextButton.icon(
                    onPressed: _runLayoutStep,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: LText('调整排版')),
                IconButton(
                    onPressed: () =>
                        setState(() => _showChapterText = !_showChapterText),
                    tooltip: '章节文本 / 多选对象',
                    icon: const Icon(Icons.view_list_outlined)),
              ])),
            ],
            const SizedBox(width: 12),
            if (wide)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _saveStatusIcon,
                    color: _saveStatusColor,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  LText(
                    _saveStatusText,
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
              onPressed: (_saving || _autoSaving) ? null : _saveProject,
              tooltip:
                  _saveError == null ? tr('保存工程') : '保存失败：$_saveError · 点击重试',
              icon: (_saving || _autoSaving)
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
                  case 'backup':
                    _exportProjectCopy();
                  case 'versions':
                    _showSavedVersions();
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
                PopupMenuItem(
                    value: 'versions',
                    enabled: _pages.isNotEmpty,
                    child: ListTile(
                        leading: const Icon(Icons.history),
                        title: LText('保存版本历史'))),
                PopupMenuItem(
                    value: 'backup',
                    enabled: _pages.isNotEmpty,
                    child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: LText('备份完整工程'))),
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

  Widget _desktopBody() => Row(
        children: [
          SizedBox(width: 300, child: _pageRail()),
          const VerticalDivider(width: 1),
          Expanded(
              child: Column(children: [
            Expanded(child: _workspace()),
            _chapterTextDock()
          ])),
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
              child: _canvasSelection == _CanvasSelection.image
                  ? _imageInspector()
                  : _inspector(),
            ),
          ],
        ],
      );

  Widget _mobilePortraitBody() => _workspace(compact: true);

  Widget _mobileLandscapeBody() => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;
          final pagesWidth = narrow ? 108.0 : 136.0;
          final inspectorWidth = narrow ? 188.0 : 224.0;
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
                child: _canvasSelection == _CanvasSelection.image
                    ? _imageInspector(compact: true, allowClose: false)
                    : _inspector(compact: true, allowClose: false),
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
    final hasSelection = (_canvasSelection == _CanvasSelection.bubble &&
            _bubble != null) ||
        (_canvasSelection == _CanvasSelection.image && _placedImage != null);
    if (!hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        _quickFeedback('请先点击一个气泡或图片元素，再打开属性'),
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
        builder: (context, controller) => ValueListenableBuilder<int>(
            valueListenable: _canvasRevision,
            builder: (context, revision, child) => _mobileSheet(
                  child: _canvasSelection == _CanvasSelection.image
                      ? _imageInspector(
                          compact: true,
                          controller: controller,
                          onClose: () => Navigator.pop(sheetContext),
                        )
                      : _inspector(
                          compact: true,
                          controller: controller,
                          onClose: () => Navigator.pop(sheetContext),
                        ),
                )),
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
              tooltip:
                  _undoStack.isEmpty ? tr('撤销') : '撤销 ${_undoStack.last.label}',
              icon: const Icon(Icons.undo, size: 19),
            ),
            IconButton(
              onPressed: _redoStack.isEmpty ? null : _redo,
              tooltip:
                  _redoStack.isEmpty ? tr('重做') : '重做 ${_redoStack.last.label}',
              icon: const Icon(Icons.redo, size: 19),
            ),
            PopupMenuButton<String>(
              onSelected: (value) =>
                  value == 'text' ? _addPlainText() : _addBubble(),
              tooltip: tr('添加气泡或文字'),
              icon: const Icon(Icons.add_comment_outlined, size: 19),
              iconColor: AppColors.pink,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'bubble', child: LText('添加气泡')),
                PopupMenuItem(value: 'text', child: LText('添加文字')),
              ],
            ),
            PopupMenuButton<String>(
                tooltip: '对象操作',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'delete':
                      _deleteSelection();
                    case 'duplicate':
                      _duplicateSelection();
                    case 'textList':
                      _showChapterText = true;
                      _showMobileTextList();
                  }
                },
                itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'duplicate', child: Text('复制当前对象')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('删除当前对象')),
                      const PopupMenuItem(
                          value: 'textList', child: Text('章节文本 / 多选'))
                    ]),
            PopupMenuButton<String>(
              tooltip: tr('添加图片元素'),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 19),
              onSelected: (value) {
                switch (value) {
                  case 'free':
                    _addImageElement();
                  case 'bubble':
                    _addImageElement(insideBubble: true);
                  case 'library':
                    _showStickerLibrary();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'free', child: LText('添加独立图片')),
                PopupMenuItem(
                  value: 'bubble',
                  enabled: _bubble != null,
                  child: LText('图片放进气泡'),
                ),
                PopupMenuItem(value: 'library', child: LText('打开表情包库')),
              ],
            ),
            IconButton(
              onPressed: (_canvasSelection == _CanvasSelection.bubble &&
                          _bubble != null) ||
                      (_canvasSelection == _CanvasSelection.image &&
                          _placedImage != null)
                  ? _showMobileInspectorSheet
                  : null,
              tooltip: tr('元素属性'),
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
            LayoutBuilder(
              builder: (_, toolbarBox) => toolbarBox.maxWidth < 800
                  ? _compactCanvasToolbar(page)
                  : Container(
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
                            style:
                                TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _showRendered = false),
                            style: TextButton.styleFrom(
                              foregroundColor: !_showRendered
                                  ? AppColors.pink
                                  : AppColors.muted,
                              minimumSize: const Size(42, 32),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 7),
                            ),
                            child: LText('原图'),
                          ),
                          Switch(
                            value: _showRendered,
                            onChanged: (value) =>
                                setState(() => _showRendered = value),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _showRendered = true),
                            style: TextButton.styleFrom(
                              foregroundColor: _showRendered
                                  ? AppColors.pink
                                  : AppColors.muted,
                              minimumSize: const Size(42, 32),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 7),
                            ),
                            child: LText('渲染'),
                          ),
                          const VerticalDivider(indent: 11, endIndent: 11),
                          IconButton(
                            onPressed: _undoStack.isEmpty ? null : _undo,
                            tooltip: _undoStack.isEmpty
                                ? tr('撤销')
                                : '撤销 ${_undoStack.last.label}',
                            icon: const Icon(Icons.undo, size: 20),
                          ),
                          IconButton(
                            onPressed: _redoStack.isEmpty ? null : _redo,
                            tooltip: _redoStack.isEmpty
                                ? tr('重做')
                                : '重做 ${_redoStack.last.label}',
                            icon: const Icon(Icons.redo, size: 20),
                          ),
                          IconButton(
                            onPressed: _canRollbackToLastSave
                                ? _rollbackToLastSave
                                : null,
                            tooltip: tr('回退到最近保存'),
                            icon: const Icon(Icons.restore, size: 20),
                          ),
                          const SizedBox(width: 4),
                          FilledButton.icon(
                            onPressed: _addBubble,
                            icon: const Icon(Icons.add_comment_outlined,
                                size: 18),
                            label: LText('添加气泡'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton.outlined(
                            onPressed: _addPlainText,
                            tooltip: tr('添加文字'),
                            icon: const Icon(Icons.text_fields, size: 20),
                          ),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            tooltip: tr('添加图片元素'),
                            icon: const Icon(Icons.add_photo_alternate_outlined,
                                size: 21),
                            onSelected: (value) {
                              switch (value) {
                                case 'free':
                                  _addImageElement();
                                case 'bubble':
                                  _addImageElement(insideBubble: true);
                                case 'library':
                                  _showStickerLibrary();
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'free',
                                child: ListTile(
                                  leading: const Icon(Icons.image_outlined),
                                  title: LText('添加独立图片'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'bubble',
                                enabled: _bubble != null,
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.bubble_chart_outlined),
                                  title: LText('图片放进当前气泡'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'library',
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.emoji_emotions_outlined),
                                  title: LText('全局表情包库'),
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                          PopupMenuButton<String>(
                            tooltip: tr('气泡编辑命令'),
                            icon: const Icon(Icons.edit_note, size: 21),
                            onSelected: (value) {
                              switch (value) {
                                case 'new':
                                  _addBubble();
                                case 'text':
                                  _addPlainText();
                                case 'rollback':
                                  _rollbackToLastSave();
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
                                value: 'rollback',
                                enabled: _canRollbackToLastSave,
                                child: ListTile(
                                  leading: const Icon(Icons.restore),
                                  title: LText('回退到最近保存'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'new',
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.add_comment_outlined),
                                  title: LText('新建气泡'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'text',
                                child: ListTile(
                                  leading: const Icon(Icons.text_fields),
                                  title: LText('添加文字'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'duplicate',
                                enabled: _bubble != null,
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.content_copy_outlined),
                                  title: LText('复制气泡'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'back',
                                enabled: _bubble != null,
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.flip_to_back_outlined),
                                  title: LText('下移一层'),
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'front',
                                enabled: _bubble != null,
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.flip_to_front_outlined),
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

                int hitTestImage(Offset local) {
                  final point = Offset(local.dx / sx, local.dy / sy);
                  return hitTestPlacedImage(page.placedImages, point);
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

                _DragMode? hitImageHandle(Offset local, PlacedImage image) {
                  final point = Offset(local.dx / sx, local.dy / sy);
                  final center = Offset(
                    image.x + image.width / 2,
                    image.y + image.height / 2,
                  );
                  final translated = point - center;
                  final cosine = math.cos(-image.rotation);
                  final sine = math.sin(-image.rotation);
                  final rotated = Offset(
                        translated.dx * cosine - translated.dy * sine,
                        translated.dx * sine + translated.dy * cosine,
                      ) +
                      center;
                  final rect = Rect.fromLTWH(
                    image.x,
                    image.y,
                    image.width,
                    image.height,
                  );
                  final scale = (sx + sy) / 2;
                  final radius = 22 / scale;
                  if ((rotated - Offset(rect.center.dx, rect.top - 30 / scale))
                          .distance <=
                      radius) {
                    return _DragMode.rotate;
                  }
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
                    if ((rotated - handles[i]).distance <= radius) {
                      return modes[i];
                    }
                  }
                  return null;
                }

                (_CanvasSelection, int, _DragMode)? interactionAt(
                    Offset local) {
                  if (!_showRendered) return null;
                  if (_selectionVisible &&
                      _canvasSelection == _CanvasSelection.image &&
                      page.placedImages.isNotEmpty &&
                      _selectedImage < page.placedImages.length) {
                    final selectedMode = hitImageHandle(
                      local,
                      page.placedImages[_selectedImage],
                    );
                    if (selectedMode != null) {
                      return (
                        _CanvasSelection.image,
                        _selectedImage,
                        selectedMode,
                      );
                    }
                  }
                  if (_selectionVisible &&
                      _canvasSelection == _CanvasSelection.bubble &&
                      page.placements.isNotEmpty &&
                      _selectedBubble < page.placements.length) {
                    final selectedMode = hitHandle(
                      local,
                      page.placements[_selectedBubble],
                    );
                    if (selectedMode != null) {
                      return (
                        _CanvasSelection.bubble,
                        _selectedBubble,
                        selectedMode,
                      );
                    }
                  }
                  final imageIndex = hitTestImage(local);
                  if (imageIndex >= 0) {
                    return (
                      _CanvasSelection.image,
                      imageIndex,
                      hitImageHandle(local, page.placedImages[imageIndex]) ??
                          _DragMode.move,
                    );
                  }
                  final index = hitTest(local);
                  if (index < 0) return null;
                  return (
                    _CanvasSelection.bubble,
                    index,
                    hitHandle(local, page.placements[index]) ?? _DragMode.move,
                  );
                }

                void applyPointerSelection(
                  (_CanvasSelection, int, _DragMode)? interaction, {
                  bool beginDrag = false,
                }) {
                  setState(() {
                    if (interaction == null) {
                      _selectionVisible = false;
                      _canvasSelection = _CanvasSelection.none;
                      _dragMode = null;
                      _hoverMode = null;
                      return;
                    }
                    _canvasSelection = interaction.$1;
                    if (interaction.$1 == _CanvasSelection.bubble) {
                      _selectedBubble = interaction.$2;
                    } else {
                      _selectedImage = interaction.$2;
                    }
                    _selectionVisible = true;
                    _inspectorVisible = true;
                    if (beginDrag) {
                      _dragMode = interaction.$3;
                      _hoverMode = interaction.$3;
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
                      _DragMode.rotate => SystemMouseCursors.grab,
                      null => SystemMouseCursors.basic,
                    };

                return InteractiveViewer(
                  panEnabled: _canvasSelection == _CanvasSelection.none,
                  scaleEnabled: true,
                  child: Center(
                    child: MouseRegion(
                      cursor: cursorFor(_dragMode ?? _hoverMode),
                      onHover: (event) {
                        if (_dragMode != null) return;
                        final mode = interactionAt(event.localPosition)?.$3;
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
                            _finishEdit();
                            _commandGroup =
                                'drag:${page.pageId}:$_selectedBubble:$_selectedImage';
                            _remember(currentPageOnly: true, label: '移动/调整对象');
                          },
                          onPanUpdate: (details) {
                            final mode = _dragMode;
                            if (mode == null) return;
                            final dx = details.delta.dx / sx;
                            final dy = details.delta.dy / sy;
                            if (_canvasSelection == _CanvasSelection.image) {
                              final image = _placedImage;
                              if (image == null) return;
                              if (mode == _DragMode.rotate) {
                                final center = Offset(
                                  image.x + image.width / 2,
                                  image.y + image.height / 2,
                                );
                                final point = Offset(
                                  details.localPosition.dx / sx,
                                  details.localPosition.dy / sy,
                                );
                                _replacePlacedImageDuringDrag(
                                  image.copyWith(
                                    rotation: math.atan2(
                                          point.dy - center.dy,
                                          point.dx - center.dx,
                                        ) +
                                        math.pi / 2,
                                  ),
                                );
                                return;
                              }
                              const minimum = 24.0;
                              var left = image.x;
                              var top = image.y;
                              var right = image.x + image.width;
                              var bottom = image.y + image.height;
                              switch (mode) {
                                case _DragMode.move:
                                  left = (left + dx).clamp(
                                    0,
                                    page.originalWidth - image.width,
                                  );
                                  top = (top + dy).clamp(
                                    0,
                                    page.originalHeight - image.height,
                                  );
                                  right = left + image.width;
                                  bottom = top + image.height;
                                case _DragMode.topLeft:
                                  left = (left + dx).clamp(0, right - minimum);
                                  top = (top + dy).clamp(0, bottom - minimum);
                                case _DragMode.top:
                                  top = (top + dy).clamp(0, bottom - minimum);
                                case _DragMode.topRight:
                                  right = (right + dx).clamp(
                                    left + minimum,
                                    page.originalWidth.toDouble(),
                                  );
                                  top = (top + dy).clamp(0, bottom - minimum);
                                case _DragMode.right:
                                  right = (right + dx).clamp(
                                    left + minimum,
                                    page.originalWidth.toDouble(),
                                  );
                                case _DragMode.bottomRight:
                                  right = (right + dx).clamp(
                                    left + minimum,
                                    page.originalWidth.toDouble(),
                                  );
                                  bottom = (bottom + dy).clamp(
                                    top + minimum,
                                    page.originalHeight.toDouble(),
                                  );
                                case _DragMode.bottom:
                                  bottom = (bottom + dy).clamp(
                                    top + minimum,
                                    page.originalHeight.toDouble(),
                                  );
                                case _DragMode.bottomLeft:
                                  left = (left + dx).clamp(0, right - minimum);
                                  bottom = (bottom + dy).clamp(
                                    top + minimum,
                                    page.originalHeight.toDouble(),
                                  );
                                case _DragMode.left:
                                  left = (left + dx).clamp(0, right - minimum);
                                case _DragMode.rotate:
                                  return;
                              }
                              _replacePlacedImageDuringDrag(
                                image.copyWith(
                                  x: left,
                                  y: top,
                                  width: right - left,
                                  height: bottom - top,
                                ),
                              );
                              return;
                            }
                            final b = _bubble;
                            if (b == null) return;
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
                              case _DragMode.rotate:
                                return;
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
                          onPanEnd: (_) {
                            _finishEdit();
                            setState(() => _dragMode = null);
                          },
                          onPanCancel: () {
                            _finishEdit();
                            setState(() => _dragMode = null);
                          },
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
                                  child: ManagedPagePaint(
                                    key: ValueKey((
                                      page.pageId,
                                      _selectionVisible ? _selectedBubble : -1,
                                      _canvasSelection,
                                      _selectionVisible ? _selectedImage : -1,
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
                                              _canvasSelection !=
                                                  _CanvasSelection.bubble ||
                                              page.placements.isEmpty
                                          ? null
                                          : _selectedBubble,
                                      selectedImageIndex: !_showRendered ||
                                              !_selectionVisible ||
                                              _canvasSelection !=
                                                  _CanvasSelection.image ||
                                              page.placedImages.isEmpty
                                          ? null
                                          : _selectedImage,
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
    final bubble = _canvasSelection == _CanvasSelection.bubble ? _bubble : null;
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
                    '点击画布对象开始编辑',
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
                    child: FilledButton.tonalIcon(
                      onPressed: _page == null ? null : _addBubble,
                      icon: const Icon(Icons.add_comment_outlined),
                      label: LText('添加空白气泡'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _page == null ? null : _addPlainText,
                      icon: const Icon(Icons.text_fields),
                      label: LText('添加文字'),
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
                    bubble.shape == BubbleShape.plainText ? '文字属性' : '气泡属性',
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
                  BubbleShape.rounded => '旁白框 · 纯黑直角框，无尾巴',
                  BubbleShape.shout => '惊喊气泡 · 尖锐轮廓，适合强烈情绪',
                  BubbleShape.thought => '心理气泡 · 云朵主体，圆点指向角色',
                  BubbleShape.whisper => '耳语气泡 · 虚线轮廓，四向指向尾巴',
                  BubbleShape.plainText => '纯文字 · 无底色、无边框、无尾巴',
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
            BubbleTextEditor(
              key: ValueKey(
                '${page.pageId}-${bubble.caption.bubbleId}',
              ),
              editorId: '${page.pageId}-${bubble.caption.bubbleId}',
              text: bubble.caption.text,
              compact: compact,
              onTap: () {},
              onUndo: _undo,
              onRedo: _redo,
              onCommit: _finishEdit,
              onChanged: (value) => _editText(_bubble ?? bubble, value),
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
                  BubbleShape.plainText,
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
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _importFont,
                      icon: const Icon(Icons.font_download_outlined),
                      label: Text(
                          bubble.fontDisplayName ??
                              FontLibrary.instance
                                  .recordFor(bubble.fontFamily)
                                  ?.displayName ??
                              bubble.fontFamily,
                          overflow: TextOverflow.ellipsis))),
              IconButton(
                  onPressed: _importFont,
                  tooltip: '搜索 / 导入 / 收藏字体',
                  icon: const Icon(Icons.manage_search)),
            ]),
            FutureBuilder<FontResolution>(
                future: FontLibrary.instance.resolve(bubble.fontFamily,
                    assetId: bubble.fontAssetId, text: bubble.caption.text),
                builder: (context, result) => result.data?.hasWarning == true
                    ? Text(
                        result.data!.missingFont
                            ? '缺失字体：正在临时使用思源黑体，原字体标识保留'
                            : '当前字体存在缺字：${result.data!.missingGlyphs.length} 字',
                        style: const TextStyle(
                            color: Colors.deepOrange, fontSize: 11))
                    : const SizedBox.shrink()),
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
            SegmentedButton<TextSizeMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8))),
                segments: const [
                  ButtonSegment(value: TextSizeMode.fixed, label: Text('固定字号')),
                  ButtonSegment(value: TextSizeMode.fit, label: Text('自动适应'))
                ],
                selected: {bubble.textSizeMode},
                onSelectionChanged: (value) => _replaceBubble(
                    bubble.copyWith(textSizeMode: value.single),
                    remember: true)),
            const SizedBox(height: 8),
            _textMetricsLabel(bubble),
            _sliderRow(
              '字体大小',
              bubble.fontSize,
              TextStyleLimits.minFontSize,
              TextStyleLimits.maxFontSize,
              (value) => _replaceBubble(bubble.copyWith(fontSize: value)),
            ),
            _sliderRow(
              '行间距',
              bubble.lineHeight,
              TextStyleLimits.minLineHeight,
              TextStyleLimits.maxLineHeight,
              (value) => _replaceBubble(bubble.copyWith(lineHeight: value)),
            ),
            _sliderRow(
                '字距',
                bubble.letterSpacing,
                TextStyleLimits.minLetterSpacing,
                TextStyleLimits.maxLetterSpacing,
                (value) =>
                    _replaceBubble(bubble.copyWith(letterSpacing: value))),
            _sliderRow(
                '文字描边',
                bubble.textStrokeWidth,
                0,
                20,
                (value) =>
                    _replaceBubble(bubble.copyWith(textStrokeWidth: value))),
            TextButton.icon(
                onPressed: () => _pickTextStrokeColor(bubble),
                icon: Icon(Icons.color_lens,
                    color: Color(bubble.textStrokeColorValue)),
                label: const Text('描边颜色')),
            Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('文字对齐'),
                  for (final alignment in [
                    TextAlign.left,
                    TextAlign.center,
                    TextAlign.right
                  ])
                    IconButton(
                        onPressed: () => _replaceBubble(
                            bubble.copyWith(textAlign: alignment),
                            remember: true),
                        color: bubble.textAlign == alignment
                            ? AppColors.pink
                            : AppColors.muted,
                        tooltip: alignment.name,
                        icon: Icon(alignment == TextAlign.left
                            ? Icons.format_align_left
                            : alignment == TextAlign.right
                                ? Icons.format_align_right
                                : Icons.format_align_center))
                ]),
            _linkedStyleControls(bubble),
            if (bubble.shape != BubbleShape.plainText) ...[
              _sliderRow(
                '气泡边框',
                bubble.strokeWidth,
                TextStyleLimits.minStrokeWidth,
                TextStyleLimits.maxStrokeWidth,
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
            ],
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
            ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _deleteBubble();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: LText(bubble.shape == BubbleShape.plainText
                      ? '删除此文字'
                      : '删除此气泡'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imageInspector({
    bool compact = false,
    ScrollController? controller,
    VoidCallback? onClose,
    bool allowClose = true,
  }) {
    final image = _placedImage;
    final page = _page;
    if (image == null || page == null) {
      return ColoredBox(
        color: AppColors.panel,
        child: Center(child: LText('请先选择一个图片元素')),
      );
    }
    final bubbleIds = {
      for (final bubble in page.placements) bubble.caption.bubbleId
    };
    final binding = bubbleIds.contains(image.bubbleId) ? image.bubbleId : null;
    Widget sliderRow(
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> changed, {
      String Function(double)? formatter,
    }) =>
        Row(
          children: [
            SizedBox(
              width: 76,
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
                onChangeStart: (_) {
                  _finishEdit();
                  _commandGroup = 'slider:$label:${_bubble?.caption.bubbleId}';
                  _remember(currentPageOnly: true, label: '修改$label');
                },
                onChangeEnd: (_) => _finishEdit(),
                onChanged: changed,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                formatter?.call(value) ?? value.toStringAsFixed(0),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        );
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
                const Icon(Icons.image_outlined, color: AppColors.pink),
                const SizedBox(width: 8),
                Expanded(
                  child: LText(
                    '图片属性',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (allowClose)
                  IconButton(
                    onPressed: onClose ??
                        () => setState(() => _inspectorVisible = false),
                    tooltip: tr('关闭属性面板'),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            Text(
              image.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 2.4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: RawImage(image: image.image, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LText('显示方式',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<PlacedImageFit>(
              segments: const [
                ButtonSegment(
                  value: PlacedImageFit.contain,
                  icon: Icon(Icons.fit_screen),
                  label: Text('完整显示'),
                ),
                ButtonSegment(
                  value: PlacedImageFit.cover,
                  icon: Icon(Icons.crop),
                  label: Text('铺满裁剪'),
                ),
              ],
              selected: {image.fit},
              onSelectionChanged: (value) => _replacePlacedImage(
                  image.copyWith(fit: value.first),
                  remember: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: binding,
              decoration: InputDecoration(labelText: tr('放置方式')),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: LText('独立图片，不裁剪')),
                for (var i = 0; i < page.placements.length; i++)
                  DropdownMenuItem<String?>(
                    value: page.placements[i].caption.bubbleId,
                    child: LText('放入气泡 ${i + 1}'),
                  ),
              ],
              onChanged: (value) => _replacePlacedImage(
                  image.copyWith(bubbleId: value),
                  remember: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PlacedImageLayer>(
              value: image.layer,
              decoration: InputDecoration(labelText: tr('图片层级')),
              items: const [
                DropdownMenuItem(
                  value: PlacedImageLayer.behindBubbles,
                  child: Text('文字和气泡下方'),
                ),
                DropdownMenuItem(
                  value: PlacedImageLayer.aboveBubbles,
                  child: Text('文字和气泡上方'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _replacePlacedImage(image.copyWith(layer: value),
                      remember: true);
                }
              },
            ),
            const SizedBox(height: 10),
            sliderRow(
              '透明度',
              image.opacity,
              0,
              1,
              (value) => _replacePlacedImage(image.copyWith(opacity: value)),
              formatter: (value) => '${(value * 100).round()}%',
            ),
            sliderRow(
              '旋转',
              image.rotation,
              -math.pi,
              math.pi,
              (value) => _replacePlacedImage(image.copyWith(rotation: value)),
              formatter: (value) => '${(value * 180 / math.pi).round()}°',
            ),
            if (image.fit == PlacedImageFit.cover) ...[
              sliderRow(
                '水平裁剪',
                image.cropX,
                0,
                1,
                (value) => _replacePlacedImage(image.copyWith(cropX: value)),
                formatter: (value) => '${(value * 100).round()}%',
              ),
              sliderRow(
                '垂直裁剪',
                image.cropY,
                0,
                1,
                (value) => _replacePlacedImage(image.copyWith(cropY: value)),
                formatter: (value) => '${(value * 100).round()}%',
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _movePlacedImageLayer(-1),
                    icon: const Icon(Icons.flip_to_back_outlined),
                    label: LText('下移一层'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _movePlacedImageLayer(1),
                    icon: const Icon(Icons.flip_to_front_outlined),
                    label: LText('上移一层'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deletePlacedImage,
                icon: const Icon(Icons.delete_outline),
                label: LText('删除图片元素'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shapeButton(BubbleShape shape, BubblePlacement bubble) {
    final selected = shape == bubble.shape;
    final icon = switch (shape) {
      BubbleShape.ellipse => Icons.chat_bubble_outline,
      BubbleShape.rounded => Icons.crop_square,
      BubbleShape.shout => Icons.brightness_7_outlined,
      BubbleShape.thought => Icons.cloud_outlined,
      BubbleShape.whisper => Icons.blur_on_outlined,
      BubbleShape.plainText => Icons.text_fields,
    };
    final label = switch (shape) {
      BubbleShape.ellipse => '对话气泡',
      BubbleShape.rounded => '旁白框',
      BubbleShape.shout => '惊喊气泡',
      BubbleShape.thought => '心理气泡',
      BubbleShape.whisper => '耳语气泡',
      BubbleShape.plainText => '纯文字',
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
                onChangeStart: (_) {
                  _finishEdit();
                  _commandGroup = 'slider:$label:${_bubble?.caption.bubbleId}';
                  _remember(currentPageOnly: true, label: '修改$label');
                },
                onChangeEnd: (_) => _finishEdit(),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 42,
              child: InkWell(
                  onTap: () async {
                    final controller =
                        TextEditingController(text: value.toStringAsFixed(2));
                    final changed = await _showTextDialog<double>(controller,
                        context: context,
                        builder: (c) => AlertDialog(
                                title: Text(label),
                                content: TextField(
                                    controller: controller,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true, signed: true),
                                    decoration: InputDecoration(
                                        helperText: '$min – $max')),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('取消')),
                                  FilledButton(
                                      onPressed: () {
                                        final n =
                                            double.tryParse(controller.text);
                                        if (n != null &&
                                            n.isFinite &&
                                            n >= min &&
                                            n <= max) Navigator.pop(c, n);
                                      },
                                      child: const Text('应用'))
                                ]));
                    // Controller ownership ends when the route transition completes.
                    if (changed == null || !mounted) return;
                    _finishEdit();
                    _remember(label: '修改$label');
                    onChanged(changed);
                    _finishEdit();
                  },
                  child: Text(
                      percent
                          ? '${value.round()}%'
                          : value.toStringAsFixed(
                              label == '行间距' || label == '字距' ? 1 : 0),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700))),
            ),
          ],
        ),
      );
}
