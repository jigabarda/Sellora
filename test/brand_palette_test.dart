import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/core/brand_palette.dart';
import 'package:sellora_mobile/core/sellora_ui.dart';

/// WCAG relative-contrast ratio, reimplemented here rather than reaching into
/// the private one under test. A test that borrows the implementation it is
/// checking cannot catch an error in that implementation.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('accent foreground contrast', () {
    // 4.5:1 is WCAG AA for body text. Button labels here are 14.5pt semibold,
    // which qualifies as large text at 3:1, so this is the stricter bar of the
    // two on purpose — the accent also backs the dashboard figure and chips.
    const minimumRatio = 4.5;

    for (final brightness in Brightness.values) {
      for (final palette in BrandPalette.values) {
        test('${palette.name} on ${brightness.name} is readable', () {
          final tokens = (brightness == Brightness.dark
                  ? SelloraTokens.dark
                  : SelloraTokens.light)
              .withPalette(palette, brightness);

          final ratio = contrast(tokens.accent, tokens.onAccent);
          expect(
            ratio,
            greaterThanOrEqualTo(minimumRatio),
            reason: '${palette.name}/${brightness.name}: text on the accent '
                'scores ${ratio.toStringAsFixed(2)}:1, below $minimumRatio:1. '
                'Either the accent needs adjusting or onColor picked wrong.',
          );
        });
      }
    }

    test('picks the better of ink and white, not merely an adequate one', () {
      // The bug this replaced returned white for anything under a luminance
      // threshold, which lost to ink on most midtone accents.
      for (final palette in BrandPalette.values) {
        for (final brightness in Brightness.values) {
          final accent = palette.accentFor(brightness);
          final chosen = SelloraTokens.onColor(accent);
          const ink = Color(0xFF14140F);
          const white = Color(0xFFFFFFFF);
          final other = chosen == white ? ink : white;

          expect(
            contrast(accent, chosen),
            greaterThanOrEqualTo(contrast(accent, other)),
            reason: '${palette.name}/${brightness.name} chose the lower-'
                'contrast foreground of the two available.',
          );
        }
      }
    });
  });

  test('avatar hues avoid the olive band that muddies at low lightness', () {
    for (final hue in avatarHues) {
      expect(
        hue < 45 || hue > 105,
        isTrue,
        reason: 'hue $hue falls in the khaki range',
      );
    }
  });

  test('the same seed always gets the same hue', () {
    // The point of a mnemonic is recognition; a colour that moves between
    // launches is worse than no colour. `hashCode` would break this.
    for (final seed in ['Aling Nena', 'juandc', 'Ice Tube Sack', '']) {
      expect(mnemonicHue(seed), mnemonicHue(seed));
      expect(avatarHues, contains(mnemonicHue(seed)));
    }
    expect(mnemonicHue('  Aling Nena  '), mnemonicHue('aling nena'),
        reason: 'trim and case must not change the colour');
  });

  test('a stored palette name survives a round trip', () {
    for (final palette in BrandPalette.values) {
      expect(BrandPalette.fromName(palette.name), palette);
    }
  });

  test('an unknown or missing stored name falls back rather than throwing', () {
    // Reachable by downgrading the app after picking a palette a later build
    // added, which must not leave the user on a crash loop at launch.
    expect(BrandPalette.fromName('chartreuse'), BrandPalette.fallback);
    expect(BrandPalette.fromName(null), BrandPalette.fallback);
    expect(BrandPalette.fromName(''), BrandPalette.fallback);
  });

  group('mnemonic avatar tones', () {
    // Generated from a hash, so no amount of eyeballing covers them. Sweeping
    // the hue circle exercises every colour the generator can produce, against
    // the real function rather than a restatement of its constants.
    for (final brightness in Brightness.values) {
      test('every hue keeps its initials readable in ${brightness.name}', () {
        // Sweeps the whole circle, not just `avatarHues`, so curating that
        // list stays a purely aesthetic decision — any hue added later is
        // already known to be legible.
        for (var hue = 0; hue < 360; hue++) {
          final tone = mnemonicToneForHue(
            hue.toDouble(),
            isDark: brightness == Brightness.dark,
          );
          final ratio = contrast(tone, SelloraTokens.onColor(tone));
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'hue $hue in ${brightness.name} scores '
                '${ratio.toStringAsFixed(2)}:1. Yellows and cyans peak in '
                'luminance, so lightness has to stay low enough that even '
                'those clear the bar.',
          );
        }
      });
    }
  });
}
