/// The shared "mark dirty" write-time value (spec
/// `docs/specs/sync-backend.md` §8.1): every repository insert/update of a
/// synced row (households, members, categories, chores, chore_assignees,
/// chore_occurrences, shopping_items -- see `SyncDirtyColumn` in
/// `lib/data/db/tables.dart`) includes `syncDirty: syncDirtyOnWrite` in its
/// companion, exactly like every write already includes an `updatedAt:
/// Value(_isoNow())`.
///
/// A single shared constant (rather than each call site writing its own
/// `Value(true)` literal) is the "shared drift helper" the spec calls for:
/// one grep-able source of truth for what marks a row dirty, so a future
/// change to this behavior (or an audit of which sites use it) has exactly
/// one definition to find. The flag is set unconditionally -- also while
/// unlinked or signed out, since it's meaningless until linked but cheap to
/// keep accurate, and makes "link later" push everything that changed.
///
/// The ONLY writers that ever clear it (set `false`) are the P3 sync
/// engine's post-push confirmation (`SyncRepository`'s `clear*Dirty`
/// methods) and its pull's row-replace (the row mappers in
/// `lib/data/sync/row_mappers.dart`, which build freshly-pulled rows with
/// `syncDirty: false`) -- never a repository write site.
library;

import 'package:drift/drift.dart';

/// Written into every synced-table repository insert/update's companion.
/// See this library's doc comment.
const Value<bool> syncDirtyOnWrite = Value(true);
