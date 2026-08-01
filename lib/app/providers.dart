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
library;

import 'dart:async';

import 'package:chore_app/app/supabase_config.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/application/household_link_service.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
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

/// Runs once at startup: ensures the local household exists, seeds its
/// default categories, catches up any missed recurring occurrences,
/// auto-clears shopping items checked more than 24h ago, and resolves to
/// that household's id.
///
/// The 24h shopping auto-clear (spec `docs/specs/ux-round-2.md` B4) uses
/// [clockProvider] so it stays deterministic under a fixed test/E2E clock.
///
/// Every screen that needs the household id (directly, or transitively via
/// [pendingOccurrencesProvider] / [membersProvider] /
/// [choreCategoriesProvider]) waits on this future first.
final bootstrapProvider = FutureProvider<String>((ref) async {
  final household = await ref
      .watch(householdRepositoryProvider)
      .ensureLocalHousehold();
  await ref.watch(categoryRepositoryProvider).seedDefaults(household.id);
  await ref.watch(choreServiceProvider).catchUpOverdue(household.id);
  final cutoffUtc = ref
      .watch(clockProvider)
      .now()
      .toUtc()
      .subtract(const Duration(hours: 24));
  await ref
      .watch(shoppingRepositoryProvider)
      .clearCheckedOlderThan(household.id, cutoffUtc: cutoffUtc);
  return household.id;
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
/// after the last relevant change, recomputes the [DigestPlan] for the
/// current [clockProvider] time and pushes it to
/// [notificationSchedulerProvider] — scheduling or cancelling the digest
/// notification as appropriate.
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

    final now = _ref.read(clockProvider).now();
    final slotDate = PlainDate.fromDateTime(
      nextDigestSlot(now: now, digestMinutes: settings.digestMinutes),
    );
    var dueTodayCount = 0;
    var overdueCount = 0;
    for (final occurrence in pending) {
      final dueDate = occurrence.occurrence.dueDate;
      if (dueDate == slotDate) {
        dueTodayCount++;
      } else if (dueDate.isBefore(slotDate)) {
        overdueCount++;
      }
    }

    final plan = planDigest(
      now: now,
      digestMinutes: settings.digestMinutes,
      enabled: settings.digestEnabled,
      dueTodayCount: dueTodayCount,
      overdueCount: overdueCount,
    );
    if (plan == null) {
      await scheduler.cancelDigest();
    } else {
      await scheduler.scheduleDigest(plan);
    }
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
