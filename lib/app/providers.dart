/// Riverpod wiring: database, repositories, service, clock, and bootstrap.
///
/// `appDatabaseProvider` and `clockProvider` are the only two providers a
/// *widget* test or E2E run ever needs to override; every screen-facing
/// provider is built on top of them, so overriding just those two is enough
/// to make the whole app deterministic and hermetic (in-memory database,
/// fixed clock). [digestNotificationPluginProvider] is a third override
/// point used only by scheduler/reschedule tests (spec
/// `docs/specs/notifications.md`), swapping the real OS-level plugin for a
/// fake; see that provider's doc comment. [authGatewayProvider] is a
/// fourth, used only by Settings Account-section tests (spec
/// `docs/specs/sync-backend.md` §5); see its own doc comment.
/// [householdGatewayProvider] is a fifth -- alongside [authGatewayProvider],
/// the two Settings/Members widget tests need on top of db/clock (spec
/// `docs/specs/sync-backend.md` §7.2); see its own doc comment.
/// [syncEngineProvider] defaults to [NoopSyncEngine] whenever
/// [supabaseConfigured] is false, the device is unlinked, or no user is
/// currently signed in (spec `docs/feedback/2026-08-01-ux-audit.md` A5) --
/// true for every widget test and E2E run -- so no test needs to override
/// it for ordinary widget tests (spec `docs/specs/sync-backend.md` §8.2);
/// see its own doc comment. [syncTransportProvider] is a sixth override
/// point, used only by `test/app/sync_engine_provider_test.dart` to exercise
/// [syncEngineProvider]'s own linked-state branching against a fake
/// transport, bypassing the compile-time [supabaseConfigured] gate that a
/// test binary can't otherwise flip; see its own doc comment.
library;

import 'dart:async';

import 'package:chore_app/app/supabase_config.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/digest_plan_builder.dart';
import 'package:chore_app/application/household_create_service.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/application/household_link_service.dart';
import 'package:chore_app/application/member_service.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The raw value of the `E2E_TODAY` dart-define, read at compile time.
///
/// Pass `--dart-define=E2E_TODAY=2026-07-24` to pin [clockProvider] to a
/// fixed date for E2E runs; leave it unset for the real system clock.
const String _e2eToday = String.fromEnvironment('E2E_TODAY');

/// The on-device database. Default: `AppDatabase(openConnection())`.
///
/// Overridden in tests with `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(openConnection());
  ref.onDispose(database.close);
  return database;
});

/// The clock used to determine "today" throughout the app.
///
/// Default: [resolveClock] applied to the `E2E_TODAY` dart-define. Widget
/// and E2E tests override this directly with `Clock.fixed(...)` so section
/// bucketing and due-date math never depend on the real wall clock.
final clockProvider = Provider<Clock>((ref) => resolveClock(_e2eToday));

/// Resolves the clock described by [clockProvider]'s doc comment.
///
/// Pulled out as a top-level function (rather than inlined in the provider)
/// so its parsing logic can be exercised directly in tests without needing
/// to pass a compile-time dart-define. Empty [e2eToday] means "use the real
/// clock"; otherwise it must be an ISO-8601 date (e.g. `2026-07-24`), and the
/// returned clock is fixed at that date's 09:00 local time.
Clock resolveClock(String e2eToday) {
  if (e2eToday.isEmpty) {
    return const Clock();
  }
  final date = PlainDate.parse(e2eToday);
  return Clock.fixed(DateTime(date.year, date.month, date.day, 9));
}

/// The chore repository, built on [appDatabaseProvider].
final choreRepositoryProvider = Provider<ChoreRepository>((ref) {
  return ChoreRepository(ref.watch(appDatabaseProvider));
});

/// The category repository, built on [appDatabaseProvider].
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(appDatabaseProvider));
});

/// The household repository, built on [appDatabaseProvider].
final householdRepositoryProvider = Provider<HouseholdRepository>((ref) {
  return HouseholdRepository(ref.watch(appDatabaseProvider));
});

/// The welcome gate (spec `docs/specs/onboarding-v2.md` §1/§2): whether any
/// household row exists locally yet. `ChoreApp` (`lib/app/app.dart`) shows
/// `WelcomeScreen` while this resolves to `null` (a fresh install -- no
/// household until the user explicitly creates or joins one) and the tab
/// shell once it resolves to a household. An existing install's very first
/// emission is already non-null, so the gate never appears for it.
final householdGateProvider = StreamProvider<Household?>((ref) {
  return ref.watch(householdRepositoryProvider).watchHouseholdOrNull();
});

/// The shopping repository, built on [appDatabaseProvider].
final shoppingRepositoryProvider = Provider<ShoppingRepository>((ref) {
  return ShoppingRepository(ref.watch(appDatabaseProvider));
});

/// The settings repository, built on [appDatabaseProvider].
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

/// The device settings singleton row, kept in sync with the database.
///
/// Watched by the settings screen (toggle/time rows) and by
/// [DigestRescheduleController] (to recompute the digest plan whenever the
/// digest is enabled/disabled or its time changes).
final settingsProvider = StreamProvider<DeviceSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watchSettings();
});

