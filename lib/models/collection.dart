import 'wallpaper.dart';

/// Fewest wallpapers a category needs before it is offered as somewhere to
/// go — a card on the browse home, a chip in search, the spotlight, a seat
/// in the carousel. Below this the category still exists (its wallpapers are
/// in every "Browse all" grid and its home row still shows) — it just is
/// not advertised as a destination, because a card that opens onto five
/// wallpapers is worse than no card.
const kMinCollectionSize = 12;

/// A category with its wallpapers in hand: what every collection surface —
/// home row, card, carousel seat, spotlight, search chip, collection page —
/// is built from. Resolved from a [Catalog] once; carried around instead of
/// re-filtering the catalog at each stop.
class Collection {
  final String id;
  final String name;

  /// One line about the collection, from the catalog config. Null when it
  /// has none; the line is then left out — never a count.
  final String? tagline;
  final List<Wallpaper> items;

  Collection({
    required this.id,
    required this.name,
    required this.items,
    this.tagline,
  });

  /// See [kMinCollectionSize].
  bool get isDestination => items.length >= kMinCollectionSize;

  /// The wallpaper that stands for the collection on a card or a cover —
  /// see [Wallpaper.coverOf]. Null only when there are no items.
  late final Wallpaper? cover = Wallpaper.coverOf(items);
}
