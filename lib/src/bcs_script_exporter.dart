import 'dart:ui' as ui;

import 'models.dart';

String buildBcsScript(List<ImagePage> pages, {int version = 3}) {
  if (version != 2 && version != 3) {
    throw ArgumentError.value(
        version, 'version', 'Only BCS 2 and 3 can be exported');
  }
  final output = StringBuffer()
    ..writeln('@格式=BCS顺序字幕脚本')
    ..writeln('@版本=$version')
    ..writeln('@坐标单位=px')
    ..writeln();

  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final page = pages[pageIndex];
    output
      ..writeln('[图片 ${pageIndex + 1}]')
      ..writeln('@原文件名=${page.name}')
      ..writeln('@原图尺寸=${page.originalWidth}x${page.originalHeight}')
      ..writeln();

    for (var bubbleIndex = 0;
        bubbleIndex < page.placements.length;
        bubbleIndex++) {
      final bubble = page.placements[bubbleIndex];
      final caption = bubble.caption;
      final bubbleId = caption.bubbleId.trim().isEmpty
          ? 'p${pageIndex + 1}-b${bubbleIndex + 1}'
          : caption.bubbleId.trim();
      output
        ..writeln('@气泡ID=$bubbleId')
        ..writeln(
          '@矩形=${bcsNumber(bubble.x)},${bcsNumber(bubble.y)},${bcsNumber(bubble.width)},${bcsNumber(bubble.height)}',
        )
        ..writeln('@尾巴=${bcsTailName(bubble.tailDirection)}')
        ..writeln('@气泡=${bcsShapeName(bubble.shape)}')
        ..writeln('@字体=${bcsFontName(bubble)}')
        ..writeln('@字号=${bcsNumber(bubble.fontSize)}')
        ..writeln(
          '@颜色=#${bubble.fontColorValue.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
        )
        ..writeln('@行距=${bcsNumber(bubble.lineHeight)}')
        ..writeln('@描边=${bcsNumber(bubble.strokeWidth)}')
        ..writeln('@白底透明度=${bcsNumber(bubble.fillOpacity * 100)}');
      if (version >= 3) {
        output
          ..writeln(
              '@字号模式=${bubble.textSizeMode == TextSizeMode.fixed ? '固定' : '自动适配'}')
          ..writeln('@文字描边=${bcsNumber(bubble.textStrokeWidth)}')
          ..writeln(
              '@文字描边颜色=#${bubble.textStrokeColorValue.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}')
          ..writeln('@字距=${bcsNumber(bubble.letterSpacing)}')
          ..writeln('@对齐=${bcsTextAlignName(bubble.textAlign)}');
        if (bubble.fontAssetId?.isNotEmpty == true) {
          output.writeln('@字体素材ID=${bubble.fontAssetId}');
        }
        if (bubble.styleId?.isNotEmpty == true) {
          output.writeln('@样式ID=${bubble.styleId}');
        }
        output.writeln(
            '@正文行数=${caption.text.isEmpty ? 0 : caption.text.split('\n').length}');
      }
      if (version < 3 || caption.text.isNotEmpty) output.writeln(caption.text);
      output.writeln();
    }
  }

  return '${output.toString().trimRight()}\n';
}

String bcsFontName(BubblePlacement bubble) {
  final label = bubble.fontDisplayName?.trim();
  if (label != null && label.isNotEmpty) return label;
  // A content-addressed asset identifies the font; a runtime alias is not its
  // user-facing name. The asset ID is separately included by BCS 3.
  if (bubble.fontAssetId?.isNotEmpty == true) return '导入字体';
  return bubble.fontFamily;
}

String bcsNumber(double value) =>
    value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');

String bcsTextAlignName(ui.TextAlign value) => switch (value) {
      ui.TextAlign.left || ui.TextAlign.start => '左对齐',
      ui.TextAlign.right || ui.TextAlign.end => '右对齐',
      _ => '居中',
    };

List<String> bcsV2CompatibilityWarnings(List<ImagePage> pages) {
  final bubbles = pages.expand((page) => page.placements).toList();
  return [
    if (bubbles.any((bubble) => bubble.textSizeMode == TextSizeMode.fixed))
      'BCS v2 不记录固定字号模式；再次导入时使用自动适配。',
    if (bubbles.any((bubble) => bubble.textStrokeWidth != 0))
      'BCS v2 不记录文字描边与描边颜色。',
    if (bubbles.any((bubble) =>
        bubble.letterSpacing != 0 || bubble.textAlign != ui.TextAlign.center))
      'BCS v2 不记录字距与文字对齐。',
    if (bubbles.any((bubble) => bubble.fontAssetId != null))
      'BCS v2 不记录字体素材 ID；需在目标设备手动导入同一字体。',
    if (bubbles.any((bubble) => bubble.styleId != null))
      'BCS v2 不记录链接样式 ID；对象保留展开样式但解除链接。',
    if (bubbles.any((bubble) {
      final text = bubble.caption.text;
      return text.isEmpty ||
          text.trim() != text ||
          text.split('\n').any((line) =>
              line.trim().isEmpty ||
              RegExp(r'^\s*(?:[#@]|\[.+\]\s*$)').hasMatch(line));
    }))
      'BCS v2 无法准确表达空气泡、正文空行、首尾空白和以 @、# 或图片段标记开头的文字；请使用 v3。',
  ];
}

String bcsScriptFileName(String projectName) {
  var safeName = projectName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  safeName = safeName.replaceFirst(RegExp(r'[. ]+$'), '');
  if (safeName.isEmpty) safeName = '未命名工程';
  return '$safeName-BCS字幕脚本.txt';
}

String bcsTailName(TailDirection value) => switch (value) {
      TailDirection.upLeft => '左上',
      TailDirection.upRight => '右上',
      TailDirection.downLeft => '左下',
      TailDirection.downRight => '右下',
    };

String bcsShapeName(BubbleShape value) => switch (value) {
      BubbleShape.ellipse => '对话气泡',
      BubbleShape.rounded => '旁白框',
      BubbleShape.shout => '惊喊气泡',
      BubbleShape.thought => '心理气泡',
      BubbleShape.whisper => '耳语气泡',
      BubbleShape.plainText => '纯文字',
    };
