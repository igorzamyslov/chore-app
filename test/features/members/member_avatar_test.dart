/// The member avatar is a ring, not a fill (G-4, design canvas frame 1b):
/// two-letter initials on the neutral surface inside a ring in the member's
/// theme-rendered colour, legible from the 32px chore tile to the 66px
/// edit-sheet preview, and at text scale 2.0.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  required String name,
  required int color,
  double radius = 16,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: MemberAvatar(
              member: previewMember(name: name, color: color),
              radius: radius,
            ),
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(MemberAvatar),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

/// Whether [value] contains a lone surrogate -- a high surrogate not
/// followed by a low one, or a low surrogate not preceded by a high one.
///
/// This is the tofu `memberInitials` exists to prevent: `substring(0, 2)`
/// indexes UTF-16 code units, so it can cut a non-BMP character in half and
/// leave exactly this. Checked by scanning code units directly, because a
/// lone surrogate survives a `runes` round trip unchanged and so would slip
/// past the obvious version of this check.
bool _hasLoneSurrogate(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;
    if (isHigh) {
      final next = i + 1 < units.length ? units[i + 1] : 0;
      if (next < 0xDC00 || next > 0xDFFF) {
        return true;
      }
      i++;
    } else if (isLow) {
      return true;
    }
  }
  return false;
}

