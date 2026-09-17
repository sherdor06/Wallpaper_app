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

  /// One line about the collection ("Pink, bows and soft things"), written
  /// in the catalog config so it can change without an app update. Null on
  /// older catalogs; callers then leave the line out — a count is never
  /// shown in its place.
  final String? tagline;

  const WallpaperCategory({required this.id, required this.name, this.tagline});

  factory WallpaperCategory.fromJson(Map<String, dynamic> json) =>
      WallpaperCategory(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['id'] ?? '').toString(),
        tagline: (json['tagline'] as String?)?.trim().isNotEmpty == true
            ? (json['tagline'] as String).trim()
            : null,
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

  /// Tone tags the catalog generator reads off the image's colours — values
  /// from [kMoodOrder]. What a collection page filters by ("Light", "Dark")
  /// when its items carry them; empty on catalogs generated before this
  /// existed, in which case the page simply shows no chips.
  final List<String> moods;

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
    this.moods = const [],
  });

  bool get isLive => type == WallpaperType.live;

  /// True when the catalog generator invented this title — "Cars 41",
  /// "Space 12" — because the source file had no words in its name.
  ///
  /// Beyond reading weakly, an auto-title is a signal about provenance: those
  /// files were tagged by position in a feed rather than by name, and are the
  /// ones most often filed under the wrong category. Anything that has to
  /// pick a single wallpaper to *represent* a set — a hero, a cover — should
  /// prefer the titled ones.
  bool get isAutoTitled {
    final cat = category.replaceAll(RegExp(r'[_\-]+'), ' ');
    if (RegExp(
      '^${RegExp.escape(cat)} \\d+\$',
      caseSensitive: false,
    ).hasMatch(title)) {
      return true;
    }
    // A filename like `img_4471` survives the generator's word filter as the
    // title "Img" — technically a word, but no more a title than a number.
    return _junkTitles.contains(title.trim().toLowerCase());
  }

  static const _junkTitles = {
    'img',
    'image',
    'images',
    'photo',
    'pic',
    'picture',
    'wallpaper',
    'wallpapers',
    'background',
    'file',
    'untitled',
    'screenshot',
  };

  /// The wallpaper that best stands for [items]: the first with a real title,
  /// or simply the first when none has one. Deterministic, so a cover does
  /// not change between opens.
  static Wallpaper? coverOf(List<Wallpaper> items) {
    if (items.isEmpty) return null;
    for (final w in items) {
      if (!w.isAutoTitled) return w;
    }
    return items.first;
  }

  /// Whether this is a 4K wallpaper (gated behind a rewarded ad to unlock).
  bool get is4k => resolution == '4K';

  /// Whether this is a Full-HD wallpaper. Like [is4k] it can be gated behind a
  /// rewarded ad — the label stays honest, only the gate widens.
  bool get isFhd => resolution == 'FHD';

  /// Builds a model from catalog JSON.
  ///
  /// URLs can be provided in two ways:
  ///  1. Directly via `thumb`/`full`/`video` (full URLs) — used as-is when present.
  ///  2. Via `key` only (e.g. "nature/001") — then they are built from [base]
  ///     (the CDN URL) as `{base}/{key}_thumb.webp`, `{base}/{key}_full.webp`,
  ///     `{base}/{key}.mp4`.
  factory Wallpaper.fromJson(
    Map<String, dynamic> json, {
    required String base,
  }) {
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
      tags:
          (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      moods:
          (json['moods'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

/// Every mood the generator can assign, in the order chips are shown. Kept in
/// step with `moods_for` in scripts/generate_catalog.py.
const kMoodOrder = ['light', 'dark', 'vivid', 'mono'];

/// "nature" → "Nature": the display name for a category id the catalog has
/// no entry for.
String categoryLabel(String id) =>
    id.isEmpty ? id : id[0].toUpperCase() + id.substring(1);

/// Display label for a mood id.
String moodLabel(String mood) => switch (mood) {
  'light' => 'Light',
  'dark' => 'Dark',
  'vivid' => 'Vivid',
  'mono' => 'Mono',
  _ => mood.isEmpty ? mood : mood[0].toUpperCase() + mood.substring(1),
};
