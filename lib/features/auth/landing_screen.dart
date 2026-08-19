import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';

/// The logged-out welcome screen.
///
/// This used to be the web marketing page ported wholesale — a long scrolling
/// column of hero, feature grid, steps, CTA band and footer. That shape exists
/// on the web because a visitor arrives cold from a search result and has to
/// be convinced. Someone who has already installed the app is past that, and
/// scrolling a sales pitch to reach a sign-up button is friction, not
/// persuasion.
///
/// So it is a swipeable intro instead: one idea per screen, the primary action
/// always visible at the bottom, and no scrolling required to act.
///
/// Each slide shows a **fragment of the real interface** rather than an icon in
/// a tinted circle. A stock glyph on a pale disc is what every onboarding
/// screen looks like, and it tells someone deciding whether to install nothing
/// at all. A card that looks exactly like the one they will tap in a minute
/// both answers the question and cannot quietly go out of date the way a
/// drawing can, because it is built from the same tokens as the app itself.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _controller = PageController();

  /// Drives the dots and the artwork. Kept as a double rather than an int so
  /// the illustration can track a drag in progress, not just settled pages.
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final page = _controller.page;
      if (page != null && page != _page) setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slidesFor(context.t);

    return Scaffold(
      body: Stack(
        children: [
          // A wash of the slide's own colour behind everything, so the whole
          // screen shifts as you swipe instead of only the picture in it.
          Positioned.fill(
            child: _Backdrop(
              tone: slides[_page.round().clamp(0, slides.length - 1)].tone,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.md, 0),
                  child: Row(
                    children: [
                      const SelloraLockup(size: 21),
                      const Spacer(),
                      TextButton(
                        onPressed: () => context.push('/login'),
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (_) => HapticFeedback.selectionClick(),
                    itemBuilder: (context, index) => _Slide(
                      slide: slides[index],
                      // How far this page sits from the viewport centre, so the
                      // artwork settles into place as it arrives rather than
                      // sliding rigidly with the page.
                      offset: index - _page,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.lg),
                  child: Column(
                    children: [
                      _Dots(count: slides.length, page: _page),
                      Gap.h24,
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.push('/register'),
                          child: const Text('Create free account'),
                        ),
                      ),
                      Gap.h8,
                      Text(
                        'No sign-up fees. Works without internet.',
                        style: context.text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft field of the active slide's colour, top-heavy so it sits behind the
/// artwork and fades out before it reaches the text.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              tone.withValues(alpha: context.isDark ? 0.22 : 0.13),
              t.canvas,
            ),
            t.canvas,
          ],
          stops: const [0, 0.62],
        ),
      ),
    );
  }
}

/// Content for one intro screen.
///
/// Built per frame rather than held as a `const` list because every tone comes
/// from the active theme, which a const cannot reach.
class _SlideData {
  const _SlideData({
    required this.tone,
    required this.title,
    required this.body,
    required this.artwork,
  });

  final Color tone;
  final String title;
  final String body;

  /// The piece of real interface this slide is about.
  final Widget artwork;
}

List<_SlideData> _slidesFor(SelloraTokens t) => [
      _SlideData(
        tone: t.accent,
        title: 'Ring up a sale\nin seconds',
        body: 'Tap the products, confirm, done. Totals and change are worked '
            'out for you.',
        artwork: const _SaleArtwork(),
      ),
      _SlideData(
        tone: t.warning,
        title: 'Never run out\nwithout knowing',
        body: 'Stock drops as you sell, and low items surface on your '
            'dashboard before they run dry.',
        artwork: const _StockArtwork(),
      ),
      _SlideData(
        tone: t.success,
        title: 'See the profit,\nnot just the sales',
        body: 'Log expenses alongside takings and know what the business '
            'actually earned this week.',
        artwork: const _ProfitArtwork(),
      ),
      _SlideData(
        // Bookends the sequence on the brand colour. Ink read as a dead grey
        // panel next to the three coloured slides before it.
        tone: t.accent,
        title: 'Yours, and\noffline for good',
        body: 'Everything lives on this phone. No account to lose, no signal '
            'required, nothing uploaded anywhere.',
        artwork: const _OfflineArtwork(),
      ),
    ];

class _Slide extends StatelessWidget {
  const _Slide({required this.slide, required this.offset});

  final _SlideData slide;
  final double offset;

  @override
  Widget build(BuildContext context) {
    // Clamped so a fast fling cannot drive the artwork to nothing; it should
    // recede, not vanish.
    final distance = math.min(offset.abs(), 1.0);
    final settle = 1 - distance;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Column(
        children: [
          // Expanded, not Flexible-and-centre: the artwork should take all the
          // room left over and let the words sit directly beneath it. Centring
          // the pair left a band of dead space between the paragraph and the
          // dots, which read as a layout that had run out of things to say.
          Expanded(
            // Bottom-aligned rather than centred: the artwork belongs directly
            // above the words it illustrates, and any space the screen has to
            // spare should collect under the header instead of wedging itself
            // between the picture and the headline.
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Opacity(
              opacity: 0.30 + 0.70 * settle,
                child: Transform.translate(
                  // Cards drift in from the side a little slower than the
                  // page, which reads as depth rather than as a slideshow.
                  offset: Offset(offset * 26, 0),
                  child: Transform.scale(
                    scale: 0.90 + 0.10 * settle,
                    child: slide.artwork,
                  ),
                ),
              ),
            ),
          ),
          Gap.h24,
          // Left-aligned deliberately. Centred paragraphs are harder to read,
          // and a ragged left edge is a lot of what makes a screen feel like a
          // marketing page rather than an app.
          Align(
            alignment: Alignment.centerLeft,
            child: Text(slide.title, style: context.text.displaySmall),
          ),
          Gap.h12,
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              slide.body,
              style: context.text.bodyLarge?.copyWith(
                color: context.t.muted,
                height: 1.5,
              ),
            ),
          ),
          Gap.h8,
        ],
      ),
    );
  }
}