/// The language override chosen via Settings (spec
/// `docs/next-session-plan.md` #5): the stored `settings.locale` mapped to
/// a [Locale] for `MaterialApp.locale` (`lib/app/app.dart`), or `null` to
/// follow the OS locale.
///
/// An unrecognized stored value (future-proofing against a value this
/// build doesn't know) also maps to `null` rather than throwing, matching
/// `actingMemberProvider`'s "read-time self-heal, nothing written back"
/// approach to a stale/foreign stored value.
///
/// Watched unconditionally from `ChoreApp.build` (`lib/app/app.dart`) --
/// including while `bootstrapProvider` is still loading or has errored --
/// so this reads [settingsProvider] via `valueOrNull` rather than `value`:
/// the latter rethrows the underlying error when the watched provider
/// itself is in an `AsyncError` state (e.g. a broken database connection),
/// which would otherwise crash the loading/error screens this locale also
/// applies to.
final localeOverrideProvider = Provider<Locale?>((ref) {
  final stored = ref.watch(settingsProvider).valueOrNull?.locale;
  switch (stored) {
    case 'en':
      return const Locale('en');
    case 'de':
      return const Locale('de');
    default:
      return null;
  }
});

/// The manual theme override chosen via Settings (spec
/// `docs/feedback/2026-08-01-field-feedback.md` G2): the stored
/// `settings.themeMode` mapped to a [ThemeMode] for `MaterialApp.themeMode`
/// (`lib/app/app.dart`), or [ThemeMode.system] to follow the OS theme.
///
/// An unrecognized stored value (future-proofing against a value this build
/// doesn't know) also maps to [ThemeMode.system] rather than throwing,
/// matching [localeOverrideProvider]'s "read-time self-heal, nothing
/// written back" approach to a stale/foreign stored value.
///
/// Watched unconditionally from `ChoreApp.build` (`lib/app/app.dart`) --
/// including while `bootstrapProvider` is still loading or has errored --
/// so this reads [settingsProvider] via `valueOrNull` rather than `value`:
/// the latter rethrows the underlying error when the watched provider
/// itself is in an `AsyncError` state (e.g. a broken database connection),
/// which would otherwise crash the loading/error screens this theme also
/// applies to.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final stored = ref.watch(settingsProvider).valueOrNull?.themeMode;
  switch (stored) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});

/// The running app's package metadata (name, version, build number),
/// read once from the platform. Backs the Settings tab's About section
/// (spec `docs/next-session-plan.md` #5: version row, and the app version
/// passed to `showLicensePage`).
///
/// Widget tests never override this provider directly: `PackageInfo`
/// exposes its own test hook, `PackageInfo.setMockInitialValues(...)`,
/// which `PackageInfo.fromPlatform()` picks up automatically once called.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

/// The client-auth gateway backing the Settings tab's Account section
/// (spec `docs/specs/sync-backend.md` §5): the real [SupabaseAuthGateway]
/// when Supabase is configured ([supabaseConfigured]), else the
/// always-signed-out [NoopAuthGateway] -- keeping the app fully usable
/// offline (spec §0) when Supabase is absent (tests, E2E, and F-Droid
/// users who never sign in).
///
/// Widget tests override this directly with a fake (see
/// `test/features/settings/fake_auth_gateway.dart`) -- or with the
/// built-in [NoopAuthGateway] itself, to exercise the 'coming soon' state
/// deterministically -- on top of the two standard database/clock
/// overrides.
final authGatewayProvider = Provider<AuthGateway>((ref) {
  return supabaseConfigured
      ? const SupabaseAuthGateway()
      : const NoopAuthGateway();
});

/// The currently signed-in [AuthUser] per [authGatewayProvider]'s
/// [AuthGateway.watchUser] stream, or `null` while signed out (or always,
/// under [NoopAuthGateway]).
final currentAuthUserProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authGatewayProvider).watchUser();
});

/// The client-household gateway backing the P2b adopt flow (Settings'
/// Account section) and the Members screen's invite row (spec
/// `docs/specs/sync-backend.md` §7.2): the real [SupabaseHouseholdGateway]
/// when Supabase is configured ([supabaseConfigured]), else the
/// always-throwing [NoopHouseholdGateway] -- unreachable in practice
/// because every call site is gated on a signed-in user, which
/// [NoopAuthGateway] never produces.
///
/// Widget tests override this directly with a fake (see
/// `test/features/settings/fake_household_gateway.dart`) -- the fourth
/// provider override (alongside [appDatabaseProvider], [clockProvider], and
/// [authGatewayProvider]) that Settings/Members widget tests need.
final householdGatewayProvider = Provider<HouseholdGateway>((ref) {
  return supabaseConfigured
      ? const SupabaseHouseholdGateway()
      : const NoopHouseholdGateway();
});

