/// Fake [AuthGateway] for the Settings Account-section widget tests: no
/// real network calls, fully controllable signed-in/out state and
/// success/failure behavior.
library;

import 'dart:async';

import 'package:chore_app/application/auth_gateway.dart';

/// A controllable fake [AuthGateway].
///
/// `currentUser` seeds the initial signed-in/out state (`null` for
/// signed-out, the default). [signIn]/[signOut] push a new value onto
/// `watchUser`'s stream, letting a test drive the UI's signed-in/out
/// transition directly rather than through a real magic-link round trip.
/// [sendMagicLinkError], if set, makes the next [sendMagicLink] call throw
/// that error instead of succeeding -- used to exercise the section's
/// generic error snackbar.
class FakeAuthGateway implements AuthGateway {
  /// Creates a fake gateway, signed out unless `currentUser` is given.
  FakeAuthGateway({this.currentUser});

  final _controller = StreamController<AuthUser?>.broadcast();

  /// The currently signed-in user, or `null` while signed out. Read once
  /// as the seed for [watchUser]'s stream; update it via [signIn] or
  /// [signOut] rather than assigning it directly once a test has started
  /// listening.
  AuthUser? currentUser;

  /// Set to make the next [sendMagicLink] call throw this instead of
  /// recording the call in [sentMagicLinks].
  Exception? sendMagicLinkError;

  /// Every email address [sendMagicLink] was successfully called with, in
  /// call order.
  final List<String> sentMagicLinks = [];

  /// Set to make the next [signOut] call throw this instead of succeeding.
  ///
  /// Models the realistic post-erasure case: `delete_account()` has already
  /// removed the `auth.users` row, so the sign-out round trip that follows
  /// it can legitimately fail.
  ///
  /// `Object?`, unlike [sendMagicLinkError] and the gateway fake's hooks:
  /// `HouseholdExitService.deleteAccount` catches `on Object` rather than
  /// `on Exception`, and a hook that can only carry an [Exception] cannot
  /// tell the two clauses apart -- the rule would be untestable and free to
  /// regress. One test throws a [StateError] through here.
  Object? signOutError;

  @override
  Stream<AuthUser?> watchUser() async* {
    yield currentUser;
    yield* _controller.stream;
  }

  @override
  Future<void> sendMagicLink(String email) async {
    final error = sendMagicLinkError;
    if (error != null) {
      throw error;
    }
    sentMagicLinks.add(email);
  }

  @override
  Future<void> signOut() async {
    final error = signOutError;
    if (error != null) {
      // The WHOLE POINT of [signOutError] is that its static type is
      // `Object?`, so a test can throw something that is not an [Exception]
      // and prove `HouseholdExitService.deleteAccount` catches `on Object`
      // rather than `on Exception`. Narrowing the field to satisfy
      // `only_throw_errors` would delete the coverage the field exists for.
      // The ignore has to sit on the line directly above the throw --
      // `// ignore:` applies to the next line only, and a block comment
      // between the two makes it an `unnecessary_ignore` while the original
      // lint still fires.
      // ignore: only_throw_errors
      throw error;
    }
    currentUser = null;
    _controller.add(null);
  }

  /// Test-setup helper simulating a completed magic-link sign-in: pushes
  /// [user] onto `watchUser`'s stream.
  void signIn(AuthUser user) {
    currentUser = user;
    _controller.add(user);
  }
}
