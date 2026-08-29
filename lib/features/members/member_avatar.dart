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
/// Shared with the member edit sheet's taken-swatch badge, so a disabled
/// swatch always shows exactly what that member's avatar shows.
String memberInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  final head = trimmed.substring(0, 1);
  return head.trim().toUpperCase();
}

/// A member's avatar: their two-letter initials (or `?` for a blank name)
/// on the neutral surface, inside a ring in [member]'s color (G-4, design
/// canvas frame 1b).
///
/// A ring rather than a fill so the same avatar is legible at 24px in a
/// chore tile and 66px in the member edit sheet: the initials always sit on
/// `surfaceContainerHigh` against `categoryTone`, a pairing the tone table
/// guarantees at >= 3:1 in both themes (`test/app/palette_test.dart`),
/// instead of on a fill whose legibility varied with the color.
///
/// [radius] defaults to 12 (the chore tile's compact inline size -- 24px,
/// sized so two glyphs fit inside the ring with margin); pass a larger
/// value for a more prominent context (the members list at 21, the
/// acting-member app-bar button, the switcher sheet, the edit sheet's
/// 33-radius preview).
class MemberAvatar extends StatelessWidget {
  /// Creates an avatar for [member].
  const MemberAvatar({required this.member, this.radius = 12, super.key});

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
    // radius / 8 reproduces the design's own two stated ring widths: 2.6 at
    // its 42px row avatar (radius 21, drawn 2.5) and 3.0 at its 66px preview
    // (radius 33, drawn 3). The 1.5 floor keeps the 24px chore-tile avatar
    // from being mostly ring.
    final ringWidth = (scaledRadius / 8).clamp(1.5, 3.0);
    // 0.72 likewise lands on the design's 15px and 23px at those two sizes;
    // the 11px floor is Material's smallest label size, below which two
    // uppercase glyphs stop being readable.
    final fontSize = (scaledRadius * 0.72).clamp(11.0, double.infinity);
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
          color: tone,
        ),
      ),
    );
  }
}
