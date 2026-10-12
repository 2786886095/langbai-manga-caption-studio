import 'dart:convert';
import 'dart:typed_data';

/// Reads single-face SFNT TTF/OTF metadata without rendering or networking.
/// Imported collections are deliberately rejected: v1 identities are face0.
class SfntFontMetadata {
  SfntFontMetadata._(this.family, this.subfamily, this.postScriptName,
      this.glyphCount, this._bytes, this._cmaps);
  final String family;
  final String subfamily;
  final String postScriptName;
  final int glyphCount;
  final ByteData _bytes;
  final List<({int start, int end, int format})> _cmaps;

  bool hasGlyph(int rune) {
    for (final map in _cmaps) {
      final glyph = _glyph(map, rune);
      if (glyph > 0 && glyph < glyphCount) return true;
    }
    return false;
  }

  List<int> missingCodePoints(String text) => {
        for (final rune in text.runes)
          if (!_isNonPrinting(rune) && !hasGlyph(rune)) rune,
      }.toList(growable: false);

  int _glyph(({int start, int end, int format}) map, int rune) {
    final start = map.start;
    if (map.format == 12) {
      var low = 0;
      var high = _bytes.getUint32(start + 12) - 1;
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        final offset = start + 16 + middle * 12;
        final first = _bytes.getUint32(offset);
        final last = _bytes.getUint32(offset + 4);
        if (rune < first) {
          high = middle - 1;
        } else if (rune > last) {
          low = middle + 1;
        } else {
          return _bytes.getUint32(offset + 8) + rune - first;
        }
      }
    } else if (map.format == 4 && rune <= 0xffff) {
      final count = _bytes.getUint16(start + 6) ~/ 2;
      final ends = start + 14;
      final starts = ends + count * 2 + 2;
      final deltas = starts + count * 2;
      final ranges = deltas + count * 2;
      for (var i = 0; i < count; i++) {
        final first = _bytes.getUint16(starts + i * 2);
        final last = _bytes.getUint16(ends + i * 2);
        if (rune < first || rune > last) continue;
        final delta = _bytes.getInt16(deltas + i * 2);
        final rangeOffset = _bytes.getUint16(ranges + i * 2);
        if (rangeOffset == 0) return (rune + delta) & 0xffff;
        final offset = ranges + i * 2 + rangeOffset + (rune - first) * 2;
        if (offset + 2 > map.end) return 0;
        final glyph = _bytes.getUint16(offset);
        return glyph == 0 ? 0 : (glyph + delta) & 0xffff;
      }
    } else if (map.format == 0 && rune <= 255) {
      return _bytes.getUint8(start + 6 + rune);
    }
    return 0;
  }
}

bool _isNonPrinting(int rune) =>
    rune <= 0x20 ||
    rune == 0x7f ||
    rune == 0x200b ||
    rune == 0x200c ||
    rune == 0x200d ||
    rune == 0xfeff ||
    (rune >= 0xfe00 && rune <= 0xfe0f) ||
    (rune >= 0xe0100 && rune <= 0xe01ef);

