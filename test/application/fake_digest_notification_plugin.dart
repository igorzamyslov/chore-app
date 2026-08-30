/// A recording fake of [DigestNotificationPlugin] for scheduler and
/// reschedule-on-mutation tests (spec `docs/specs/notifications.md`
/// testing section): no real OS notification channel is ever touched.
library;

import 'package:chore_app/application/notification_scheduler.dart';

/// One recorded call to [FakeDigestNotificationPlugin.zonedSchedule].
class ScheduledCall {
  /// Creates a recorded call.
  const ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    this.payload,
    this.actionable = false,
  });

  /// The notification id passed to `zonedSchedule`.
  final int id;

  /// The notification title passed to `zonedSchedule`.
  final String title;

  /// The notification body passed to `zonedSchedule`.
  final String body;

  /// The fire time passed to `zonedSchedule`.
  final DateTime fireAt;

  /// The Android notification channel id passed to `zonedSchedule` (spec
  /// `docs/specs/notifications-n2.md` §9.3): one of `digestChannelId`,
  /// `remindersChannelId` or `eveningChannelId`.
  final String channelId;

  /// The localized Android notification channel name passed to
  /// `zonedSchedule` (backlog E-1).
  final String channelName;

  /// The localized Android notification channel description passed to
  /// `zonedSchedule` (backlog E-1).
  final String channelDescription;

  /// The JSON action payload passed to `zonedSchedule`, or `null` for a
  /// non-actionable slot (backlog F-1).
  final String? payload;

  /// Whether the "Done" action was attached to this notification (backlog
  /// F-1).
  final bool actionable;

  @override
  String toString() =>
      'ScheduledCall(id: $id, title: $title, body: $body, fireAt: $fireAt, '
      'channelId: $channelId, channelName: $channelName, '
      'channelDescription: $channelDescription, '
      'payload: $payload, actionable: $actionable)';
}

/// A fake [DigestNotificationPlugin] that records every call instead of
/// touching a real notification channel.
class FakeDigestNotificationPlugin implements DigestNotificationPlugin {
  /// Whether [isPermissionGranted] should report the permission as
  /// granted; flip this in a test to simulate a denied permission.
  bool permissionGranted = true;

  /// How many times [initialize] was called.
  int initializeCallCount = 0;

  /// The localized "Done" action title passed to the most recent
  /// [initialize] call, or `null` if it was never called (backlog F-1).
  ///
  /// Used only for the iOS notification category, whose action titles are
  /// fixed at registration time.
  String? lastDoneActionTitle;

  /// How many times [requestPermission] was called.
  int requestPermissionCallCount = 0;

  /// How many times [cancel] was called.
  int cancelCallCount = 0;

  /// How many times `deleteLegacyDigestChannel` was called.
  int deleteLegacyDigestChannelCallCount = 0;

  /// Every [zonedSchedule] call, in order.
  final List<ScheduledCall> scheduledCalls = [];

  /// Every currently-armed notification, keyed by id: [zonedSchedule]
  /// replaces the entry for that id, [cancel] removes it, and [deliverDue]
  /// removes the ones the OS would already have shown.
  ///
  /// This models what `pendingNotificationRequests()` reports on a real
  /// device. [scheduledCalls] stays a full append-only history (used for
  /// debounce/burst assertions); this is the *current state*.
  final Map<int, ScheduledCall> pending = {};

  /// Simulates the OS delivering every armed notification whose `fireAt` is
  /// at or before [now], removing it from [pending]. Nothing re-arms them —
  /// which is exactly the behaviour the horizon exists to survive.
  void deliverDue(DateTime now) {
    pending.removeWhere((_, call) => !call.fireAt.isAfter(now));
  }

  @override
  Future<void> initialize({required String doneActionTitle}) async {
    initializeCallCount++;
    lastDoneActionTitle = doneActionTitle;
  }

  @override
  Future<void> requestPermission() async {
    requestPermissionCallCount++;
  }

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelId,
    required String channelName,
    required String channelDescription,
    String? payload,
    bool actionable = false,
  }) async {
    final call = ScheduledCall(
      id: id,
      title: title,
      body: body,
      fireAt: fireAt,
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
      payload: payload,
      actionable: actionable,
    );
    scheduledCalls.add(call);
    pending[id] = call;
  }

  @override
  Future<void> cancel(int id) async {
    cancelCallCount++;
    pending.remove(id);
  }

  @override
  Future<void> deleteLegacyDigestChannel() async {
    deleteLegacyDigestChannelCallCount++;
  }
}
