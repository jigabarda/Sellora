import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.md, 0),
              child: Row(
                children: [
                  const SelloraWordmark(size: 22),
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
    );
  }
}

/// Content for one intro screen.
///
/// Built per frame rather than held as a `const` list because every tone comes
/// from the active theme, which a const cannot reach.
class _SlideData {
  const _SlideData({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.chips,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  /// Small labels floated around the artwork, carrying the concrete detail the
  /// headline has to leave out.
  final List<String> chips;
}

List<_SlideData> _slidesFor(SelloraTokens t) => [
      _SlideData(
        icon: Icons.point_of_sale_outlined,
        tone: t.accent,
        title: 'Ring up a sale\nin seconds',
        body: 'Tap the products, confirm, done. Totals and change are worked '
            'out for you.',
        chips: const ['Fast checkout', 'Auto totals'],
      ),
      _SlideData(
        icon: Icons.inventory_2_outlined,
        tone: t.warning,
        title: 'Never run out\nwithout knowing',
        body: 'Stock drops as you sell, and low items surface on your '
            'dashboard before they run dry.',
        chips: const ['Live stock', 'Low alerts'],
      ),
      _SlideData(
        icon: Icons.insights_outlined,
        tone: t.success,
        title: 'See the profit,\nnot just the sales',
        body: 'Log expenses alongside takings and know what the business '
            'actually earned this week.',
        chips: const ['Daily totals', 'Top products'],
      ),
      _SlideData(
        icon: Icons.cloud_off_outlined,
        // Bookends the sequence on the brand colour. Ink read as a dead grey
        // disc next to the three coloured slides before it.
        tone: t.accent,
        title: 'Yours, and\noffline for good',
        body: 'Everything lives on this phone. No account to lose, no signal '
            'required, nothing uploaded anywhere.',
        chips: const ['No internet', 'Private by default'],
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Opacity(
              opacity: 0.35 + 0.65 * settle,
              child: Transform.scale(
                scale: 0.88 + 0.12 * settle,
                child: _Artwork(slide: slide),
              ),
            ),
          ),
          Gap.h32,
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
        ],
      ),
    );
  }
}

/// The illustration for a slide: a tinted disc, the feature's icon, and two
/// labels tucked against the edges.
///
/// Drawn rather than shipped as an image so it recolours with the brand
/// palette, works in both themes, and adds nothing to the APK.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.slide});

  final _SlideData slide;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized from the space actually available: a fixed diameter overflows
        // on a short screen and strands itself in the middle of a tall one.
        final size = math.min(constraints.maxHeight, constraints.maxWidth);
        final disc = size * 0.78;

        return SizedBox(
          height: size,
          width: constraints.maxWidth,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    slide.tone.withValues(alpha: context.isDark ? 0.20 : 0.10),
                    t.canvas,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(slide.icon, size: disc * 0.34, color: slide.tone),
              Align(
                alignment: Alignment.topLeft,
                child: _Chip(label: slide.chips.first),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: _Chip(label: slide.chips[1]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: t.line),
      ),
      child: Text(
        label,
        style: context.text.labelMedium?.copyWith(color: t.ink),
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
