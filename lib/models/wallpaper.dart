/// Wallpaper kind: a regular image or a live (video) wallpaper.
enum WallpaperType {
  image,
  live;

  static WallpaperType fromString(String? value) =>
      value == 'live' ? WallpaperType.live : WallpaperType.image;
}

/// A catalog category (used by the filter UI).
class WallpaperCategory {
  final String id;
  final String name;

  const WallpaperCategory({required this.id, required this.name});

  factory WallpaperCategory.fromJson(Map<String, dynamic> json) =>
      WallpaperCategory(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['id'] ?? '').toString(),
      );
}

/// Data model describing a single wallpaper.
///
/// Note: the gallery uses [thumbUrl] (small size) to save memory, while the
/// preview/apply flow loads [fullUrl] (full size, up to 4K).
class Wallpaper {
  final String id;
  final String title;

  /// Small image for the gallery grid (less traffic, less memory).
  final String thumbUrl;

  /// Full-size image for preview and applying the wallpaper (up to 4K).
  final String fullUrl;

  /// Video URL for live wallpapers. `null` for regular images.
  final String? videoUrl;

  final WallpaperType type;

  /// Resolution label for display, e.g. "4K", "FHD".
  final String resolution;

  /// Category id (used for filtering), e.g. "nature", "live".
  final String category;

  /// Search tags (optional).
  final List<String> tags;

  const Wallpaper({
    required this.id,
    required this.title,
    required this.thumbUrl,
    required this.fullUrl,
    required this.type,
    required this.resolution,
    required this.category,
    this.videoUrl,
    this.tags = const [],
  });

  bool get isLive => type == WallpaperType.live;

  /// Whether this is a 4K wallpaper (gated behind a rewarded ad to unlock).
  bool get is4k => resolution == '4K';

  /// Builds a model from catalog JSON.
  ///
  /// URLs can be provided in two ways:
  ///  1. Directly via `thumb`/`full`/`video` (full URLs) — used as-is when present.
  ///  2. Via `key` only (e.g. "nature/001") — then they are built from [base]
  ///     (the CDN URL) as `{base}/{key}_thumb.webp`, `{base}/{key}_full.webp`,
  ///     `{base}/{key}.mp4`.
  factory Wallpaper.fromJson(Map<String, dynamic> json, {required String base}) {
    final key = (json['key'] ?? json['id'] ?? '').toString();
    final type = WallpaperType.fromString(json['type']?.toString());

    String? str(String k) {
      final v = json[k];
      return (v == null || v.toString().isEmpty) ? null : v.toString();
    }

    final thumb = str('thumb') ?? '$base/${key}_thumb.webp';
    final full = str('full') ?? '$base/${key}_full.webp';
    final video = type == WallpaperType.live
        ? (str('video') ?? '$base/$key.mp4')
        : null;

    return Wallpaper(
      id: key,
      title: (json['title'] ?? key).toString(),
      thumbUrl: thumb,
      fullUrl: full,
      videoUrl: video,
      type: type,
      resolution: (json['resolution'] ?? 'HD').toString(),
      category: (json['category'] ?? '').toString(),
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