/// Whether the signed-in caller's account is ALREADY a claimed member of
/// SOME household this DEVICE isn't currently linked to -- probed for the
/// Account section's P2d reconnect row (spec `docs/specs/sync-backend.md`
/// §7.6) via [HouseholdGateway.findMyMembership].
///
/// Returns `null` WITHOUT calling the gateway at all in either of two
/// cases: signed out (no [currentAuthUserProvider] user yet), or
/// [householdGatewayProvider] resolves to [NoopHouseholdGateway] (Supabase
/// unconfigured) -- both make the probe meaningless, and the second would
/// throw anyway. Otherwise resolves to the gateway's answer: a
/// [MyMembership] when this account is already a member elsewhere, else
/// `null`.
///
/// Watching [currentAuthUserProvider] directly (not `.future`) re-runs this
/// probe every time the auth state changes -- sign-in, sign-out, or the
/// initial resolve -- rather than only once.
final myMembershipProvider = FutureProvider<MyMembership?>((ref) async {
  final gateway = ref.watch(householdGatewayProvider);
  if (gateway is NoopHouseholdGateway) {
    return null;
  }
  final user = ref.watch(currentAuthUserProvider).valueOrNull;
  if (user == null) {
    return null;
  }
  return gateway.findMyMembership();
});

/// The P2b adopt-flow service (spec `docs/specs/sync-backend.md` §7.3),
/// built on [householdGatewayProvider], [householdRepositoryProvider], and
/// [settingsRepositoryProvider].
final householdLinkServiceProvider = Provider<HouseholdLinkService>((ref) {
  return HouseholdLinkService(
    gateway: ref.watch(householdGatewayProvider),
    households: ref.watch(householdRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

/// The P2c join-flow service (spec `docs/specs/sync-backend.md` §7.4), built
/// on [householdGatewayProvider], [appDatabaseProvider], and
/// [settingsRepositoryProvider].
final householdJoinServiceProvider = Provider<HouseholdJoinService>((ref) {
  return HouseholdJoinService(
    gateway: ref.watch(householdGatewayProvider),
    database: ref.watch(appDatabaseProvider),
    settings: ref.watch(settingsRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

/// The welcome screen's "Set up a new household" service (spec
/// `docs/specs/onboarding-v2.md` §1/§2), built on [householdRepositoryProvider],
/// [categoryRepositoryProvider], and [settingsRepositoryProvider].
final householdCreateServiceProvider = Provider<HouseholdCreateService>((ref) {
  return HouseholdCreateService(
    database: ref.watch(appDatabaseProvider),
    households: ref.watch(householdRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});

/// The transport [syncEngineProvider] hands a real [SupabaseSyncEngine]
/// (spec `docs/specs/sync-backend.md` §8.4) -- `null` means "Supabase isn't
/// configured", which forces [NoopSyncEngine] regardless of linked state.
///
/// Defaults to the real [SupabaseSyncTransport], gated on
/// [supabaseConfigured] (a compile-time constant that can't itself be
/// overridden in a test binary). This extra indirection is what lets a
/// bare-`ProviderContainer` test exercise [syncEngineProvider]'s OWN
/// linked-state branching for real: `syncTransportProvider.overrideWithValue
/// (fakeTransport)` (a non-null fake) makes the "linked" branch reachable
/// even though `--dart-define=SUPABASE_URL=` is always empty under
/// `flutter test` -- see `test/app/sync_engine_provider_test.dart`.
final syncTransportProvider = Provider<SyncTransport?>((ref) {
  return supabaseConfigured ? const SupabaseSyncTransport() : null;
});

/// The P3 ongoing sync engine (spec `docs/specs/sync-backend.md` §8.2): the
/// real [SupabaseSyncEngine] whenever [syncTransportProvider] is non-null
/// (Supabase configured) AND this device is linked (`syncHouseholdId` is
/// non-null) AND a user is currently signed in (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A5), else the inert
/// [NoopSyncEngine] -- which covers every widget test and E2E run (neither
/// ever configures Supabase), keeping the offline suite free of the
/// debounced-push timer and the realtime subscription
/// [SupabaseSyncEngine.start] arms.
///
/// **A5 (2026-08-01):** gating on linked state alone let a signed-out,
/// still-linked device spin forever on 401s (every push/pull silently
/// failing, per spec §8.3's swallow-everything failure posture) -- no data
/// harm, but battery/log noise, and Account section showed a bare sign-in
/// form with no hint the phone was still linked (see
/// `AccountSectionBody`'s `_SignedOutForm` hint, `lib/features/settings/
/// account_section.dart`). Fixed by also requiring
/// [currentAuthUserProvider] to resolve to a non-null user.
///
/// Re-evaluates on the linked state AND the auth state, per spec: whenever
/// `syncHouseholdId` changes (unlinked -> linked, or a join-flow's
/// household replace) OR the signed-in user changes (sign-in/sign-out),
/// Riverpod disposes the previous value -- calling [SyncEngine.stop] via
/// `ref.onDispose` below -- and builds a fresh one, which
/// [SyncEngine.start]s immediately (when both conditions now hold). This is
/// the entire "start()/stop() driven by linked+auth state" requirement;
/// [SyncEngineController] below only adds the app-resume trigger, mirroring
/// [CatchUpController].
///
/// **Live-repro'd bug (fixed 2026-08-01):** this MUST watch
/// `settingsProvider.select(...)` scoped to `syncHouseholdId` alone, never
/// the bare `settingsProvider` (the whole `DeviceSettings` row). A started
/// engine's own `pullSince` unconditionally writes
/// `settings.syncLastPulledAt` on every successful pull -- watching the
/// whole row turned that write into a feedback loop: the write re-emitted
/// `settingsProvider`, which rebuilt this provider (linked state
/// unchanged, but Riverpod only compares the WATCHED value, and an
/// unscoped watch sees every field), tearing down the just-started engine
/// (cancelling its debounce `Timer` and `db.tableUpdates()`/realtime
/// subscriptions) and replacing it with a brand-new one whose `start()`
/// immediately pulled again -- an infinite restart loop that never let a
/// debounced push survive to fire. `select` fixes it by only comparing the
/// projected `syncHouseholdId` value, which the pull's own write never
/// changes. **CRITICAL for the A5 gate above:** the same discipline
/// applies to the auth watch -- [currentAuthUserProvider] is watched
/// DIRECTLY (not the bare `authGatewayProvider`/some broader auth stream),
/// because its own emissions are already auth-state-only (it maps
/// `AuthGateway.watchUser()`, which only ever emits on sign-in/sign-out --
/// never as a side effect of anything the sync engine itself does). Watch
/// it, never the raw settings stream, and never anything coarser.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final transport = ref.watch(syncTransportProvider);
  final linkedHouseholdId = ref.watch(
    settingsProvider.select(
      (settings) => settings.valueOrNull?.syncHouseholdId,
    ),
  );
  final signedIn = ref.watch(currentAuthUserProvider).valueOrNull != null;
  if (transport == null || linkedHouseholdId == null || !signedIn) {
    return const NoopSyncEngine();
  }
  final engine = SupabaseSyncEngine(
    db: ref.watch(appDatabaseProvider),
    transport: transport,
    settings: ref.watch(settingsRepositoryProvider),
    householdId: linkedHouseholdId,
  )..start();
  ref.onDispose(engine.stop);
  return engine;
});

/// The bootstrap household's own row (currently just its `name`), kept in
/// sync with the database. Backs the Account section's 'linked' subtitle
/// (spec `docs/specs/sync-backend.md` §7.3 last paragraph), which names the
/// household once this device is linked.
final currentHouseholdProvider = StreamProvider<Household>((ref) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref.watch(householdRepositoryProvider).watchHousehold(householdId);
});

/// The OS-level notification plugin (or fake), wrapped by
/// [notificationSchedulerProvider].
///
/// Defaults to the real [FlutterLocalNotificationsAdapter]. Scheduler and
/// reschedule-on-mutation tests override this with a fake implementing
/// [DigestNotificationPlugin] so no real notification channel is ever
/// touched; see `test/application/fake_digest_notification_plugin.dart`.
final digestNotificationPluginProvider = Provider<DigestNotificationPlugin>((
  ref,
) {
  return FlutterLocalNotificationsAdapter();
});

/// The digest notification scheduler, built on
/// [digestNotificationPluginProvider].
final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return NotificationScheduler(
    plugin: ref.watch(digestNotificationPluginProvider),
  );
});

/// Whether the OS notification permission is currently granted, per the
/// last check performed by [DigestRescheduleController] (at bootstrap and
/// on app resume).
///
/// Defaults to `true` so the settings screen's permission-denied hint
/// doesn't flash on the very first frame, before that first check
/// resolves. Backed by a plain [StateProvider] (rather than a
/// [FutureProvider] re-read each time) specifically so widget tests can
/// override it directly to exercise the hint's visible/hidden states
/// without needing a real plugin call.
final notificationPermissionGrantedProvider = StateProvider<bool>(
  (ref) => true,
);

/// The chore lifecycle service, built on [appDatabaseProvider],
/// [choreRepositoryProvider], and [clockProvider].
final choreServiceProvider = Provider<ChoreService>((ref) {
  return ChoreService(
    database: ref.watch(appDatabaseProvider),
    chores: ref.watch(choreRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

/// The member-deletion service (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1), built on
/// [appDatabaseProvider], [choreRepositoryProvider], and [clockProvider] --
/// mirrors [choreServiceProvider]'s shape.
final memberServiceProvider = Provider<MemberService>((ref) {
  return MemberService(
    database: ref.watch(appDatabaseProvider),
    chores: ref.watch(choreRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Runs once at startup (once the welcome gate -- [householdGateProvider]
/// -- has already confirmed a household exists): seeds default categories
/// if somehow still missing, catches up any missed recurring occurrences,
/// auto-clears shopping items checked more than 24h ago, and resolves to
/// the household's id.
///
/// Spec `docs/specs/onboarding-v2.md` §2: this no longer CREATES the
/// household itself (that's [householdCreateServiceProvider]'s /
/// `HouseholdJoinService.joinFresh`'s job now, both explicit, user-chosen
/// actions on the welcome screen) -- it ASSUMES one exists, since `ChoreApp`
/// (`lib/app/app.dart`) only ever builds the subtree that reads this
/// provider once [householdGateProvider] has resolved to non-null. A `null`
/// household here is therefore a programming-bug-level surprise, not a
/// normal startup state, and throws rather than silently bootstrapping one
/// (the old lazy-create behavior the welcome gate spec explicitly retires).
///
/// The 24h shopping auto-clear (spec `docs/specs/ux-round-2.md` B4) uses
/// [clockProvider] so it stays deterministic under a fixed test/E2E clock.
///
/// Every screen that needs the household id (directly, or transitively via
/// [pendingOccurrencesProvider] / [membersProvider] /
/// [choreCategoriesProvider]) waits on this future first.
final bootstrapProvider = FutureProvider<String>((ref) async {
  // Gate-aware, not gate-ASSUMING (live-E2E regression, 2026-08-05):
  // main.dart's controllers (`catchUpControllerProvider` etc.) listen to
  // this provider BEFORE runApp -- on a fresh install that used to cache
  // a StateError here, which `_Bootstrapped` then dutifully displayed as
  // a startup-error screen right after the user created their household
  // on the welcome gate. Widget tests never caught it because they either
  // pre-seed a household or pump `ChoreApp` without main()'s controller
  // activation. Instead of throwing, park on the gate.
  //
  // The watch is SELECT-scoped to the household's ID -- the same
  // discipline `syncEngineProvider` documents for its linked-state watch:
  // the gate stream re-emits on EVERY households-row change (a RENAME
  // re-emits it too), and an unscoped watch would re-run this provider's
  // side effects on each of those. Only existence/identity transitions
  // matter here: null -> id (welcome create / join) and id -> other id
  // (join's household replace).
  final householdId = ref.watch(
    householdGateProvider.select((gate) => gate.valueOrNull?.id),
  );
  if (householdId == null) {
    // Pre-gate (or gate still loading): never resolve. The controllers
    // listening to this provider simply keep waiting; the id appearing
    // rebuilds this provider (the select above) and the fresh execution
    // resolves. Nothing ever awaits this future while the gate shows.
    return Completer<String>().future;
  }
  await ref.watch(categoryRepositoryProvider).seedDefaults(householdId);
  await ref.watch(choreServiceProvider).catchUpOverdue(householdId);
  final cutoffUtc = ref
      .watch(clockProvider)
      .now()
      .toUtc()
      .subtract(const Duration(hours: 24));
  await ref
      .watch(shoppingRepositoryProvider)
      .clearCheckedOlderThan(householdId, cutoffUtc: cutoffUtc);
  return householdId;
});

/// Pending chore occurrences of the bootstrap household, each joined with
/// its chore, category, and assigned member.
final pendingOccurrencesProvider = StreamProvider<List<OccurrenceWithChore>>((
  ref,
) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref
      .watch(choreRepositoryProvider)
      .watchPendingOccurrences(
        householdId,
      );
});

/// Occurrences of the bootstrap household closed (done or skipped) today,
/// each joined with its chore, category, assigned member, and completer.
///
/// Backs the chores list's collapsed 'Done today' section (spec
/// `docs/specs/ux-round-2.md` A3).
final closedTodayOccurrencesProvider =
    StreamProvider<List<ClosedOccurrenceWithChore>>((ref) async* {
      final householdId = await ref.watch(bootstrapProvider.future);
      final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());
      yield* ref
          .watch(choreRepositoryProvider)
          .watchClosedOnDate(householdId, today);
    });

/// Paused chores of the bootstrap household, each joined with its ordered
/// assignee ids and resolved category.
///
/// Backs the chores list's collapsed 'Paused' section (spec
/// `docs/specs/ux-round-2.md` A5). Built on [ChoreRepository.watchActiveChores]
/// (which already includes paused chores) rather than a new repository
/// query, since filtering down to the paused subset needs no SQL of its
/// own.
final pausedChoresProvider = StreamProvider<List<ChoreWithDetails>>((
  ref,
) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref
      .watch(choreRepositoryProvider)
      .watchActiveChores(householdId)
      .map(
        (chores) => [
          for (final details in chores)
            if (details.chore.pausedAt != null) details,
        ],
      );
});

/// Every member of the bootstrap household, ordered by creation time (see
/// `HouseholdRepository.watchMembers`).
final membersProvider = StreamProvider<List<Member>>((ref) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref.watch(householdRepositoryProvider).watchMembers(householdId);
});

/// Active chore categories of the bootstrap household.
final choreCategoriesProvider = StreamProvider<List<Category>>((ref) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref
      .watch(categoryRepositoryProvider)
      .watchCategories(householdId, CategoryKind.chore);
});

/// Every active shopping item of the bootstrap household, joined with its
/// resolved category, in [ShoppingRepository.watchActiveItems] order:
/// unchecked first, then by category sort order, then by name.
final shoppingItemsProvider = StreamProvider<List<ShoppingItemWithCategory>>((
  ref,
) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref.watch(shoppingRepositoryProvider).watchActiveItems(householdId);
});

/// Active shopping categories of the bootstrap household.
final shoppingCategoriesProvider = StreamProvider<List<Category>>((ref) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref
      .watch(categoryRepositoryProvider)
      .watchCategories(householdId, CategoryKind.shopping);
});

/// The member who acts on behalf of the user for single-user attribution
/// flows (completing an unassigned occurrence, `createdBy` on a new chore,
/// shopping `addedBy`), and the member the acting-member switcher (spec
/// `docs/specs/members-management.md` §4) shows as "current".
///
/// Resolution order, re-run every time [settingsProvider] or
/// [membersProvider] changes:
///
/// 1. `settings.actingMemberId`, if it matches a member in
///    [membersProvider]'s current list;
/// 2. otherwise the household's first admin member, else its first member.
///
/// `null` only while [membersProvider] hasn't loaded yet or has no members.
/// A stored id that doesn't resolve to a current member (cleared, or
/// dangling) silently falls through to the fallback — this is a read-time
/// self-heal, not a repair: nothing is written back to settings.
final actingMemberProvider = Provider<Member?>((ref) {
  final members = ref.watch(membersProvider).value;
  if (members == null || members.isEmpty) {
    return null;
  }
  final storedId = ref.watch(settingsProvider).value?.actingMemberId;
  if (storedId != null) {
    for (final member in members) {
      if (member.id == storedId) {
        return member;
      }
    }
  }
  return members.firstWhere(
    (member) => member.role == MemberRole.admin,
    orElse: () => members.first,
  );
});

/// Debounce delay collapsing bursts of digest-affecting mutations into a
/// single reschedule (spec `docs/specs/notifications.md` architecture #2).
const Duration digestRescheduleDebounce = Duration(milliseconds: 500);

/// Owns the digest notification's "reschedule on mutation" wiring (spec
/// `docs/specs/notifications.md` architecture #2).
///
/// Listens to [pendingOccurrencesProvider] and [settingsProvider] (any
/// occurrence/chore/settings mutation shows up through one of those two),
/// and to [bootstrapProvider] resolving once. [digestRescheduleDebounce]
/// after the last relevant change, rebuilds the digest's whole scheduling
/// horizon (`buildDigestPlans`, scoped to [actingMemberProvider]) for the
/// current [clockProvider] time and pushes all [digestHorizonDays] days of
/// it to [notificationSchedulerProvider] at once — scheduling the days that
/// have something to say and cancelling the days that don't. The horizon is
/// what makes the digest survive the app simply not being opened (spec
/// `docs/specs/notifications.md` architecture #2): every trigger this class
/// listens to requires a running app, so a single-slot schedule went
/// silent the morning after it fired.
///
/// [triggerRecompute] is also called directly by `main.dart`'s app-resume
/// observer: an OS lifecycle transition isn't itself a Riverpod-watchable
/// value, so that trigger can't be wired via [Ref.listen] like the other
/// two and needs an explicit external call instead.
///
/// Deliberately NOT read anywhere in the `lib/app`/`lib/features` widget
/// tree (`ChoreApp`, `AppShell`, screens): every widget test builds
/// `ChoreApp` directly, never through `main()`, and eagerly starting a real
/// debounced [Timer] as a side effect of building that tree would leave a
/// "Timer still pending" failure in every widget test that never touches
/// notifications at all. Production code activates this exclusively from
/// `main.dart`, before `runApp` — see that file.
class DigestRescheduleController {
  /// Starts listening immediately. The `ref` is retained for the lifetime
  /// of this controller (i.e. of the [ProviderContainer] that created it
  /// via [digestRescheduleControllerProvider]).
  DigestRescheduleController(this._ref) {
    _ref
      ..listen(bootstrapProvider, (previous, next) {
        if (next.hasValue) {
          unawaited(refreshPermissionState());
          triggerRecompute();
        }
      })
      ..listen(pendingOccurrencesProvider, (previous, next) {
        triggerRecompute();
      })
      ..listen(settingsProvider, (previous, next) {
        triggerRecompute();
      })
      // The digest is scoped to the acting member (triage T2.3), so a
      // change of who that is must re-count. Most such changes arrive via
      // `settingsProvider` (the stored id) — but a member being added,
      // renamed or removed can change `actingMemberProvider`'s fallback
      // resolution with no settings write at all.
      ..listen(actingMemberProvider, (previous, next) {
        triggerRecompute();
      });
  }

  final Ref _ref;
  Timer? _debounceTimer;

  /// Cancels any pending debounce timer. Called via `ref.onDispose` when
  /// the owning [ProviderContainer] is torn down.
  void dispose() => _debounceTimer?.cancel();

  /// (Re)starts the [digestRescheduleDebounce] timer; when it fires,
  /// recomputes the digest plan and (re)schedules or cancels it. Called by
  /// this controller's own listeners above, and externally on app resume.
  void triggerRecompute() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(digestRescheduleDebounce, _recompute);
  }

  /// Re-checks the OS notification permission immediately (no debounce:
  /// it's a cheap read with no OS side effect), updating
  /// [notificationPermissionGrantedProvider]. Called at bootstrap and
  /// externally on app resume — the two moments the spec calls out for
  /// re-checking the OS permission state.
  Future<void> refreshPermissionState() async {
    final granted = await _ref
        .read(digestNotificationPluginProvider)
        .isPermissionGranted();
    _ref.read(notificationPermissionGrantedProvider.notifier).state = granted;
  }

  Future<void> _recompute() async {
    final scheduler = _ref.read(notificationSchedulerProvider);
    await scheduler.ensureInitialized();

    final settings = _ref.read(settingsProvider).value;
    final pending = _ref.read(pendingOccurrencesProvider).value;
    if (settings == null || pending == null) {
      // Either stream hasn't emitted its first value yet; the `ref.listen`
      // callback that eventually delivers it calls [triggerRecompute]
      // again, so nothing is lost by bailing out here.
      return;
    }

    await scheduler.applyDigestPlans(
      buildDigestPlans(
        now: _ref.read(clockProvider).now(),
        settings: settings,
        pending: pending,
        recipientMemberId: _ref.read(actingMemberProvider)?.id,
      ),
    );
  }
}

/// Activates [DigestRescheduleController] the moment it's first read.
///
/// Read exactly once, from `main.dart`, before `runApp` — see the
/// controller's own doc comment for why it must never be read from inside
/// the widget tree.
final digestRescheduleControllerProvider = Provider<DigestRescheduleController>(
  (ref) {
    final controller = DigestRescheduleController(ref);
    ref.onDispose(controller.dispose);
    return controller;
  },
);

/// The next local-midnight moment strictly after [now], plus a 1-second
/// buffer past the exact boundary so a caller never treats "the day
/// changed" a fraction of a second before it actually has.
///
/// Built from calendar components — mirroring [nextDigestSlot]'s DST
/// rationale — rather than `now.add(const Duration(days: 1))`: the local
/// difference between two calendar days isn't always exactly 24 hours
/// across a daylight-saving transition, and Dart's `DateTime` constructor
/// already normalizes an out-of-range day into the correct following
/// month/year. Exposed as a top-level function (rather than inlined in
/// [CatchUpController]) so it's directly unit-testable, the same reason
/// [nextDigestSlot] is.
DateTime nextLocalMidnight(DateTime now) {
  return DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
}

/// Owns re-running [ChoreService.catchUpOverdue] on the two triggers spec
/// `docs/specs/polish-round-1.md` C1 calls out that [bootstrapProvider]
/// (which runs it once at startup) doesn't cover: the app resuming from
/// the background, and the local calendar day changing while the app stays
/// open.
///
/// Follows the same shape as [DigestRescheduleController], including why
/// it's only ever activated from `main.dart`: it arms a real day-change
/// [Timer] as a side effect of being read, and every widget test builds
/// `ChoreApp` directly (never through `main()`), so activating this from
/// inside the `lib/app`/`lib/features` widget tree would leave a "Timer
/// still pending" failure in every widget test that never touches this
/// controller at all.
///
/// A day-change timer is armed (via [nextLocalMidnight]) the moment
/// [bootstrapProvider] resolves (so the household id is known); firing it
/// re-runs catch-up and re-arms itself for the following midnight.
/// [triggerOnResume] is called directly by `main.dart`'s app-resume
/// observer — an OS lifecycle transition isn't itself a Riverpod-watchable
/// value, mirroring [DigestRescheduleController.triggerRecompute]'s own
/// external call site — and also re-arms the day-change timer from the
/// current time, since a backgrounded app's timers don't reliably fire on
/// schedule and could otherwise go stale.
///
/// Catch-up only triggers a digest recompute
/// ([DigestRescheduleController.triggerRecompute]) when
/// [ChoreService.catchUpOverdue] reports it actually changed something —
/// the common case (nothing overdue) has nothing new for the digest to
/// reflect.
class CatchUpController {
  /// Starts listening immediately; arms the first day-change timer once
  /// [bootstrapProvider] resolves. The `ref` is retained for the lifetime
  /// of this controller (i.e. of the [ProviderContainer] that created it
  /// via [catchUpControllerProvider]).
  CatchUpController(this._ref) {
    _ref.listen(bootstrapProvider, (previous, next) {
      final householdId = next.valueOrNull;
      if (householdId != null) {
        _householdId = householdId;
        _armDayChangeTimer();
      }
    });
  }

  final Ref _ref;

  /// The bootstrap household id, set once [bootstrapProvider] resolves.
  String? _householdId;
  Timer? _dayChangeTimer;

  /// Cancels the day-change timer. Called via `ref.onDispose` when the
  /// owning [ProviderContainer] is torn down.
  void dispose() => _dayChangeTimer?.cancel();

  /// Re-runs catch-up and re-arms the day-change timer from the current
  /// time. Called externally on app resume.
  void triggerOnResume() {
    unawaited(_runCatchUp());
    _armDayChangeTimer();
  }

  /// (Re)arms [_dayChangeTimer] to fire just past the next local midnight,
  /// per [nextLocalMidnight], then re-fire and re-arm again from there —
  /// this is what keeps catch-up running every day the app stays open.
  void _armDayChangeTimer() {
    _dayChangeTimer?.cancel();
    final now = _ref.read(clockProvider).now();
    _dayChangeTimer = Timer(nextLocalMidnight(now).difference(now), () {
      unawaited(_runCatchUp());
      _armDayChangeTimer();
    });
  }

  Future<void> _runCatchUp() async {
    final householdId = _householdId;
    if (householdId == null) {
      return;
    }
    final changed = await _ref
        .read(choreServiceProvider)
        .catchUpOverdue(householdId);
    if (changed) {
      _ref.read(digestRescheduleControllerProvider).triggerRecompute();
    }
  }
}

/// Activates [CatchUpController] the moment it's first read.
///
/// Read exactly once, from `main.dart`, before `runApp` — see the
/// controller's own doc comment for why it must never be read from inside
/// the widget tree.
final catchUpControllerProvider = Provider<CatchUpController>((ref) {
  final controller = CatchUpController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Owns the P3 sync engine's app-resume trigger (spec
/// `docs/specs/sync-backend.md` §8.3: "pull on ... app resume") --
/// REUSES the exact same lifecycle-observer pattern as [CatchUpController]/
/// [DigestRescheduleController] (`main.dart`'s single `_AppResumeObserver`
/// calls all three; no second `WidgetsBindingObserver` is added) rather than
/// owning start()/stop() itself: [syncEngineProvider] already does that
/// reactively (see its own doc comment) purely from Riverpod watching the
/// linked state, with no external trigger needed.
///
/// This controller's constructor only needs to keep [syncEngineProvider]
/// "alive" (subscribed) for the app's lifetime, exactly like
/// [CatchUpController]/[DigestRescheduleController] do for
/// [bootstrapProvider] -- so it reactively rebuilds (and restarts) on every
/// later linked-state change, not just the first one.
///
/// Deliberately NOT read anywhere in the `lib/app`/`lib/features` widget
/// tree, for the same reason as [CatchUpController]/
/// [DigestRescheduleController]: every widget test builds `ChoreApp`
/// directly (never through `main()`), so [syncEngineProvider] is simply
/// never constructed during a widget test at all (it always resolves to
/// [NoopSyncEngine] there anyway, per its own doc comment, but never even
/// building it is one less thing for a test to accidentally depend on).
class SyncEngineController {
  /// Starts listening immediately. The `ref` is retained for the lifetime
  /// of this controller (i.e. of the [ProviderContainer] that created it
  /// via [syncEngineControllerProvider]).
  SyncEngineController(this._ref) {
    _ref.listen(syncEngineProvider, (previous, next) {
      // Nothing to do here: `syncEngineProvider`'s own body already
      // start()s the new engine and (via `ref.onDispose`) stop()s the
      // previous one. This listener exists purely to keep the provider
      // subscribed -- see the class doc comment.
    }, fireImmediately: true);
  }

  final Ref _ref;

  /// Triggers a push (which itself pulls afterward on success) on the
  /// CURRENTLY active engine. Called externally on app resume -- mirrors
  /// [CatchUpController.triggerOnResume]/
  /// [DigestRescheduleController.triggerRecompute]'s external call site.
  ///
  /// `pushDirty`, not a bare `pullSince`: spec §8.3 lists app resume as a
  /// PUSH trigger too ("push on: any local write while linked (debounced
  /// ~2s), app resume, reconnect"), not just a pull trigger -- a write
  /// made just before backgrounding may never have gotten a chance to push
  /// (the OS can suspend/kill the debounce `Timer`), so resume must also
  /// recover it, not only fetch what changed remotely.
  void triggerOnResume() {
    unawaited(_ref.read(syncEngineProvider).pushDirty());
  }

  /// Suspends the CURRENTLY active engine's foreground safety-net poll when
  /// the app leaves the screen (spec `docs/specs/sync-freshness.md` §2.2).
  void pauseBackgroundWork() {
    _ref.read(syncEngineProvider).pauseBackgroundWork();
  }

  /// Resumes what [pauseBackgroundWork] suspended, on app resume.
  void resumeBackgroundWork() {
    _ref.read(syncEngineProvider).resumeBackgroundWork();
  }
}

/// Activates [SyncEngineController] the moment it's first read.
///
/// Read exactly once, from `main.dart`, before `runApp` — the same place
/// [catchUpControllerProvider]/[digestRescheduleControllerProvider] are
/// read; see [SyncEngineController]'s own doc comment for why it must never
/// be read from inside the widget tree.
final syncEngineControllerProvider = Provider<SyncEngineController>((ref) {
  return SyncEngineController(ref);
});
