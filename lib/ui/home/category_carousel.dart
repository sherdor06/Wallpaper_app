import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/collection.dart';
import '../widgets/wallpaper_thumb.dart';

/// Card size when focused; neighbours are drawn at [_sideScale] of it.
const _cardWidth = 164.0;
const _cardHeight = 92.0;
const _sideScale = 0.86;

/// How far the focused card reaches into each neighbour's page.
const _overlap = 14.0;

/// Lets the focused card's ticker hold the carousel: the strip does not
/// move on until a long tagline has rolled round once and come back to its
/// start. A card whose line fits never holds it.
class _TickerGate extends ChangeNotifier {
  bool _held = false;
  bool get held => _held;

  void hold() {
    if (_held) return;
    _held = true;
    notifyListeners();
  }

  void release() {
    if (!_held) return;
    _held = false;
    notifyListeners();
  }
}

/// A quick way into a handful of collections, sitting under the hero.
///
/// Cards scroll sideways and snap so one is always centred — that one is
/// full size, its neighbours shrink and dim — and the strip advances by
/// itself every few seconds until the user touches it. Any card opens its
/// collection; the dots say where in the line-up the focus is.
///
/// Loops: the page list is treated as endless and indexed modulo the
/// collection count, so the auto-advance never has to rewind across seven
/// cards to get back to the first.
class CategoryCarousel extends StatefulWidget {
  final List<Collection> collections;
  final void Function(Collection) onOpen;

  const CategoryCarousel({
    super.key,
    required this.collections,
    required this.onOpen,
  });

  @override
  State<CategoryCarousel> createState() => _CategoryCarouselState();
}

class _CategoryCarouselState extends State<CategoryCarousel> {
  /// How long a card holds the centre before the strip moves on, and how
  /// long a touch keeps it still afterwards. Long enough to read a card,
  /// short enough that the strip is visibly alive.
  static const _advanceEvery = Duration(milliseconds: 4000);
  static const _idleAfterTouch = Duration(seconds: 6);
  static const _slide = Duration(milliseconds: 800);

  /// Far enough from zero that swiping backwards never hits the start.
  static const _origin = 1000;

  late final PageController _controller;
  final _gate = _TickerGate();
  Timer? _timer;
  int _page = _origin;

  /// True once the dwell timer has fired but the ticker was still holding.
  bool _dwellOver = false;

  int get _count => widget.collections.length;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: _origin,
      // A page is a little narrower than a card, so the focused card leans
      // into its neighbours' pages and the gap to them closes. Safe because
      // a neighbour is drawn at [_sideScale], inset from its page edge by
      // more than the overhang, so nothing is ever painted over.
      viewportFraction: (_cardWidth - _overlap) / 390,
    );
    _controller.addListener(_onScroll);
    _gate.addListener(_onGate);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Not disposed: the cards release it from their own dispose, which
    // runs after this one, and a disposed notifier asserts on that.
    _gate.removeListener(_onGate);
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// Fires when the ticker lets go: if the dwell had already run out while
  /// it held, move on now.
  void _onGate() {
    if (!_gate.held && _dwellOver) {
      _dwellOver = false;
      _advance();
    }
  }

  void _onScroll() {
    final p = _controller.page?.round();
    if (p != null && p != _page) setState(() => _page = p);
  }

  void _start([Duration delay = _advanceEvery]) {
    _timer?.cancel();
    _timer = Timer(delay, _advance);
  }

  void _advance() {
    // A page under a hidden tab has no ticker: the animation would never
    // finish and the strip would be stuck on the next visit. Try again later.
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        !_controller.hasClients) {
      _start();
      return;
    }
    // The tagline is still rolling round: wait for it (see _onGate).
    if (_gate.held) {
      _dwellOver = true;
      return;
    }
    // Ease in and out: the card drifts off and the next settles, rather
    // than the snap a finger-flick gets.
    _controller
        .nextPage(duration: _slide, curve: Curves.easeInOutCubic)
        .whenComplete(_start);
  }

  /// A touch pauses the strip so it never yanks a card out from under a
  /// finger; it resumes once the user has clearly moved on.
  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _timer?.cancel();
    } else if (n is ScrollEndNotification) {
      _start(_idleAfterTouch);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: _cardHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onNotification,
            child: PageView.builder(
              controller: _controller,
              // Endless: see the class note.
              itemBuilder: (context, i) => _Card(
                collection: widget.collections[i % _count],
                index: i,
                controller: _controller,
                gate: _gate,
                onTap: () => widget.onOpen(widget.collections[i % _count]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Dots(count: _count, current: _page % _count),
      ],
    );
  }
}

/// One card. Its size and dimming follow how far it is from the centre,
/// read straight off the controller so they move with the finger.
class _Card extends StatelessWidget {
  final Collection collection;
  final int index;
  final PageController controller;
  final _TickerGate gate;
  final VoidCallback onTap;

