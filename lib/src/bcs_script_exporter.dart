import 'models.dart';

String buildBcsScript(List<ImagePage> pages) {
  final output = StringBuffer()
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
          '@矩形=${bubble.x.toStringAsFixed(0)},${bubble.y.toStringAsFixed(0)},${bubble.width.toStringAsFixed(0)},${bubble.height.toStringAsFixed(0)}',
        )
        ..writeln('@尾巴=${bcsTailName(bubble.tailDirection)}')
        ..writeln('@气泡=${bcsShapeName(bubble.shape)}')
        ..writeln('@字体=${bubble.fontFamily}')
        ..writeln('@字号=${bubble.fontSize.toStringAsFixed(0)}')
        ..writeln(
          '@颜色=#${bubble.fontColorValue.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
        )
        ..writeln('@行距=${bubble.lineHeight.toStringAsFixed(2)}')
        ..writeln('@描边=${bubble.strokeWidth.toStringAsFixed(1)}')
        ..writeln('@白底透明度=${(bubble.fillOpacity * 100).round()}')
        ..writeln(caption.text)
        ..writeln();
    }
  }

  return '${output.toString().trimRight()}\n';
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
    };
