/// Shared member avatar rendering (spec
/// `docs/specs/members-management.md`): two-letter initials on the neutral
/// surface inside a ring in the member's color.
///
/// Originally written for the chore occurrence tile's inline assignee
/// metadata, then extracted here so the members screen and the
/// acting-member switcher can reuse the same rendering rather than forking
/// it.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// Builds a throwaway [Member] carrying only [name] and [color] -- the two
/// fields [MemberAvatar] reads -- for callers that do not have a real row:
/// the member edit sheet's live preview (the member may not exist yet) and
/// the join chooser (which has a `ClaimableMember`). Every other field is an
/// inert placeholder; never write one of these to the database.
Member previewMember({required String name, required int color}) => Member(
  id: '',
  householdId: '',
  name: name,
  color: color,
  role: MemberRole.member,
  createdAt: '',
  updatedAt: '',
  syncDirty: false,
);

/// The badge for [name]: its first two characters, uppercased, or `?` when
/// the name is blank (G-4 / plan decision R2).
///
/// Two characters, not one, because for a color-blind viewer the initials
/// are the ONLY channel separating one member from another -- "Anna" and
/// "Alex" collide at one letter and separate at two
/// (`docs/specs/design-language.md`: color is never the only carrier). That
/// matters more since the palette widened to twelve, whose closest pair
/// (`#6B57B0` purple and `#7A5AA8` violet) sits at CIELAB dE 7.8, well
/// tighter than the original eight's 25.8.
///
/// The rule is the first two LETTERS OF THE NAME, matching the design
/// canvas ('Mia' -> 'MI'), NOT the initials of two words: "Anna Maria" is
/// "AN", not "AM". The trailing trim handles a name whose second character
/// is a space ("J Smith" -> "J").
///
/// "Two characters" means two **grapheme clusters**, via `String.characters`
/// -- never `substring(0, 2)`, which indexes UTF-16 code units. A name whose
/// second character is non-BMP ("A(emoji)") would have its surrogate pair
/// split by `substring`, rendering an unpaired surrogate as a tofu box; and a
/// decomposed diacritic ("A" + U+030A ring, as in a decomposed "Angstrom")
/// would be cut into a letter plus a floating combining mark, yielding one
/// visible glyph where two were intended. Both are plausible in a family's
/// member names, and a tofu box separates nobody -- which is the whole
/// argument for two characters in the first place.
///
/// Emoji are NOT excluded: the rule is "the first two characters", so
/// "A(emoji)" keeps both, as one clean grapheme each. Filtering to
/// letters-only would need a definition of "letter" that nothing has
/// decided, and would turn an all-emoji name into "?".
///
/// Shared with the member edit sheet's taken-swatch badge, so a disabled
/// swatch always shows exactly what that member's avatar shows.
String memberInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  // `characters` comes from Flutter's own re-export in `widgets.dart`, so
  // this needs no import and no pubspec entry.
  final head = trimmed.characters.take(2).toString();
  return head.trim().toUpperCase();
}

/// The avatar's ring stroke width for an already text-scale-adjusted
/// [scaledRadius].
///
/// `scaledRadius / 8` reproduces the design's own two stated ring widths --
/// 2.6 at its 42px row avatar (radius 21, drawn 2.5) and 3.0 at its 66px
/// preview (radius 33, drawn 3) -- floored at 1.5 so the ring never gets so
/// thin it disappears at the smallest sizes, and capped at 3.0 so the
/// largest avatar is not mostly ring.
///
/// Exported (rather than inlined in `build`) so the fit check in
/// `test/features/members/member_avatar_test.dart` measures the geometry
/// this widget actually draws instead of a copy of it.
double memberAvatarRingWidth(double scaledRadius) =>
    (scaledRadius / 8).clamp(1.5, 3.0);

