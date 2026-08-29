/// The member avatar is a ring, not a fill (G-4, design canvas frame 1b):
/// two-letter initials on the neutral surface inside a ring in the member's
/// theme-rendered colour, legible from the 24px chore tile to the 66px
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
  double radius = 12,
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
    // 24px chore tile (radius 12, the default): thinner, so the two letters
    // still have room. Left implicit because `--fatal-infos` rejects
    // `radius: 12` as redundant against the helper's own default.
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    expect((_decoration(tester).border! as Border).top.width, 1.5);
  });

  testWidgets('two letters fit inside the smallest avatar without overflow', (
    tester,
  ) async {
    // R2: the default radius is 12 (a 24px box) precisely so two glyphs fit
    // with margin. 'WM' is about the widest two-letter pair in the alphabet.
    //
    // Containment is measured against the avatar's own box, not the ring's
    // inner diameter: widget tests never load Inter (this repo has no
    // flutter_test_config.dart), so text falls back to the `FlutterTest`
    // font, where every glyph is a FULL em -- 22px for 'WM' at the 11px
    // floor, against Inter's ~15px. The font-independent property that
    // matters is that the glyphs never escape the widget.
    await _pump(tester, appLightTheme, name: 'Wm', color: stored);
    expect(tester.takeException(), isNull);
    final textRect = tester.getRect(find.text('WM'));
    final avatarRect = tester.getRect(find.byType(MemberAvatar));
    expect(
      avatarRect.contains(textRect.topLeft) &&
          avatarRect.contains(textRect.bottomRight),
      isTrue,
      reason: 'two glyphs must stay inside the avatar at the default radius',
    );
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
    expect(base.width, 24);

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
      closeTo(24 * 1.6, 0.01),
      reason:
          'text scale 2.0 clamps to 1.6 -- the initials must keep pace with '
          'surrounding text, without bursting ListTile leading slots',
    );
    // The glyphs grew too, and still fit.
    expect(
      tester.getSize(find.text('MI')).width,
      lessThan(
        scaled.width - 2 * (_decoration(tester).border! as Border).top.width,
      ),
    );
  });

  testWidgets('a blank name shows ?', (tester) async {
    await _pump(tester, appLightTheme, name: '   ', color: stored);
    expect(find.text('?'), findsOneWidget);
  });
}
