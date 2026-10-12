import 'dart:typed_data';

import 'sticker_library_io.dart'
    if (dart.library.js_interop) 'sticker_library_web.dart' as implementation;

class StickerAsset {
  const StickerAsset({
    required this.id,
    required this.name,
    required this.category,
    required this.bytes,
    required this.createdAt,
    this.favorite = false,
    this.lastUsedAt,
  });

  final String id;
  final String name;
  final String category;
  final Uint8List bytes;
  final DateTime createdAt;
  final bool favorite;
  final DateTime? lastUsedAt;

  StickerAsset copyWith({
    String? name,
    String? category,
    bool? favorite,
    DateTime? lastUsedAt,
  }) =>
      StickerAsset(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        bytes: bytes,
        createdAt: createdAt,
        favorite: favorite ?? this.favorite,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, Object?> toJson({bool includeBytes = true}) => {
        'id': id,
        'name': name,
        'category': category,
        'favorite': favorite,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastUsedAt != null)
          'lastUsedAt': lastUsedAt!.toUtc().toIso8601String(),
        if (includeBytes) 'bytes': implementation.encodeStickerBytes(bytes),
      };

  static StickerAsset fromJson(Map<String, dynamic> json) => StickerAsset(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '表情包',
        category: json['category']?.toString() ?? '未分类',
        bytes: implementation.decodeStickerBytes(json['bytes']?.toString()),
        favorite: json['favorite'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
      );
}

Future<List<StickerAsset>> loadStickerLibrary() =>
    implementation.loadStickerLibrary();

Future<void> saveStickerLibrary(List<StickerAsset> assets) =>
    implementation.saveStickerLibrary(assets);
