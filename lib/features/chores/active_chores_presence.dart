/// Whether the bootstrap household has ANY active (non-deleted) chore at
/// all, regardless of its current pending/paused/done-today state.
///
/// Backs two independent pieces of first-run UI (spec
/// `docs/specs/polish-round-1.md`): A1's fresh-install-vs-all-done empty
/// state distinction, and A3's "at least one chore exists" gate for the
/// digest pre-prompt banner. Both need a stronger signal than "any pending
/// occurrence right now" — e.g. a one-off chore completed days ago has zero
/// currently-visible trace (not pending, not paused, not closed *today*)
/// but the household is clearly no longer a fresh install.
///
/// Deliberately NOT added to `lib/app/providers.dart` (owned by a different
/// work stream in this round) — built directly on the existing
/// [choreRepositoryProvider] and [bootstrapProvider] instead, scoped to the
/// chores feature that's the only consumer.
library;

import 'package:chore_app/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` once the bootstrap household has at least one active
/// (non-deleted) chore, `false` while it has none.
final hasActiveChoresProvider = StreamProvider<bool>((ref) async* {
  final householdId = await ref.watch(bootstrapProvider.future);
  yield* ref
      .watch(choreRepositoryProvider)
      .watchActiveChores(householdId)
      .map((chores) => chores.isNotEmpty);
});
