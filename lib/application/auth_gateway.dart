/// Client-side authentication abstraction (spec
/// `docs/specs/sync-backend.md` §5).
///
/// Widgets depend on this interface, never on `Supabase.instance` directly
/// -- see [NoopAuthGateway], which `authGatewayProvider`
/// (`lib/app/providers.dart`) returns whenever Supabase isn't configured
/// (`supabaseConfigured` false), keeping the whole app usable offline
/// (spec §0: "the app remains fully functional offline and for
/// never-signed-in users"). Tests substitute their own fake (see
/// `test/features/settings/fake_auth_gateway.dart`) rather than exercising
/// either implementation in this file directly.
library;

import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// The famdo custom-scheme deep link Supabase redirects the magic-link
/// email to (iOS URL scheme + Android intent filter -- see
/// `ios/Runner/Info.plist` and `android/app/src/main/AndroidManifest.xml`).
const String authCallbackRedirectUrl = 'famdo://auth-callback';

/// A signed-in user's minimal identity.
@immutable
class AuthUser {
  /// Creates an identity from the given [id] and [email].
  const AuthUser({required this.id, required this.email});

  /// The Supabase auth user id.
  final String id;

  /// The user's email address.
  final String email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'AuthUser($id, $email)';
}

/// The narrow seam between Settings' Account section and real client
/// authentication.
abstract class AuthGateway {
  /// Watches the currently signed-in user, emitting `null` while signed
  /// out.
  Stream<AuthUser?> watchUser();

  /// Sends a magic-link sign-in email to [email].
  Future<void> sendMagicLink(String email);

  /// Signs the current user out.
  Future<void> signOut();
}

/// The always-signed-out [AuthGateway] returned by `authGatewayProvider`
/// whenever Supabase isn't configured -- tests, E2E, and F-Droid users who
/// never sign in all get this instead of ever touching a live Supabase
/// client.
class NoopAuthGateway implements AuthGateway {
  /// Creates the no-op gateway.
  const NoopAuthGateway();

  @override
  Stream<AuthUser?> watchUser() => Stream.value(null);

  @override
  Future<void> sendMagicLink(String email) {
    throw StateError('Supabase is not configured; cannot send a magic link.');
  }

  @override
  Future<void> signOut() async {}
}

/// The production [AuthGateway]: a thin wrapper over
/// `Supabase.instance.client.auth`.
///
/// `Supabase.instance` is only ever touched lazily, inside each method
/// call below -- never from this class's constructor -- so merely
/// constructing one (as `authGatewayProvider`'s default branch does) can't
/// throw even if `Supabase.initialize()` hasn't run yet.
class SupabaseAuthGateway implements AuthGateway {
  /// Creates a gateway over the app's Supabase client. `Supabase.
  /// initialize()` must have already run (see `main.dart`) before any
  /// method on this class is called.
  const SupabaseAuthGateway();

  supabase.SupabaseClient get _client => supabase.Supabase.instance.client;

  @override
  Stream<AuthUser?> watchUser() {
    return _client.auth.onAuthStateChange.map((state) {
      final user = state.session?.user;
      final email = user?.email;
      if (user == null || email == null) {
        return null;
      }
      return AuthUser(id: user.id, email: email);
    });
  }

  @override
  Future<void> sendMagicLink(String email) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: authCallbackRedirectUrl,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