SfntFontMetadata inspectFont(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > 64 * 1024 * 1024) {
    throw const FormatException('字体文件为空、过短或超过64MB。');
  }
  final data = ByteData.sublistView(bytes);
  final signature = data.getUint32(0);
  if (signature == 0x74746366) {
    throw const FormatException('暂不支持TTC字体集合，请导入独立TTF/OTF字体。');
  }
  if (signature != 0x00010000 && signature != 0x4f54544f) {
    throw const FormatException('仅支持真正的TTF或OTF字体文件。');
  }
  final count = data.getUint16(4);
  if (count == 0 || 12 + count * 16 > bytes.length) {
    throw const FormatException('字体表目录不完整。');
  }
  final tables = <String, ({int offset, int length})>{};
  for (var i = 0; i < count; i++) {
    final start = 12 + i * 16;
    final tag = latin1.decode(bytes.sublist(start, start + 4));
    final offset = data.getUint32(start + 8);
    final length = data.getUint32(start + 12);
    if (offset > bytes.length || length > bytes.length - offset) {
      throw const FormatException('字体表超出文件边界。');
    }
    tables[tag] = (offset: offset, length: length);
  }
  final name = tables['name'];
  final cmap = tables['cmap'];
  final maxp = tables['maxp'];
  if (name == null ||
      name.length < 6 ||
      cmap == null ||
      cmap.length < 4 ||
      maxp == null ||
      maxp.length < 6 ||
      data.getUint16(maxp.offset + 4) < 1) {
    throw const FormatException('字体缺少有效name、cmap或maxp表。');
  }
  final head = tables['head'];
  final hhea = tables['hhea'];
  final hmtx = tables['hmtx'];
  if (head == null ||
      head.length < 54 ||
      data.getUint32(head.offset + 12) != 0x5f0f3cf5 ||
      hhea == null ||
      hhea.length < 36 ||
      hmtx == null) {
    throw const FormatException('字体缺少有效头部或水平度量表。');
  }
  final glyphCount = data.getUint16(maxp.offset + 4);
  final metricsCount = data.getUint16(hhea.offset + 34);
  if (metricsCount == 0 ||
      metricsCount > glyphCount ||
      hmtx.length < metricsCount * 4 + (glyphCount - metricsCount) * 2) {
    throw const FormatException('字体水平度量数据不完整。');
  }
  if (signature == 0x00010000) {
    final loca = tables['loca'];
    final glyf = tables['glyf'];
    final format = data.getInt16(head.offset + 50);
    if (loca == null ||
        glyf == null ||
        (format != 0 && format != 1) ||
        loca.length < (glyphCount + 1) * (format == 0 ? 2 : 4)) {
      throw const FormatException('TrueType字体轮廓定位数据不完整。');
    }
    var previous = 0;
    for (var i = 0; i <= glyphCount; i++) {
      final offset = format == 0
          ? data.getUint16(loca.offset + i * 2) * 2
          : data.getUint32(loca.offset + i * 4);
      if (offset < previous || offset > glyf.length) {
        throw const FormatException('TrueType字形轮廓越界。');
      }
      previous = offset;
    }
  } else if (!tables.containsKey('CFF ') && !tables.containsKey('CFF2')) {
    throw const FormatException('OpenType字体没有CFF轮廓数据。');
  }
  final names = <int, ({String value, int priority})>{};
  final nameCount = data.getUint16(name.offset + 2);
  final strings = name.offset + data.getUint16(name.offset + 4);
  if (name.offset + 6 + nameCount * 12 > name.offset + name.length) {
    throw const FormatException('字体名称表不完整。');
  }
  for (var i = 0; i < nameCount; i++) {
    final at = name.offset + 6 + i * 12;
    final platform = data.getUint16(at);
    final language = data.getUint16(at + 4);
    final id = data.getUint16(at + 6);
    final length = data.getUint16(at + 8);
    final offset = strings + data.getUint16(at + 10);
    if (offset < name.offset || offset + length > name.offset + name.length) {
      throw const FormatException('字体名称字符串越界。');
    }
    if (!const {1, 2, 6, 16, 17}.contains(id)) continue;
    String value;
    if (platform == 0 || platform == 3) {
      if (length.isOdd) continue;
      value = String.fromCharCodes([
        for (var j = offset; j < offset + length; j += 2) data.getUint16(j),
      ]);
    } else if (platform == 1) {
      value = latin1.decode(bytes.sublist(offset, offset + length));
    } else {
      continue;
    }
    value = value.replaceAll('\u0000', '').trim();
    final priority = (platform == 3 ? 10 : 0) +
        (language == 0x0409
            ? 4
            : language == 0x0804
                ? 3
                : 0);
    if (value.isNotEmpty &&
        (names[id] == null || priority > names[id]!.priority)) {
      names[id] = (value: value, priority: priority);
    }
  }
  final family = names[16]?.value ?? names[1]?.value;
  if (family == null) throw const FormatException('字体没有有效family名称。');
  final cmaps = <({int start, int end, int format})>[];
  final mapCount = data.getUint16(cmap.offset + 2);
  if (4 + mapCount * 8 > cmap.length) {
    throw const FormatException('字体字符映射目录不完整。');
  }
  for (var i = 0; i < mapCount; i++) {
    final at = cmap.offset + 4 + i * 8;
    final platform = data.getUint16(at);
    final encoding = data.getUint16(at + 2);
    if (platform != 0 &&
        !(platform == 3 && (encoding == 1 || encoding == 10))) {
      continue;
    }
    final start = cmap.offset + data.getUint32(at + 4);
    if (start < cmap.offset || start + 6 > cmap.offset + cmap.length) {
      throw const FormatException('字体字符映射越界。');
    }
    final format = data.getUint16(start);
    if (!const {0, 4, 12}.contains(format)) continue;
    if (format == 12 && start + 16 > cmap.offset + cmap.length) {
      throw const FormatException('字体Unicode映射不完整。');
    }
    final length =
        format == 12 ? data.getUint32(start + 4) : data.getUint16(start + 2);
    final end = start + length;
    if (end > cmap.offset + cmap.length || length < 6) {
      throw const FormatException('字体字符映射长度无效。');
    }
    if (format == 0 && length < 262 ||
        format == 4 &&
            (length < 16 ||
                data.getUint16(start + 6).isOdd ||
                16 + data.getUint16(start + 6) * 4 > length) ||
        format == 12 && 16 + data.getUint32(start + 12) * 12 > length) {
      throw const FormatException('字体字符映射数据不完整。');
    }
    cmaps.add((start: start, end: end, format: format));
  }
  if (cmaps.isEmpty) throw const FormatException('字体没有可读取的Unicode字符映射。');
  return SfntFontMetadata._(family, names[17]?.value ?? names[2]?.value ?? '',
      names[6]?.value ?? '', data.getUint16(maxp.offset + 4), data, cmaps);
}
