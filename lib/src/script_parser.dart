import 'models.dart';

class ScriptImageSection {
  ScriptImageSection({
    required this.number,
    required this.legacyHeader,
    this.originalName,
  });

  final int number;
  final bool legacyHeader;
  String? originalName;
  int? declaredWidth;
  int? declaredHeight;
  final List<CaptionLine> captions = [];
}

class ScriptParseResult {
  const ScriptParseResult(
    this.byFile,
    this.unassigned, [
    this.warnings = const [],
    this.sections = const [],
  ]);
  final Map<String, List<CaptionLine>> byFile;
  final List<CaptionLine> unassigned;
  final List<String> warnings;
  final List<ScriptImageSection> sections;

  bool get usesSequentialFormat =>
      sections.any((section) => !section.legacyHeader);
}

ScriptParseResult parseCaptionScript(String source) {
  final byFile = <String, List<CaptionLine>>{};
  final unassigned = <CaptionLine>[];
  final warnings = <String>[];
  final sections = <ScriptImageSection>[];
  final directives = <String, String>{};
  final textBuffer = <String>[];
  String? currentFile;
  ScriptImageSection? currentSection;
  var blockLine = 1;

  void addCaption(CaptionLine caption) {
    currentSection?.captions.add(caption);
    if (currentFile == null) {
      unassigned.add(caption);
    } else {
      byFile.putIfAbsent(currentFile, () => []).add(caption);
    }
  }

  void flushBlock() {
    final rawText = textBuffer.join('\n').trim();
    if (rawText.isEmpty) {
      directives.clear();
      textBuffer.clear();
      return;
    }
    var speaker = directives['角色']?.trim() ?? '';
    var text = rawText;
    if (speaker.isEmpty) {
      final separator = rawText.indexOf(RegExp(r'[:：]'));
      if (separator > 0 && !rawText.substring(0, separator).contains('\n')) {
        speaker = rawText.substring(0, separator).trim();
        text = rawText.substring(separator + 1).trim();
      }
    }
    if (text.isEmpty) {
      warnings.add('第 $blockLine 行：字幕正文为空，已忽略。');
    } else {
      addCaption(
        CaptionLine(
          speaker: speaker,
          text: text,
          layout: directives.isEmpty
              ? null
              : _buildLayoutSpec(directives, blockLine, warnings),
          bubbleId: directives['气泡ID']?.trim() ?? '',
        ),
      );
    }
    directives.clear();
    textBuffer.clear();
  }

  final lines = source.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index++) {
    final lineNumber = index + 1;
    final line = lines[index].trim();
    if (line.startsWith('#')) continue;
    if (line.isEmpty) {
      if (textBuffer.isNotEmpty) flushBlock();
      continue;
    }
    final sequentialHeader = RegExp(r'^\[图片\s*(\d+)\]$').firstMatch(line);
    if (sequentialHeader != null) {
      flushBlock();
      final number = int.parse(sequentialHeader.group(1)!);
      currentFile = null;
      currentSection = ScriptImageSection(number: number, legacyHeader: false);
      sections.add(currentSection);
      blockLine = lineNumber + 1;
      continue;
    }
    final header = RegExp(r'^\[(.+?)\]$').firstMatch(line);
    if (header != null) {
      flushBlock();
      currentFile = header.group(1)!.trim();
      byFile.putIfAbsent(currentFile, () => []);
      currentSection = ScriptImageSection(
        number: sections.length + 1,
        legacyHeader: true,
        originalName: currentFile,
      );
      sections.add(currentSection);
      blockLine = lineNumber + 1;
      continue;
    }
    if (line.startsWith('@')) {
      if (textBuffer.isNotEmpty) flushBlock();
      final match = RegExp(r'^@([^=＝]+)[=＝](.*)$').firstMatch(line);
      if (match == null) {
        warnings.add('第 $lineNumber 行：指令必须使用 @名称=值。');
        continue;
      }
      final key = match.group(1)!.trim();
      final value = match.group(2)!.trim();
      if (currentSection == null && const {'格式', '版本', '坐标单位'}.contains(key)) {
        continue;
      }
      if (currentSection != null && key == '原文件名') {
        currentSection.originalName = value;
        continue;
      }
      if (currentSection != null && key == '原图尺寸') {
        final size = _parsePixelSize(value);
        if (size == null) {
          warnings.add('第 $lineNumber 行：@原图尺寸 必须是正整数宽x高，例如 1080x1920。');
        } else {
          currentSection
            ..declaredWidth = size.$1
            ..declaredHeight = size.$2;
        }
        continue;
      }
      const bubbleDirectiveKeys = {
        '气泡ID',
        '角色',
        '矩形',
        '坐标',
        '尺寸',
        '位置',
        '尾巴',
        '尾巴位置',
        '气泡',
        '字体',
        '字号',
        '颜色',
        '行距',
        '描边',
        '白底透明度',
      };
      if (!bubbleDirectiveKeys.contains(key)) {
        warnings.add('第 $lineNumber 行：未知指令 @$key，请检查拼写。');
      }
      if (key == '气泡ID' && directives.containsKey('气泡ID')) flushBlock();
      if (key == '角色' && directives.containsKey('角色')) flushBlock();
      directives[key] = value;
      blockLine = lineNumber;
      continue;
    }
    if (directives.isEmpty) {
      final separator = line.indexOf(RegExp(r'[:：]'));
      final caption = separator > 0
          ? CaptionLine(
              speaker: line.substring(0, separator).trim(),
              text: line.substring(separator + 1).trim(),
            )
          : CaptionLine(speaker: '', text: line);
      if (caption.text.isNotEmpty) addCaption(caption);
    } else {
      textBuffer.add(line);
    }
  }
  flushBlock();
  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    if (!section.legacyHeader && section.number != i + 1) {
      warnings.add('图片段顺序错误：第 ${i + 1} 段应写为 [图片 ${i + 1}]。');
    }
    if (!section.legacyHeader &&
        (section.declaredWidth == null || section.declaredHeight == null)) {
      warnings.add('第 ${section.number} 张缺少有效的 @原图尺寸。');
    }
  }
  return ScriptParseResult(byFile, unassigned, warnings, sections);
}

