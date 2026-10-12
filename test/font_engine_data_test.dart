import 'dart:typed_data';

import 'package:bubble_caption_studio/src/font_engine_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine byte boundary owns a native writable copy, not public storage', () {
    final raw = Uint8List.fromList([0, 1, 2, 3]);
    final immutable = raw.asUnmodifiableView();
    final data = fontDataForEngine(immutable);
    final engineBytes =
        Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    expect(engineBytes, immutable);
    engineBytes[0] = 9;
    expect(immutable[0], 0);
    expect(() => immutable[0] = 9, throwsUnsupportedError);
  });
}
