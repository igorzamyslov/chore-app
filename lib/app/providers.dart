/// Riverpod wiring: database, repositories, service, clock, and bootstrap.
///
/// `appDatabaseProvider` and `clockProvider` are the only two providers ever
/// overridden by a test or E2E run; every other provider is built on top of
/// them, so overriding just those two is enough to make the whole app
/// deterministic and hermetic (in-memory database, fixed clock).
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// default categories, catches up any missed recurring occurrences, and
/// resolves to that household's id.
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

/// Every member of the bootstrap household, ordered by name.
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

/// The member who acts on behalf of the user for v1's single-user flows
/// (completing an unassigned occurrence, `createdBy` on a new chore): the
/// household's first admin member, or `null` while [membersProvider] hasn't
/// loaded yet or has no members.
///
/// Proper member switching (choosing which household member "you" are) is
/// out of scope for v1.
final actingMemberProvider = Provider<Member?>((ref) {
  final members = ref.watch(membersProvider).value;
  if (members == null || members.isEmpty) {
    return null;
  }
  return members.firstWhere(
    (member) => member.role == MemberRole.admin,
    orElse: () => members.first,
  );
});