  const _Card({
    required this.collection,
    required this.index,
    required this.controller,
    required this.gate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tagline = collection.tagline;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Distance from the centre in pages: 0 focused, 1 a neighbour.
        final page =
            controller.hasClients && controller.position.hasContentDimensions
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final d = (page - index).abs().clamp(0.0, 1.0);
        final scale = 1 - d * (1 - _sideScale);
        // The card is always laid out at full size and *drawn* smaller for
        // a neighbour. Laying neighbours out smaller re-wrapped the text at
        // the narrower width, so a line changed as a card moved between
        // focus and the side. Dimming is a wash of the page colour rather
        // than Opacity, so nothing is rasterised and resampled.
        final wash = Theme.of(context).scaffoldBackgroundColor;
        return Center(
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: _cardWidth,
              height: _cardHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: wash.withValues(alpha: d * 0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      // No accent ring here: every card looks the same, the way the rest
      // of the row does. The accented collections show their colour in
      // their own row and on their page.
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              WallpaperThumb(wallpaper: collection.cover, memCacheWidth: 400),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.3, 1],
                    colors: [Color(0x000E0E12), Color(0xD90E0E12)],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (tagline != null)
                      _Marquee(
                        text: tagline,
                        controller: controller,
                        index: index,
                        gate: gate,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tagline. Fits: plain text. Too long for the card: on the focused
/// card it holds a moment, then rolls left like a ticker — the start of the
/// line following the end round again — for as long as the card is looked
/// at. Off focus it sits still, showing its beginning. The clip is a plain
/// cut, no fade: the words stay legible right up to the edge.
class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final PageController controller;
  final int index;
  final _TickerGate gate;

  const _Marquee({
    required this.text,
    required this.style,
    required this.controller,
    required this.index,
    required this.gate,
  });

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  /// Pause before the roll starts, so the start is read before it moves.
  static const _hold = Duration(milliseconds: 650);
  static const _speed = 30.0; // px per second

  /// Space between the end of the line and its next beginning.
  static const _gap = 36.0;

  // Created in initState, not lazily: a lazy controller first touched from
  // dispose() (a line that never overflowed) would be created against a
  // deactivated element and assert.
  late final AnimationController _anim;
  double _textWidth = 0;
  bool _overflows = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    // The first card is in focus before the controller has ever scrolled,
    // so _onPage would never tell it; read the initial page directly.
    _focused = widget.index == widget.controller.initialPage;
    widget.controller.addListener(_onPage);
  }

  void _onPage() {
    final c = widget.controller;
    if (!c.hasClients || !c.position.hasContentDimensions) return;
    final page = c.page ?? c.initialPage.toDouble();
    final focused = (page - widget.index).abs() < 0.5;
    if (focused == _focused) return;
    _focused = focused;
    if (focused) {
      _run();
    } else {
      // Off focus: straight back to the start. The card is mid-slide at
      // this moment, so the jump hides in the motion; a visible rewind
      // read as the line running backwards.
      _anim.stop();
      _anim.value = 0;
      widget.gate.release();
    }
  }

  @override
  void dispose() {
    widget.gate.release();
    widget.controller.removeListener(_onPage);
    _anim.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (!_overflows) return;
    // Hold the carousel until the line has rolled round once.
    widget.gate.hold();
    _anim.value = 0;
    await Future<void>.delayed(_hold);
    if (!mounted || !_focused) return;
    // One period moves the line by its own width plus the gap, which is
    // exactly when the copy behind it has taken its place — so the loop
    // is seamless.
    final period = Duration(
      milliseconds: ((_textWidth + _gap) / _speed * 1000).round(),
    );
    try {
      await _anim.animateTo(1, duration: period, curve: Curves.linear);
    } on TickerCanceled {
      return;
    }
    if (!mounted || !_focused) return;
    // Back at the start: the carousel may move on; keep rolling meanwhile.
    _anim.value = 0;
    widget.gate.release();
    _anim.repeat(period: period);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        _textWidth = painter.width;
        _overflows = painter.width > constraints.maxWidth;
        if (!_overflows) {
          return Text(widget.text, maxLines: 1, style: widget.style);
        }
        // Kick off if the card is already in focus when the line first lays
        // out (the first card on a cold open).
        if (_focused && !_anim.isAnimating) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _run());
        }
        final lineHeight = painter.height;
        final line = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );
        return SizedBox(
          height: lineHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, child) => Transform.translate(
                offset: Offset(-(_textWidth + _gap) * _anim.value, 0),
                child: child,
              ),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                // Unbounded: the row takes its own width, so a pixel of
                // difference between the painter's measure and the real
                // layout can never overflow it.
                maxWidth: double.infinity,
                maxHeight: lineHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    line,
                    const SizedBox(width: _gap),
                    line,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;
  const _Dots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: i == current ? 10 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: on.withValues(alpha: i == current ? 0.9 : 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
