/// Shared member avatar rendering (spec
/// `docs/specs/members-management.md`): a colored circle with the member's
/// first-letter initial.
///
/// Originally written for the chore occurrence tile's inline assignee
/// metadata, then extracted here so the members screen and the
/// acting-member switcher can reuse the same rendering rather than forking
/// it.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// A circular avatar in [member]'s color, showing their first-letter
/// initial (or `?` for a blank name).
///
/// [radius] defaults to 10 (the chore tile's compact inline size); pass a
/// larger value for a more prominent context (the members list, the
/// acting-member app-bar button, the switcher sheet).
class MemberAvatar extends StatelessWidget {
  /// Creates an avatar for [member].
  const MemberAvatar({required this.member, this.radius = 10, super.key});

  /// The member this avatar represents.
  final Member member;

  /// The avatar's radius, in logical pixels.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = Color(member.color);
    final trimmedName = member.name.trim();
    final initial = trimmedName.isEmpty
        ? '?'
        : trimmedName.substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: radius * 1.1,
          fontWeight: FontWeight.w600,
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
    );
  }
}