List<String> validateScriptForPages(
  ScriptParseResult parsed,
  List<ImagePage> pages,
) {
  final errors = <String>[];
  if (parsed.sections.length != pages.length) {
    errors.add(
      '图片共 ${pages.length} 张，但脚本有 ${parsed.sections.length} 个图片段。两者必须完全一致。',
    );
  }
  final bubbleIds = <String>{};
  for (var i = 0; i < parsed.sections.length && i < pages.length; i++) {
    final section = parsed.sections[i];
    final page = pages[i];
    if (!section.legacyHeader) {
      if (section.number != i + 1) {
        errors.add('第 ${i + 1} 个图片段必须写为 [图片 ${i + 1}]。');
      }
      if (section.declaredWidth == null || section.declaredHeight == null) {
        errors.add('第 ${i + 1} 张缺少 @原图尺寸。');
      } else if (section.declaredWidth != page.originalWidth ||
          section.declaredHeight != page.originalHeight) {
        errors.add(
          '第 ${i + 1} 张尺寸不一致：脚本 ${section.declaredWidth}x${section.declaredHeight}，实际 ${page.originalWidth}x${page.originalHeight}。',
        );
      }
    }
    for (var bubbleIndex = 0;
        bubbleIndex < section.captions.length;
        bubbleIndex++) {
      final caption = section.captions[bubbleIndex];
      final bubbleId = caption.bubbleId;
      if (!section.legacyHeader && bubbleId.isEmpty) {
        errors.add('第 ${i + 1} 张 / 气泡 ${bubbleIndex + 1} 缺少 @气泡ID。');
      } else if (bubbleId.isNotEmpty && !bubbleIds.add(bubbleId)) {
        errors.add('气泡 ID“$bubbleId”重复；每个气泡必须使用唯一 ID。');
      }
      final spec = caption.layout;
      if (spec?.x != null &&
          spec?.y != null &&
          spec?.width != null &&
          spec?.height != null &&
          (spec!.x! + spec.width! > page.originalWidth ||
              spec.y! + spec.height! > page.originalHeight)) {
        errors.add('第 ${i + 1} 张 / 气泡 ${bubbleIndex + 1} 的 @矩形 超出原图。');
      }
    }
  }
  return errors;
}