/// The avatar's initials font size for an already text-scale-adjusted
/// [scaledRadius].
///
/// `scaledRadius * 0.72` lands on the design's 15px and 23px at radius 21
/// and 33, floored at 11px -- below which two uppercase glyphs stop being
/// legible (G-4 / R2).
///
/// Never lower this floor to make two letters fit a smaller ring; grow the
/// ring instead (G-16). A smaller glyph at the same border position trades
/// one defect for another wearing a different hat. Note that the floor
/// binds for every `scaledRadius` below `11 / 0.72 = 15.28`, and that while
/// it binds the glyphs are larger than the design's own size relationship
/// asks for -- which is the mechanism behind G-16, and the reason the
/// default radius is 16 rather than the smallest value that merely fits.
double memberAvatarFontSize(double scaledRadius) =>
    (scaledRadius * 0.72).clamp(11.0, double.infinity);

/// A member's avatar: their two-letter initials (or `?` for a blank name)
/// on the neutral surface, inside a ring in [member]'s color (G-4, design
/// canvas frame 1b).
///
/// A ring rather than a fill so the same avatar is legible at 32px in a
/// chore tile and 66px in the member edit sheet: the initials always sit on
/// `surfaceContainerHigh` against `categoryTone`, a pairing the tone table
/// guarantees at >= 3:1 in both themes (`test/app/palette_test.dart`),
/// instead of on a fill whose legibility varied with the color.
///
/// [radius] defaults to 16 -- a 32px box. That is the smallest radius at
/// which [memberAvatarFontSize]'s 11px legibility floor stops binding, and
/// therefore the smallest at which the initials get the design's own 12.8%
/// of glyph headroom inside the ring, the same proportion the 42px and 66px
/// avatars already have. It was 12, and at 12 the widest real two-letter
/// pair overflowed the ring by 1.16px at ordinary unscaled text -- backlog
/// G-16, measured against the shipped font by `tool/measure_avatar_font.py`
/// and asserted in `test/features/members/member_avatar_test.dart`. Pass a
/// larger value for a more prominent context (the members list at 21, the
/// edit sheet's 33-radius preview).
///
/// One caveat, because it is invisible from here: a parent that imposes a
/// TIGHT constraint overrides this size entirely. Material chips do exactly
/// that (`BoxConstraints.tightFor(contentSize)`, ~24px), so the two
/// `FilterChip` avatars in `chore_form/assignment_fields.dart` pass an
/// explicit `radius: 12` to match the box they will actually be given, and
/// sit outside the fit guarantee above.
class MemberAvatar extends StatelessWidget {
  /// Creates an avatar for [member].
  const MemberAvatar({required this.member, this.radius = 16, super.key});

  /// The member this avatar represents.
  final Member member;

  /// The avatar's unscaled radius, in logical pixels. The rendered radius
  /// is this times the viewer's text scale, capped at 1.6x.
  final double radius;

  /// The cap on text-scale growth. Uncapped, a 2.0-scale avatar bursts
  /// `ListTile` leading slots and the chore form's chip rows.
  static const double _maxTextScale = 1.6;

  @override
  Widget build(BuildContext context) {
    // categoryTone (spec docs/specs/theme-v2.md §1.3) resolves the stored
    // color to its per-theme render; ring and initials are drawn in the same
    // tone, against surfaceContainerHigh. FamdoColors.onMemberColor is no
    // longer read here -- there is no fill left to sit on.
    final tone = categoryTone(context, member.color);
    final initials = memberInitials(member.name);
    // The whole avatar scales -- box, ring and glyphs together -- rather
    // than the text alone. Scaling the text inside a fixed box would
    // overflow the ring; not scaling at all would leave 11px initials
    // beside 22px labels for the viewer who asked for larger text.
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, _maxTextScale);
    final scaledRadius = radius * scale;
    final ringWidth = memberAvatarRingWidth(scaledRadius);
    final fontSize = memberAvatarFontSize(scaledRadius);
    return Container(
      width: scaledRadius * 2,
      height: scaledRadius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(color: tone, width: ringWidth),
      ),
      child: Text(
        initials,
        // The scale is already applied to `fontSize` above; letting the
        // Text scale again would double-apply it.
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          // Pinned, not inherited. Flutter adds letterSpacing after EVERY
          // glyph, and this theme ships roles from -1.5 to +1.2, so an
          // ambient DefaultTextStyle could eat most of the ring clearance
          // G-16 establishes -- which would make that guarantee depend on
          // where the avatar happened to be placed.
          letterSpacing: 0,
          color: tone,
        ),
      ),
    );
  }
}