/// Every artwork is composed at this size and then scaled to whatever the
/// screen can spare.
///
/// Laying the cards out against fixed pixels and shrinking the result keeps the
/// proportions identical on every device, and — the practical half — makes it
/// impossible for a short screen to overflow the illustration.
const _boardWidth = 300.0;
const _boardHeight = 232.0;

class _Artboard extends StatelessWidget {
  const _Artboard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: _boardWidth,
        height: _boardHeight,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

/// A card in the app's own clothes, lifted off the background.
///
/// Not [SelloraCard]: this one carries a real shadow, because two of these
/// overlapping is the whole trick, and a flat border alone would collapse them
/// into one shape.
class _MockCard extends StatelessWidget {
  const _MockCard({
    required this.child,
    this.padding = const EdgeInsets.all(Gap.md),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: t.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.40 : 0.10),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// One product line: tile, name, and the money on the right.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.icon,
    required this.tone,
    required this.name,
    required this.detail,
    required this.amount,
  });

  final IconData icon;
  final Color tone;
  final String name;
  final String detail;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        IconTile(icon: icon, tone: tone, size: 30),
        Gap.w12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(detail, style: context.text.bodySmall),
            ],
          ),
        ),
        Gap.w8,
        Text(
          amount,
          style: context.text.bodyMedium
              ?.copyWith(color: t.ink, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Slide one: a basket being rung up, and the total that follows from it.
class _SaleArtwork extends StatelessWidget {
  const _SaleArtwork();

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return _Artboard(
      children: [
        Positioned(
          left: 0,
          right: 22,
          top: 0,
          child: _MockCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LineRow(
                  icon: Icons.water_drop_outlined,
                  tone: t.accent,
                  name: 'Purified 5-Gallon Refill',
                  detail: '2 × ₱25.00',
                  amount: formatPhp(50),
                ),
                Gap.h12,
                _LineRow(
                  icon: Icons.ac_unit_outlined,
                  tone: t.accent,
                  name: 'Crushed Ice Bag',
                  detail: '4 × ₱60.00',
                  amount: formatPhp(240),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 40,
          right: 0,
          bottom: 0,
          child: _MockCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('Total', style: context.text.bodyMedium),
                    const Spacer(),
                    Text(
                      formatPhp(290),
                      style: context.text.titleLarge?.copyWith(color: t.ink),
                    ),
                  ],
                ),
                Gap.h12,
                _FakeButton(label: 'Record sale', tone: t.accent),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Slide two: the shelf running down, and the warning that arrives first.
class _StockArtwork extends StatelessWidget {
  const _StockArtwork();

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return _Artboard(
      children: [
        Positioned(
          left: 0,
          right: 18,
          top: 0,
          child: _MockCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _LineRow(
                        icon: Icons.ac_unit_outlined,
                        tone: t.warning,
                        name: 'Crushed Ice Bag',
                        detail: '2 left',
                        amount: '',
                      ),
                    ),
                    const SelloraPill(label: 'Low', tone: PillTone.warning),
                  ],
                ),
                Gap.h12,
                _LineRow(
                  icon: Icons.water_drop_outlined,
                  tone: t.accent,
                  name: 'Purified 5-Gallon Refill',
                  detail: '48 left',
                  amount: '',
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 46,
          right: 0,
          bottom: 0,
          child: _MockCard(
            child: Row(
              children: [
                IconTile(
                    icon: Icons.trending_down, tone: t.danger, size: 30),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Runs out tomorrow',
                        style: context.text.bodyMedium?.copyWith(
                          color: t.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('Selling about 1.4 a day',
                          style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Slide three: takings, what they cost, and what is actually left.
class _ProfitArtwork extends StatelessWidget {
  const _ProfitArtwork();

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return _Artboard(
      children: [
        Positioned(
          left: 0,
          right: 20,
          top: 0,
          child: _MockCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('This week', style: context.text.labelSmall),
                Gap.h4,
                Text(
                  formatPhp(2065),
                  style: context.text.displaySmall?.copyWith(color: t.ink),
                ),
                Gap.h12,
                const _MiniBars(
                  // A real week: two quiet days, a market day, a Sunday off.
                  values: [0.32, 0.48, 0.40, 1.0, 0.22, 0.64, 0.10],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 44,
          right: 0,
          bottom: 0,
          child: _MockCard(
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md, vertical: Gap.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Expenses', style: context.text.bodySmall),
                      Text(
                        formatPhp(780),
                        style: context.text.bodyLarge?.copyWith(
                          color: t.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 34, color: t.line),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Profit', style: context.text.bodySmall),
                      Text(
                        formatPhp(1285),
                        style: context.text.bodyLarge?.copyWith(
                          color: t.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Slide four: the claim about privacy, made concrete.
class _OfflineArtwork extends StatelessWidget {
  const _OfflineArtwork();

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    Widget row(IconData icon, String label, Color tone) => Row(
          children: [
            IconTile(icon: icon, tone: tone, size: 30),
            Gap.w12,
            Expanded(
              child: Text(
                label,
                style: context.text.bodyMedium?.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.check_circle, size: 18, color: t.success),
          ],
        );

    return _Artboard(
      children: [
        Positioned(
          left: 0,
          right: 16,
          top: 0,
          child: _MockCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row(Icons.cloud_off_outlined, 'No internet needed', t.accent),
                Gap.h12,
                row(Icons.lock_outline, 'Nothing uploaded', t.accent),
                Gap.h12,
                row(Icons.phone_android_outlined, 'Stays on this phone',
                    t.accent),
              ],
            ),
          ),
        ),
        Positioned(
          left: 52,
          right: 0,
          bottom: 0,
          child: _MockCard(
            child: Row(
              children: [
                IconTile(
                    icon: Icons.shield_outlined, tone: t.success, size: 30),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Permissions asked for',
                        style: context.text.bodySmall,
                      ),
                      Text(
                        'None',
                        style: context.text.bodyLarge?.copyWith(
                          color: t.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The shape of a filled button without the behaviour. Deliberately inert —
/// this is a picture of the app, and a tappable-looking control that does
/// nothing is worse than one that plainly does not invite the tap.
class _FakeButton extends StatelessWidget {
  const _FakeButton({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: context.text.labelMedium?.copyWith(color: context.t.onAccent),
      ),
    );
  }
}

/// A week of takings, tall enough to read the shape and no taller.
class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: Container(
                height: math.max(4, 34 * values[i]),
                decoration: BoxDecoration(
                  color: values[i] >= 0.99
                      ? t.accent
                      : Color.alphaBlend(
                          t.accent.withValues(alpha: 0.45), t.surface),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page indicator.
///
/// The active dot stretches into a bar rather than only changing colour, so
/// position stays readable whatever accent the user picked — including one
/// with little contrast against the line colour.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page});

  final int count;
  final double page;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final active = page.round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: i == active ? 22 : 6,
            decoration: BoxDecoration(
              color: i == active ? t.accent : t.lineStrong,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
      ],
    );
  }
}