void main() {
  // NOTE ON FONTS, measured in CI rather than assumed -- it decides what
  // this file can honestly assert.
  //
  // Widget tests here draw the Ahem-style `FlutterTest` font, not the
  // bundled Inter: there is no `flutter_test_config.dart` anywhere in the
  // repo and nothing calls `FontLoader`. Measured: 'WM' at 11px/w600 comes
  // back **21.87px**, i.e. 1.99 em per glyph -- the SDK's "square whose size
  // equals the font size". The same 21.87 is returned whether the family is
  // inherited from the theme or set explicitly to 'Inter', and adding a
  // `FontLoader('Inter')` over the bundled TTFs in `setUpAll` did NOT change
  // it (the fonts are declared under pubspec `fonts:` rather than `assets:`,
  // so `rootBundle.load` gives the loader nothing usable and it silently
  // no-ops).
  //
  // Consequence, stated plainly rather than papered over: **whether two
  // glyphs physically fit inside the ring cannot be asserted here.** In the
  // test font 'WM' wants 21.87px inside a 21px ring, so it wraps and the
  // paragraph reports its constraint (21.0) -- which makes a containment
  // check pass no matter what the avatar's geometry is, and a strict
  // inner-diameter check fail on correct code. Both are worthless.
  //
  // So the WIDGET tests in this file assert only what is font-independent:
  // the box size, the ring width, the 11px font floor, the text-scale cap,
  // and that nothing throws.
  //
  // Glyph fit itself is covered instead by the arithmetic test at the bottom
  // of this file, which compares the REAL Inter-SemiBold ink geometry --
  // read out of the shipped TTF's own tables by `tool/measure_avatar_font.py`
  // rather than rendered -- against MemberAvatar's exported ring and
  // font-size formulas. That is an analytical bound, not a render: it knows
  // nothing about hinting, anti-aliasing or sub-pixel rounding, so a look at
  // a real screen is still the closing gate (`docs/specs/design-language.md`,
  // definition of visual done: light + dark at text scale 1.0 and 2.0 on a
  // Pixel-class emulator).

  const stored = 0xFFD98E73; // renders 0xFFB96A4C light / 0xFFF0AF95 dark

  testWidgets('is a ring on the neutral surface, not a filled circle', (
    tester,
  ) async {
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final context = tester.element(find.byType(MemberAvatar));
    final scheme = Theme.of(context).colorScheme;
    final decoration = _decoration(tester);

    expect(decoration.shape, BoxShape.circle);
    expect(
      decoration.color,
      scheme.surfaceContainerHigh,
      reason: 'the ground is neutral; the colour lives in the ring',
    );
    expect(
      (decoration.border! as Border).top.color,
      categoryTone(context, stored),
    );
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('shows the first TWO letters, drawn in the ring colour', (
    tester,
  ) async {
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final context = tester.element(find.byType(MemberAvatar));
    // R2: the design's rule is the first two LETTERS of the display name
    // ('Mia' -> 'MI'), not the initials of two words.
    expect(find.text('MI'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('MI')).style!.color,
      categoryTone(context, stored),
    );
  });

  test('the initials rule handles every name shape', () {
    expect(memberInitials('Mia'), 'MI');
    expect(memberInitials('Anna'), 'AN');
    expect(memberInitials('Igor'), 'IG');
    expect(memberInitials('Leo'), 'LE');
    // Two words are NOT special-cased: first two letters, not word initials.
    expect(memberInitials('Anna Maria'), 'AN');
    // A one-character name yields one character, never padded.
    expect(memberInitials('J'), 'J');
    // A space as the second character is trimmed away rather than drawn.
    expect(memberInitials('J Smith'), 'J');
    expect(memberInitials('  mia  '), 'MI');
    expect(memberInitials('   '), '?');
    expect(memberInitials(''), '?');
  });

  test('the initials rule counts graphemes, not UTF-16 code units', () {
    // `substring(0, 2)` would split the balloon's surrogate pair here and
    // render an unpaired surrogate as a tofu box. The rule takes two
    // GRAPHEME CLUSTERS, so both survive intact. Emoji are deliberately not
    // excluded -- the rule is "the first two characters", and filtering to
    // letters-only would need a definition of "letter" that nothing has
    // decided (and would turn an all-emoji name into '?').
    expect(memberInitials('A\u{1F388}'), 'A\u{1F388}');
    // Leading non-BMP: pinned rather than left accidental.
    expect(memberInitials('\u{1F388}A'), '\u{1F388}A');
    expect(memberInitials('\u{1F388}'), '\u{1F388}');

    // A DECOMPOSED diacritic: 'A' + U+030A combining ring above, as in a
    // decomposed "Angstrom". `substring(0, 2)` takes the letter and its
    // combining mark, yielding ONE visible glyph; graphemes take the whole
    // cluster plus the following letter, yielding the two that were meant.
    expect(memberInitials('A\u030Angstro\u0308m'), 'A\u030AN');
    expect(
      memberInitials('A\u030Angstro\u0308m').characters,
      hasLength(2),
      reason: 'two visible glyphs, not a letter plus a floating diacritic',
    );

    // Whatever the rule yields, it is never half a character.
    for (final name in [
      'A\u{1F388}',
      '\u{1F388}A',
      '\u{1F388}',
      'A\u030Angstro\u0308m',
      'Mia',
      'J Smith',
    ]) {
      expect(
        _hasLoneSurrogate(memberInitials(name)),
        isFalse,
        reason: 'lone surrogate (tofu) for "$name"',
      );
    }
    // ...and the guard itself can fail: half a balloon is a lone surrogate.
    expect(_hasLoneSurrogate('A\u{1F388}'.substring(0, 2)), isTrue);
  });

  testWidgets('uses the DARK tone under the dark theme', (tester) async {
    await _pump(tester, appDarkTheme, name: 'Mia', color: stored);
    expect(
      (_decoration(tester).border! as Border).top.color,
      const Color(0xFFF0AF95),
    );
  });

  testWidgets('ring width tracks radius and reproduces the design values', (
    tester,
  ) async {
    // 42px row avatar (design: 2.5px ring).
    await _pump(tester, appLightTheme, name: 'Mia', color: stored, radius: 21);
    expect(
      (_decoration(tester).border! as Border).top.width,
      closeTo(2.5, 0.2),
    );
    // 66px sheet preview (design: 3px ring).
    await _pump(tester, appLightTheme, name: 'Mia', color: stored, radius: 33);
    expect((_decoration(tester).border! as Border).top.width, 3);
    // 32px chore tile (radius 16, the default): thinner than the 21/33 rows
    // above, and the smallest ring the two letters still clear (G-16). Left
    // implicit because `--fatal-infos` rejects `radius: 16` as redundant
    // against the helper's own default.
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    expect((_decoration(tester).border! as Border).top.width, 2);
  });

  testWidgets('the smallest avatar renders two letters without throwing', (
    tester,
  ) async {
    // G-16 sized the default radius at 16 (a 32px box); the margin that
    // buys is asserted arithmetically at the bottom of this file, not here,
    // for the reason in the note at the top. What IS asserted here is
    // font-independent: the widest two-letter pair lays out without an
    // exception, the box is the size G-16 specified, and the glyphs never
    // drop below the legibility floor.
    await _pump(tester, appLightTheme, name: 'Wm', color: stored);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MemberAvatar)), const Size(32, 32));
    expect(
      tester.widget<Text>(find.text('WM')).style!.fontSize,
      greaterThanOrEqualTo(11),
      reason: 'R2: 11px is the legibility floor for two uppercase glyphs',
    );
  });

  testWidgets('the whole avatar grows with text scale, capped at 1.6x', (
    tester,
  ) async {
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final base = tester.getSize(find.byType(MemberAvatar));
    expect(base.width, 32);

    await _pump(
      tester,
      appLightTheme,
      name: 'Mia',
      color: stored,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final scaled = tester.getSize(find.byType(MemberAvatar));
    expect(
      scaled.width,
      closeTo(32 * 1.6, 0.01),
      reason:
          'text scale 2.0 clamps to 1.6 -- the initials must keep pace with '
          'surrounding text, without bursting ListTile leading slots',
    );
    // NOT re-asserted here: that the glyphs still fit. A Text is laid out
    // inside the ring, so its reported width is its own constraint and the
    // check passes at any geometry -- one of the four tests wave 6 found
    // could not fail. Fit is the arithmetic test at the bottom of this file.
    // What this test can honestly add is that the RING grew with the box,
    // so the glyphs are not being asked to clear a stroke sized for an
    // unscaled avatar.
    expect(
      (_decoration(tester).border! as Border).top.width,
      memberAvatarRingWidth(scaled.width / 2),
    );
  });

  testWidgets('a blank name shows ?', (tester) async {
    await _pump(tester, appLightTheme, name: '   ', color: stored);
    expect(find.text('?'), findsOneWidget);
  });

  test(
    'two-letter initials stay inside the ring at every avatar size this '
    'widget controls its own box at, measured against the real shipped '
    'font (G-16)',
    () {
      // Real glyph geometry for Inter SemiBold -- the face FontWeight.w600
      // resolves to -- read straight out of the shipped
      // assets/fonts/Inter-SemiBold.ttf's own sfnt tables. NOT from a widget
      // test: `flutter test` draws the Ahem-style FlutterTest font, ~1 em
      // per glyph, so no widget test in this repo can measure whether text
      // physically fits (backlog G-14). Re-derive this number any time with
      //
      //     python3 tool/measure_avatar_font.py
      //
      // which brute-forces every ordered pair over A-Z, 0-9 and the
      // Latin-1/Extended capitals rather than assuming which pair is worst.
      // The winner is 'WW' at 1.05998 em, not 'WM' at 1.01426 -- a pair may
      // repeat a glyph. ('WA-ring' 1.05841 and 'OE-ligature W' 1.05700 sit
      // just behind it, so this is not a knife-edge on one exotic pair.)
      //
      // The quantity is the distance from the avatar's centre to the far
      // CORNER of the pair's ink box, because the ring is a circle and a
      // corner reaches further than either half-axis. It holds because
      // MemberAvatar pins `letterSpacing: 0` and inherits no `height`, and
      // because the Container's border padding centres the text box on the
      // avatar's centre.
      const cornerReachPerFontSize = 1.05998;

      // Read the default off the widget itself. Hard-coding it here would
      // leave this test passing if someone put the default back to 12 --
      // which is exactly how the two previous versions of this check ended
      // up unable to fail.
      final defaultRadius = MemberAvatar(
        member: previewMember(name: 'Wm', color: 0xFF7A5AA8),
      ).radius;

      double innerRadiusAt(double radius, double scale) {
        final scaledRadius = radius * scale;
        return scaledRadius - memberAvatarRingWidth(scaledRadius);
      }

      double cornerReachAt(double radius, double scale) =>
          cornerReachPerFontSize * memberAvatarFontSize(radius * scale);

      // Every radius `lib/` builds a MemberAvatar at where the widget
      // controls its own box, from `grep -rn 'MemberAvatar('`: the default
      // (chore tile, rotation row, stats share card, chore history, the
      // mark-done and acting-member sheets, the join chooser), 21
      // (manage_members_screen.dart) and 33 (member_edit_sheet.dart). Text
      // scale 1.0 and 1.6 (MemberAvatar's own cap) bound the range: the
      // margin is monotonically non-decreasing in scale for every fixed
      // radius here, checked numerically across the whole range by
      // tool/measure_avatar_font.py, so the ends bound the middle.
      for (final testCase in <({double radius, double scale})>[
        (radius: defaultRadius, scale: 1),
        (radius: defaultRadius, scale: 1.6),
        (radius: 21, scale: 1),
        (radius: 21, scale: 1.6),
        (radius: 33, scale: 1),
        (radius: 33, scale: 1.6),
      ]) {
        final inner = innerRadiusAt(testCase.radius, testCase.scale);
        final reach = cornerReachAt(testCase.radius, testCase.scale);
        expect(
          reach,
          lessThan(inner),
          reason:
              'radius ${testCase.radius} at scale ${testCase.scale}: the '
              "widest real pair ('WW') reaches "
              '${reach.toStringAsFixed(3)} logical px from the avatar centre '
              "but the ring's inner edge is only "
              '${inner.toStringAsFixed(3)}px out -- the initials would touch '
              'or cross the ring',
        );
      }

      // The margin is not merely positive: at the default it is the same
      // 12.8% of the inner radius that the design-canvas 42px (radius 21)
      // and 66px (radius 33) avatars have, which is the whole reason the
      // default is 16 and not the smaller 14 or 15 that would also "fit".
      // Radius 16 is the smallest radius at which memberAvatarFontSize's
      // 11px floor stops binding; below it the glyphs are held larger than
      // the design's own size relationship asks for, which is what produced
      // G-16.
      final defaultMargin =
          innerRadiusAt(defaultRadius, 1) - cornerReachAt(defaultRadius, 1);
      expect(
        defaultMargin / innerRadiusAt(defaultRadius, 1),
        greaterThan(0.12),
        reason:
            'the smallest avatar must have the same proportional glyph '
            'headroom as the two sizes the design canvas pins, not merely a '
            'sub-pixel escape: margin is '
            '${defaultMargin.toStringAsFixed(3)}px',
      );

      // The one place the app draws an avatar that this bound does NOT
      // cover, asserted as failing so the exclusion cannot rot into a
      // comment nobody re-checks -- and so this test demonstrates in every
      // CI run that its inequality can come out either way.
      //
      // Material lays a chip's avatar out with
      // BoxConstraints.tightFor(contentSize) -- ~24px, i.e. radius 12 --
      // whatever `radius` says, and _RenderChip.centerLayout asserts the
      // avatar is no taller than that content size, so no larger box can be
      // handed to it either. Two glyphs at the 11px legibility floor need
      // 2 * (1.05998 * 11 + 1.5) = 26.32px of outer diameter. The two
      // FilterChip avatars in chore_form/assignment_fields.dart are
      // therefore pinned to radius 12 (today's rendering, unchanged) and
      // tracked separately in docs/backlog.md; the remedy is a product
      // decision, not a geometry one.
      const chipForcedRadius = 12.0;
      expect(
        cornerReachAt(chipForcedRadius, 1),
        greaterThan(innerRadiusAt(chipForcedRadius, 1)),
        reason:
            'if a Material chip can now hold two letters at the 11px floor, '
            'the assignment_fields.dart chips should stop being an '
            'exception -- update them and this test together',
      );
    },
  );
}
