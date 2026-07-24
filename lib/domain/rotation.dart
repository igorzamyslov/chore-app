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
/// Throws [ArgumentError] if [orderedMemberIds] is empty.
String nextRotationAssignee({
  required List<String> orderedMemberIds,
  required String? lastAssignedMemberId,
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
  if (lastIndex == -1) {
    return orderedMemberIds.first;
  }
  return orderedMemberIds[(lastIndex + 1) % orderedMemberIds.length];
}
