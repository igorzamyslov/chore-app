/// The digest notification action's payload: the only channel that can say
/// WHAT the user tapped "Done" on (spec `docs/specs/notifications.md` N2,
/// backlog F-1).
///
/// Encoder and decoder live in the SAME library on purpose. They are written
/// by the main isolate and read by a background isolate that shares no state
/// with it, so a schema mismatch between the two would be invisible until a
/// real device dropped a real user's tap on the floor. Keeping the pair and
/// the constants they agree on in one file makes "they cannot drift"
/// structural rather than a comment on two files.
///
/// ## Why a payload at all, rather than the notification id
///
/// Notification ids are SLOT-RELATIVE: `digestNotificationIdBase + k` where
/// `k` is the offset from the NEXT slot, so id 1001 means Monday 07:00 on one
/// recompute and Tuesday 09:00 on the next, and past the daily segment slot
/// `k` is not even `k` days out. An id therefore names neither a chore nor a
/// date. On top of that `NotificationResponse.id` is not reliably delivered
/// on the background path at all — `flutter_local_notifications`'
/// `callback_dispatcher.dart` substitutes `-1` when the native value is
/// neither an `int` nor a `String`. Nothing about what was actioned may be
/// inferred from the id.
///
/// ## Why JSON rather than a delimited string
///
/// Two fields already, and the background callback is **process-global**: it
/// receives responses for every notification this app will ever schedule,
/// including the 40 ids reserved for the unbuilt per-chore reminders (backlog
/// G-6 / F16). A self-describing, versioned payload is what lets G-6 add its
/// own shape later without either side having to guess which it is holding.
library;

import 'dart:convert';

/// The payload schema version written by this build.
///
/// Bumped only for a change a previous build's decoder could misread; the
/// decoder rejects anything it does not recognize outright, so an older app
/// silently no-ops rather than acting on a payload it half-understands.
const int digestActionPayloadVersion = 1;

const String _versionKey = 'v';
const String _occurrenceKey = 'occ';
const String _memberKey = 'by';

/// A decoded digest action payload.
class DigestActionPayload {
  /// Creates a payload.
  const DigestActionPayload({
    required this.occurrenceId,
    required this.actingMemberId,
  });

  /// The occurrence row to complete.
  ///
  /// The action means "complete THIS row if it is still pending", never
  /// "complete whatever is due on the date this notification describes" —
  /// which is what makes the answer independent of which slot fired and of
  /// how long the notification sat unread in the shade.
  final String occurrenceId;

  /// The member the completion is attributed to, or `null` for an
  /// unattributed completion.
  ///
  /// Resolved in the MAIN isolate and carried here, never re-derived by the
  /// background isolate. The real chain (`actingMemberProvider`) consults
  /// `memberIdentityModeProvider`, which needs a live Supabase auth session
  /// the isolate must not have, and in PINNED mode with no resolvable claim
  /// it deliberately returns `null` rather than guessing at a member — that
  /// guess is exactly the misattribution backlog A-5 closed. A simplified
  /// isolate-side "stored id, else first admin, else first member" chain
  /// would re-introduce A-5 for every linked household.
  ///
  /// `null` therefore means "identity is genuinely unknown" and must pass
  /// straight through to `completeOccurrence(completedBy: null)`. An
  /// unattributed completion is the honest answer; inventing a member is not.
  final String? actingMemberId;
}

/// Encodes the payload for the slot naming [occurrenceId], attributed to
/// [actingMemberId] (which may be `null`).
String encodeDigestActionPayload({
  required String occurrenceId,
  required String? actingMemberId,
}) {
  return jsonEncode(<String, Object?>{
    _versionKey: digestActionPayloadVersion,
    _occurrenceKey: occurrenceId,
    _memberKey: actingMemberId,
  });
}

/// Decodes [raw], or returns `null` if it is not a payload this build
/// understands.
///
/// Never throws. [raw] arrives from the OS across a process boundary, may be
/// absent, and may have been written by a different version of this app that
/// the user has since upgraded past — so malformed JSON, a non-object, an
/// unknown version, and a missing/blank/non-string occurrence id all mean the
/// same thing: do nothing. A silent no-op is the correct response because
/// there is no UI in the background isolate to report an error to.
DigestActionPayload? decodeDigestActionPayload(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  if (decoded[_versionKey] != digestActionPayloadVersion) {
    return null;
  }
  final occurrenceId = decoded[_occurrenceKey];
  if (occurrenceId is! String || occurrenceId.isEmpty) {
    return null;
  }
  final actingMemberId = decoded[_memberKey];
  return DigestActionPayload(
    occurrenceId: occurrenceId,
    // A non-string `by` (a corrupt or foreign payload) degrades to "identity
    // unknown" rather than to a rejected action: the occurrence id is the
    // part the user's intent depends on, and an unattributed completion is
    // strictly better than losing the tap.
    actingMemberId: actingMemberId is String ? actingMemberId : null,
  );
}
