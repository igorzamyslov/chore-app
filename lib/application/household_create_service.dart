/// The welcome screen's "Set up a new household" action (spec
/// `docs/specs/onboarding-v2.md` §1/§2), run from the inline create form in
/// `lib/features/onboarding/welcome_screen.dart`.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';

/// Composes [HouseholdRepository.createLocalHousehold] with the two other
/// side effects the welcome-create action needs (spec §2: "creates the
/// household + ONE admin member named `name` + marks the name-prompt flag
/// + seeds default categories, all in one transaction where feasible"):
/// default category seeding ([CategoryRepository.seedDefaults], reusing the
/// exact same seed set every upgrading install already gets from
/// `bootstrapProvider`) and marking `onboardingNamePromptShownAt`
/// ([SettingsRepository.markOnboardingNamePromptShown]) -- the onboarding
/// name banner is dead on arrival for this path since the member's name was
/// just typed in, so it must never appear afterwards.
///
/// Kept as its own small application-layer service (mirroring
/// `HouseholdJoinService`/`HouseholdLinkService`'s shape) rather than
/// folded into [HouseholdRepository] itself: [HouseholdRepository] stays a
/// household+member repository, and this is the one caller that needs to
/// orchestrate it together with [CategoryRepository] and
/// [SettingsRepository] -- exactly the kind of multi-repository flow those
/// other application-layer services already exist for.
class HouseholdCreateService {
  /// Creates the service.
  HouseholdCreateService({
    required this.database,
    required this.households,
    required this.categories,
    required this.settings,
  });

  /// The database every step below runs against, inside one outer
  /// transaction (drift nests [HouseholdRepository.createLocalHousehold]'s
  /// own transaction as a savepoint of it).
  final AppDatabase database;

  /// Creates the household + admin member.
  final HouseholdRepository households;

  /// Seeds default categories once the household exists.
  final CategoryRepository categories;

  /// Marks the onboarding name-prompt flag as already handled.
  final SettingsRepository settings;

  /// Creates the household with a single admin member named [name], seeds
  /// its default categories, and marks the onboarding name-prompt flag,
  /// all in one transaction. Resolves to the new household's id.
  Future<String> create(String name) {
    return database.transaction(() async {
      final household = await households.createLocalHousehold(name);
      await categories.seedDefaults(household.id);
      await settings.markOnboardingNamePromptShown();
      return household.id;
    });
  }
}
