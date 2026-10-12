import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'font_library.dart';

/// A local, searchable font library. The caller owns its surrounding dialog
/// and whether choosing a font closes it.
class FontPicker extends StatefulWidget {
  const FontPicker(
      {super.key,
      required this.onSelected,
      this.sampleText = '漫画对白：你好，世界！',
      this.selectedFamily,
      this.selectedAssetId,
      this.library});
  final ValueChanged<FontAsset> onSelected;
  final String sampleText;
  final String? selectedFamily;
  final String? selectedAssetId;
  final FontLibrary? library;
  @override
  State<FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<FontPicker> {
  late final FontLibrary _library = widget.library ?? FontLibrary.instance;
  late Future<void> _load;
  String _query = '';
  String _filter = '全部';
  bool _busy = false;
  String? _error;
  final Map<String, Future<FontAsset?>> _previews = {};

  @override
  void initState() {
    super.initState();
    _load = _library.load();
    _library.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _library.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _select(FontRecord record) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final asset = await _library.getAsset(record.id);
      if (asset == null) throw StateError('字体文件不可用。');
      await _library.markUsed(record.id);
      if (mounted) widget.onSelected(asset);
    } catch (error) {
      if (mounted) setState(() => _error = '字体未应用：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _favorite(FontRecord record) async {
    try {
      await _library.setFavorite(record.id, !record.favorite);
    } catch (error) {
      if (mounted) setState(() => _error = '收藏未保存：$error');
    }
  }

  Future<void> _import() async {
    final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('导入本地字体'),
                content: const Text(
                    '仅支持独立TTF、OTF，可一次选择多个文件。字体会复制到本地全局字体库，并随使用它的项目保存。请确认你有使用、嵌入及再分发这些字体的许可。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('我已确认许可，选择文件'))
                ]));
    if (allowed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['ttf', 'otf'],
          allowMultiple: true,
          withData: true);
      if (selection == null) return;
      final errors = <String, String>{};
      final inputs = <FontImportInput>[];
      for (final file in selection.files) {
        if (file.bytes == null) {
          errors[file.name] = '未读取到字体文件字节。';
        } else {
          inputs.add(FontImportInput(file.bytes!, fileName: file.name));
        }
      }
      final report = await _library.importMany(inputs);
      errors.addAll(report.errors);
      if (mounted) {
        setState(() {
          _filter = report.assets
                  .every((asset) => asset.record.source == FontSource.builtIn)
              ? '全部'
              : '已导入';
          _query = '';
          _error = errors.isEmpty
              ? null
              : errors.entries.map((e) => '${e.key}：${e.value}').join('\n');
        });
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
                '已处理${report.assets.length}个字体文件（重复内容复用），失败${errors.length}个')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败，未写入字体库：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<FontRecord> _visible() {
    final query = _query.trim().toLowerCase();
    final records = _library.records.where((font) {
      if (query.isNotEmpty &&
          !'${font.displayName} ${font.metadataFamily} ${font.runtimeFamily} ${font.fileName ?? ''} ${font.category}'
              .toLowerCase()
              .contains(query)) return false;
      return switch (_filter) {
        '内置' => font.source == FontSource.builtIn,
        '已导入' => font.source == FontSource.imported,
        '当前项目' => font.source == FontSource.project,
        '收藏' => font.favorite,
        '最近' => font.lastUsedAt != null,
        '全部' => true,
        _ => font.category == _filter,
      };
    }).toList();
    if (_filter == '最近') {
      records.sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
    }
    return records;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return SizedBox(
        width: (screen.width - 56).clamp(240, 720).toDouble(),
        height: (screen.height - 100).clamp(280, 680).toDouble(),
        child: FutureBuilder<void>(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('本地字体库加载失败：${snapshot.error}'),
                  TextButton(
                      onPressed: () => setState(() => _load = _library.load()),
                      child: const Text('重试'))
                ]));
              }
              final visible = _visible();
              final categories = _library.records
                  .map((font) => font.category)
                  .where((category) => category.isNotEmpty)
                  .toSet();
              final missing = widget.selectedFamily != null &&
                  _library.recordFor(
                          widget.selectedAssetId ?? widget.selectedFamily!) ==
                      null;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('本地字体库',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700))),
                      FilledButton.tonalIcon(
                          onPressed: _busy ? null : _import,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('批量导入'))
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索字体名称、文件名或类别',
                            border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final filter in [
                            '全部',
                            '内置',
                            '已导入',
                            '当前项目',
                            '收藏',
                            '最近',
                            ...categories
                          ])
                            Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                    label: Text(filter),
                                    selected: _filter == filter,
                                    onSelected: (_) =>
                                        setState(() => _filter = filter)))
                        ])),
                    if (missing)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                              '原字体“${widget.selectedFamily}”缺失。原身份保留，选择替换后才更改。',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    if (_error != null)
                      Flexible(
                          flex: 0,
                          child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_error!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error)))),
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Expanded(
                        child: visible.isEmpty
                            ? const Center(child: Text('没有匹配的字体'))
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (context, index) =>
                                    _fontTile(visible[index]))),
                    const Text('预览使用本地真实字体；⚠ 表示当前文字有该字体不支持的字符。',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ]);
            }));
  }

  Widget _fontTile(FontRecord record) {
    final selected = widget.selectedAssetId == record.id ||
        widget.selectedFamily == record.runtimeFamily;
    return FutureBuilder<FontAsset?>(
        future: _previews.putIfAbsent(
            record.id, () => _library.getAsset(record.id)),
        builder: (context, snapshot) {
          final asset = snapshot.data;
          final missing =
              asset?.metadata.missingCodePoints(widget.sampleText) ??
                  const <int>[];
          return Card(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: InkWell(
                  onTap:
                      _busy || snapshot.hasError ? null : () => _select(record),
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      '${record.displayName} · ${record.metadataFamily}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600))),
                              if (selected)
                                const Icon(Icons.check_circle_outline,
                                    size: 18),
                              IconButton(
                                  tooltip: record.favorite ? '取消收藏' : '收藏字体',
                                  onPressed: () => _favorite(record),
                                  icon: Icon(
                                      record.favorite
                                          ? Icons.star
                                          : Icons.star_border,
                                      size: 20))
                            ]),
                            if (snapshot.hasError)
                              Text('加载失败：${snapshot.error}',
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error))
                            else if (asset == null)
                              const SizedBox(
                                  height: 26, child: Text('正在加载本地字体…'))
                            else
                              Text(
                                  widget.sampleText.isEmpty
                                      ? '漫画对白：你好，世界！'
                                      : widget.sampleText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: asset.runtimeFamily,
                                      fontSize: 22)),
                            if (missing.isNotEmpty)
                              Text(
                                  '⚠ 缺字：${String.fromCharCodes(missing.take(12))}',
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                      fontSize: 11)),
                          ]))));
        });
  }
}
