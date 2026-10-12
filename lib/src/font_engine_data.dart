import 'dart:typed_data';

/// Flutter's Web font engine requires a native ArrayBuffer/Uint8Array.
/// Public font assets intentionally expose immutable Dart views; those wrappers
/// cannot be passed through Dart 3.5 JS typed-data interop. Own a mutable native
/// copy only at the engine boundary, never expose it as a public asset.
ByteData fontDataForEngine(Uint8List bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes));
