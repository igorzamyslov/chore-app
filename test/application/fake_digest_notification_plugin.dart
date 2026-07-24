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
  });

  /// The notification id passed to `zonedSchedule`.
  final int id;

  /// The notification title passed to `zonedSchedule`.
  final String title;

  /// The notification body passed to `zonedSchedule`.
  final String body;

  /// The fire time passed to `zonedSchedule`.
  final DateTime fireAt;

  @override
  String toString() =>
      'ScheduledCall(id: $id, title: $title, body: $body, fireAt: $fireAt)';
}

/// A fake [DigestNotificationPlugin] that records every call instead of
/// touching a real notification channel.
class FakeDigestNotificationPlugin implements DigestNotificationPlugin {
  /// Whether [isPermissionGranted] should report the permission as
  /// granted; flip this in a test to simulate a denied permission.
  bool permissionGranted = true;

  /// How many times [initialize] was called.
  int initializeCallCount = 0;

  /// How many times [requestPermission] was called.
  int requestPermissionCallCount = 0;

  /// How many times [cancel] was called.
  int cancelCallCount = 0;

  /// Every [zonedSchedule] call, in order.
  final List<ScheduledCall> scheduledCalls = [];

  @override
  Future<void> initialize() async {
    initializeCallCount++;
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
  }) async {
    scheduledCalls.add(
      ScheduledCall(id: id, title: title, body: body, fireAt: fireAt),
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelCallCount++;
  }
}