CaptionLayoutSpec _buildLayoutSpec(
  Map<String, String> values,
  int line,
  List<String> warnings,
) {
  final rect = _parsePixelRect(values['矩形'], line, warnings);
  final coordinate = _parsePercentPair(values['坐标'], '坐标', line, warnings);
  final size = _parsePercentPair(
    values['尺寸'],
    '尺寸',
    line,
    warnings,
    requirePositive: true,
  );
  final preset = values['位置']?.trim();
  const validPresets = {'左上', '中上', '右上', '左中', '居中', '右中', '左下', '中下', '右下'};
  if (preset != null && !validPresets.contains(preset)) {
    warnings.add('第 $line 行：位置“$preset”无效，请使用左上、中上、右上、左中、居中、右中、左下、中下或右下。');
  }
  final shape = switch (values['气泡']?.trim()) {
    '椭圆' || '对话' || '对话气泡' || null => BubbleShape.ellipse,
    '圆角' || '旁白' || '旁白框' => BubbleShape.rounded,
    '思考' || '心理' || '心理气泡' => BubbleShape.thought,
    '惊喊' || '震惊' || '爆炸' || '惊喊气泡' || '震惊气泡' => BubbleShape.shout,
    '耳语' || '低语' || '耳语气泡' || '低语气泡' => BubbleShape.whisper,
    final value => _warnValue<BubbleShape>(
        warnings,
        line,
        '气泡',
        value,
        BubbleShape.ellipse,
      ),
  };
  final tail = switch (values['尾巴']?.trim()) {
    '左上' => TailDirection.upLeft,
    '右上' => TailDirection.upRight,
    '左下' => TailDirection.downLeft,
    '右下' || null => TailDirection.downRight,
    '上' => TailDirection.upRight,
    '下' => TailDirection.downRight,
    '左' => TailDirection.downLeft,
    '右' => TailDirection.downRight,
    final value => _warnValue<TailDirection>(
        warnings,
        line,
        '尾巴',
        value,
        TailDirection.downRight,
      ),
  };
  final font = switch (values['字体']?.trim()) {
    null || '' => null,
    final value => normalizeBubbleFontFamily(value),
  };
  if (values.containsKey('尾巴位置')) {
    warnings.add('第 $line 行：@尾巴位置 已停用；尾部固定在气泡边缘，只需设置四向 @尾巴。');
  }
  final fillOpacityPercent = _parseNumber(
    values['白底透明度'],
    '白底透明度',
    line,
    warnings,
    0,
    100,
  );
  return CaptionLayoutSpec(
    x: rect?.$1,
    y: rect?.$2,
    width: rect?.$3,
    height: rect?.$4,
    xPercent: coordinate?.$1,
    yPercent: coordinate?.$2,
    widthPercent: size?.$1,
    heightPercent: size?.$2,
    positionPreset: validPresets.contains(preset) ? preset : null,
    shape: shape,
    tailDirection: tail,
    tailPosition: null,
    fontFamily: font,
    fontColorValue: _parseColor(values['颜色'], line, warnings),
    fontSize: _parseNumber(values['字号'], '字号', line, warnings, 8, 200),
    lineHeight: _parseNumber(values['行距'], '行距', line, warnings, .8, 3),
    strokeWidth: _parseNumber(values['描边'], '描边', line, warnings, 0, 20),
    fillOpacity: fillOpacityPercent == null ? null : fillOpacityPercent / 100,
  );
}

(int, int)? _parsePixelSize(String raw) {
  final match = RegExp(r'^(\d+)\s*[xX×]\s*(\d+)$').firstMatch(raw.trim());
  if (match == null) return null;
  final width = int.parse(match.group(1)!);
  final height = int.parse(match.group(2)!);
  if (width <= 0 || height <= 0) return null;
  return (width, height);
}

(double, double, double, double)? _parsePixelRect(
  String? raw,
  int line,
  List<String> warnings,
) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.split(RegExp(r'[,，]'));
  if (parts.length != 4) {
    warnings.add('第 $line 行：@矩形 必须是 x,y,宽,高 四个像素数值。');
    return null;
  }
  final values = parts.map((part) => double.tryParse(part.trim())).toList();
  if (values.any((value) => value == null) ||
      values[0]! < 0 ||
      values[1]! < 0 ||
      values[2]! <= 0 ||
      values[3]! <= 0) {
    warnings.add('第 $line 行：@矩形 坐标不能为负，宽高必须大于 0。');
    return null;
  }
  return (values[0]!, values[1]!, values[2]!, values[3]!);
}

(double, double)? _parsePercentPair(
  String? raw,
  String name,
  int line,
  List<String> warnings, {
  bool requirePositive = false,
}) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.split(RegExp(r'[,，]'));
  if (parts.length != 2) {
    warnings.add('第 $line 行：@$name 必须包含两个百分比，例如 68%,12%。');
    return null;
  }
  final first = double.tryParse(parts[0].replaceAll('%', '').trim());
  final second = double.tryParse(parts[1].replaceAll('%', '').trim());
  if (first == null ||
      second == null ||
      first < 0 ||
      first > 100 ||
      second < 0 ||
      second > 100 ||
      (requirePositive && (first == 0 || second == 0))) {
    warnings.add('第 $line 行：@$name 的数值必须在 0% 到 100% 之间。');
    return null;
  }
  return (first, second);
}

double? _parseNumber(
  String? raw,
  String name,
  int line,
  List<String> warnings,
  double min,
  double max,
) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  if (value == null || value < min || value > max) {
    warnings.add('第 $line 行：@$name 必须在 $min 到 $max 之间。');
    return null;
  }
  return value;
}

int? _parseColor(String? raw, int line, List<String> warnings) {
  if (raw == null || raw.trim().isEmpty) return null;
  final hex = raw.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    warnings.add('第 $line 行：@颜色 必须是六位十六进制颜色，例如 #141518。');
    return null;
  }
  return int.parse('ff$hex', radix: 16);
}

T _warnValue<T>(
  List<String> warnings,
  int line,
  String name,
  String value,
  T fallback,
) {
  warnings.add('第 $line 行：@$name 的值“$value”无效，已使用默认值。');
  return fallback;
}

List<String> naturalSort(List<String> values) {
  return [...values]..sort(compareNaturalNames);
}

int compareNaturalNames(String a, String b) {
  final token = RegExp(r'(\d+|\D+)');
  final aa = token.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final bb = token.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < aa.length && i < bb.length; i++) {
    final an = int.tryParse(aa[i]);
    final bn = int.tryParse(bb[i]);
    final result =
        an != null && bn != null ? an.compareTo(bn) : aa[i].compareTo(bb[i]);
    if (result != 0) return result;
  }
  return aa.length.compareTo(bb.length);
}
