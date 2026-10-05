/// Pure rotation-assignment logic, independent of the data layer.
///
/// Same purity standard as `lib/domain/recurrence/`: zero imports beyond
/// `dart:core`, so this is trivially testable and reusable.
library;

/// Returns the member who takes the next turn in a rotation.
///
/// [orderedMemberIds] is the rotation order (must be non-empty). Returns the
/// member after [lastAssignedMemberId] in that order, wrapping around to the
/// start after the last position. If [lastAssignedMemberId] is `null` or no
/// longer present in [orderedMemberIds] (e.g. the chore's assignees were
/// edited since the last assignment), returns the first member.
///
/// [skipMemberId] is whoever just did the turn (spec
/// `docs/specs/occurrence-lifecycle.md` §2 "Covering for someone"): if the
/// member found above is [skipMemberId] and [orderedMemberIds] holds anyone
/// else, the member after them is returned instead, so covering for someone
/// never hands the coverer the very next turn. The order itself is never
/// re-based on [skipMemberId].
///
/// Throws [ArgumentError] if [orderedMemberIds] is empty.
String nextRotationAssignee({
  required List<String> orderedMemberIds,
  required String? lastAssignedMemberId,
  String? skipMemberId,
}) {
  if (orderedMemberIds.isEmpty) {
    throw ArgumentError.value(
      orderedMemberIds,
      'orderedMemberIds',
      'Must not be empty',
    );
  }
  final lastIndex = lastAssignedMemberId == null
      ? -1
      : orderedMemberIds.indexOf(lastAssignedMemberId);
  final length = orderedMemberIds.length;
  final nextIndex = (lastIndex + 1) % length;
  final next = orderedMemberIds[nextIndex];
  if (next == skipMemberId && length > 1) {
    return orderedMemberIds[(nextIndex + 1) % length];
  }
  return next;
}
