# Category-delete impact count — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before the irreversible tap, the category delete-confirmation
dialog states how many chores or shopping items reference the category, and
what happens to them, truthfully.

**Architecture:** `CategoryRepository` gains one new read method,
`countActiveReferences(id, kind)`, that mirrors the exact `WHERE` clause
`softDeleteCategory` already uses to detach rows — so the number shown can
never drift from what the delete actually does. The call site
(`category_edit_sheet.dart`'s `_delete()`) awaits that count *before* calling
`showCategoryDeleteDialog`, so the dialog itself stays a plain,
fully-resolved data-in widget like the other three delete dialogs in this
codebase — no async state inside `AlertDialog.builder`. Four new ARB keys
(chore/shopping × zero/non-zero, the non-zero pair using ICU plural) replace
the single generic body string.

**Tech Stack:** Flutter, Riverpod, drift (SQLite), gen_l10n (ARB), the
existing `testChoreApp` integration-test harness (real in-memory
`AppDatabase`, fixed `clockProvider`).

## Global Constraints

- Every user-visible string goes through gen_l10n (`app_en.arb` template +
  `app_de.arb`, German du-form). No inline English, no string concatenation
  across word-order-sensitive boundaries.
- The counted message needs ICU plurals in **both** locales.
- Every interactive widget gets a stable id via `semantic()`.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  `clockProvider`, overriding only `appDatabaseProvider` and `clockProvider`.
  Never mock repositories or services.
- Never await a drift stream outside a widget pump; never bare-await
  `bootstrapProvider.future` in a `ProviderContainer` test;
  `tester.pump(small duration)` between `container.dispose()` and
  `database.close()` (not relevant here — no container test is added, but
  keep it in mind if one is).
- Strict lints (very_good_analysis, `--fatal-infos`); public members need
  doc comments.
- TDD: write-failing-test → run → implement → run → commit.
- The dialog must not run SQL — all counting logic lives in the repository.
- After editing `app_en.arb`/`app_de.arb`, regenerate localizations
  (`flutter gen-l10n`) before compiling — the generated files under
  `lib/l10n/app_localizations*.dart` are checked into this repo, so the
  regenerated output must be committed too.

## Analysis (for context — do not re-derive)

**What `softDeleteCategory` actually does today**
(`lib/data/repositories/category_repository.dart:171-204`): in one
transaction it (1) soft-deletes the category row, (2) clears `categoryId`
(sets it to `NULL`) on every **active** (`deletedAt IS NULL`) chore that
referenced it, (3) does the same for every active shopping item. Nothing is
deleted or hidden except the category itself — referencing rows survive and
become uncategorized. The **current** dialog body
(`categoryDeleteDialogBody`, `app_en.arb:1000`) already says this correctly
("Chores and items using it become uncategorized") — T1.2's "promise with no
mechanism" problem does **not** apply here; the only gap is the missing
count. This plan does not change the truthfulness of the copy, only adds the
number and makes the noun kind-specific.

**What a single category can be attached to**
(`lib/data/db/tables.dart:37,169-178,302-320,423-453`): `Categories.kind` is
a `CategoryKind` (`chore` or `shopping`), fixed at creation
(`category_edit_sheet.dart` passes `widget.kind` into `createCategory` and
never changes it). `Chores.categoryId` and `ShoppingItems.categoryId` are
both nullable FKs to `Categories`, but by construction a chore-kind category
is only ever offered in the chore form's category picker and a
shopping-kind category only in the shopping item's
(`shopping_edit_sheet.dart:122` passes `CategoryKind.shopping`; the chore
form's category field is scoped to `CategoryKind.chore` the same way). So a
single category is, in practice, referenced by **exactly one** of the two
tables depending on its `kind` — never both. The counting query and the
copy must be kind-specific, not "chores and items" generically.

**Where the counting query lives — approaches considered**

1. **New `CategoryRepository` method, direct `db.select` on
   `db.chores`/`db.shoppingItems` (chosen).** `CategoryRepository` already
   reaches into both tables directly inside `softDeleteCategory` itself
   (`category_repository.dart:183-202`) — this is the codebase's existing
   precedent for "category-domain logic that touches the referencing
   tables lives in `CategoryRepository`," not in `ChoreRepository` /
   `ShoppingRepository`. Keeping the count here also makes it trivial to
   keep the `WHERE` clause byte-for-byte in sync with the delete itself.
2. **Add a `countByCategory` method to each of `ChoreRepository` and
   `ShoppingRepository`, called from the UI layer.** Rejected: doubles the
   surface area for one read, and the UI would need its own kind-switch to
   pick which repo to call — logic that `CategoryRepository` can hide
   behind one method taking `kind`.
3. **A drift `count()` aggregate query instead of `.get().length`.**
   Rejected for this change: `_activeCount` (the existing, closely-related
   method two lines above where the new one will go,
   `category_repository.dart:289-299`) already uses `.get()` then
   `.length` rather than a SQL `COUNT`, at the same table scale (one
   household's chores/items — never large). Matching that local convention
   beats introducing a second query style for the same kind of read.

**How the dialog loads the count — approaches considered**

1. **Pre-fetch before calling `showDialog` (chosen).** `_delete()` in
   `category_edit_sheet.dart` is already `async` and already awaits
   `softDeleteCategory` after the dialog resolves; awaiting one more local,
   near-instant `SELECT` before opening the dialog costs nothing
   perceptible and keeps `showCategoryDeleteDialog` a plain function that
   takes fully-resolved data — exactly like `showMemberDeleteDialog` and
   `showChoreDeleteDialog`, the two existing precedents named in this
   ticket. No new async/loading state inside an `AlertDialog.builder`.
2. **Async dialog body (`FutureBuilder` inside `AlertDialog`, showing a
   spinner then the count).** Rejected: introduces a loading flicker into a
   destructive-confirm dialog, which no dialog in this app does today, and
   design-language.md rule 6 reserves spinners for "initial load" — a
   modal confirm opening already-resolved is the calmer read. Also adds
   test complexity (pumping through a loading frame) for a query with no
   perceptible latency.
3. **Reactive `StreamProvider` watched by the dialog.** Rejected: massive
   overkill for a one-shot confirm the user sees for a few seconds: no
   value in reacting to another device's concurrent chore edits while this
   dialog happens to be open.

No product decision is required here — all of the above is fully derivable
from the existing code and the design-language spec's dialog rules ("body =
one line of specifics").

## Open product decisions

None. Everything the copy needs to say is either fixed by what
`softDeleteCategory` actually does (derived from code) or fixed by matching
this codebase's existing dialog conventions (derived from precedent).

## File map

- Modify `lib/data/repositories/category_repository.dart` — add
  `countActiveReferences(String id, CategoryKind kind)`.
- Modify `test/data/repositories/category_repository_test.dart` — unit
  tests for the new method.
- Modify `lib/l10n/app_en.arb` — replace `categoryDeleteDialogBody` with
  four new keys (see Task 2).
- Modify `lib/l10n/app_de.arb` — same four keys, German du-form.
- Regenerate `lib/l10n/app_localizations.dart`,
  `lib/l10n/app_localizations_en.dart`, `lib/l10n/app_localizations_de.dart`
  (`flutter gen-l10n`) — do not hand-edit these.
- Modify `lib/features/settings/category_delete_dialog.dart` — new required
  `kind` and `referenceCount` params, message selection logic.
- Modify `lib/features/settings/category_edit_sheet.dart` — `_delete()`
  fetches the count before calling `showCategoryDeleteDialog`.
- Modify `test/features/settings/category_delete_test.dart` — extend the
  existing integration test to cover zero/one/many for both category kinds.
- Modify `docs/backlog.md` — close out **B-2** in the "Closed since..." line
  at the top, once the above lands and tests pass.

---

## Task 1: `CategoryRepository.countActiveReferences`

**Files:**
- Modify: `lib/data/repositories/category_repository.dart`
- Test: `test/data/repositories/category_repository_test.dart`

**Interfaces:**
- Produces: `Future<int> CategoryRepository.countActiveReferences(String id, CategoryKind kind)` —
  for `CategoryKind.chore`, counts active (`deletedAt IS NULL`) rows in
  `db.chores` with `categoryId == id`; for `CategoryKind.shopping`, the same
  over `db.shoppingItems`. Consumed by Task 4.

- [ ] **Step 1: Write the failing tests**

Add a new group to `test/data/repositories/category_repository_test.dart`,
after the existing `group('softDeleteCategory', ...)` block (before
`group('reorderCategories', ...)`):

```dart
  group('countActiveReferences', () {
    test('counts only active chores for a chore-kind category', () async {
      final category = await repo.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'Cleaning',
        icon: 'a',
        color: 1,
      );
      final choreRepo = ChoreRepository(
        db,
        newId: _IdGen().call,
        nowUtc: _fixedNow,
      );
      await choreRepo.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        categoryId: category.id,
      );
      final dust = await choreRepo.createChore(
        householdId: householdId,
        title: 'Dust',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        categoryId: category.id,
      );
      await choreRepo.softDeleteChore(dust.id);

      final count = await repo.countActiveReferences(
        category.id,
        CategoryKind.chore,
      );

      expect(count, 1);
    });

    test('counts only active shopping items for a shopping-kind category', (
      () async {
        final category = await repo.createCategory(
          householdId,
          kind: CategoryKind.shopping,
          name: 'Dairy',
          icon: 'a',
          color: 1,
        );
        final shoppingRepo = ShoppingRepository(
          db,
          newId: _IdGen().call,
          nowUtc: _fixedNow,
        );
        await shoppingRepo.addItem(
          householdId,
          name: 'Milk',
          categoryId: category.id,
        );
        final eggs = await shoppingRepo.addItem(
          householdId,
          name: 'Eggs',
          categoryId: category.id,
        );
        await shoppingRepo.deleteItem(eggs.id);

        final count = await repo.countActiveReferences(
          category.id,
          CategoryKind.shopping,
        );

        expect(count, 1);
      }),
    );

    test('returns 0 for a category nothing references', () async {
      final category = await repo.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'Unused',
        icon: 'a',
        color: 1,
      );

      final count = await repo.countActiveReferences(
        category.id,
        CategoryKind.chore,
      );

      expect(count, 0);
    });
  });
```

Before running, check the exact soft-delete method names on
`ChoreRepository` and `ShoppingRepository` — this plan assumes
`choreRepo.softDeleteChore(id)` and `shoppingRepo.deleteItem(id)`. Grep
first:

```bash
grep -n "Future<void> softDelete\|Future<void> delete" \
  lib/data/repositories/chore_repository.dart \
  lib/data/repositories/shopping_repository.dart
```

Adjust the two test bodies above to the real method names before running if
they differ from the assumption.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/repositories/category_repository_test.dart`
Expected: FAIL — `countActiveReferences` is not defined on
`CategoryRepository`.

- [ ] **Step 3: Implement `countActiveReferences`**

In `lib/data/repositories/category_repository.dart`, add this method right
after `softDeleteCategory` (before `reorderCategories`, so it sits next to
the method whose `WHERE` clauses it mirrors):

```dart
  /// Counts the active chores or shopping items — whichever [kind] matches
  /// — that currently reference category [id].
  ///
  /// Mirrors the exact `WHERE` clause [softDeleteCategory] uses to detach
  /// rows from a deleted category, so this number always matches what a
  /// delete will actually affect. Used by the delete-confirmation dialog to
  /// state the blast radius before the irreversible tap.
  Future<int> countActiveReferences(String id, CategoryKind kind) async {
    switch (kind) {
      case CategoryKind.chore:
        final rows =
            await (db.select(db.chores)..where(
                  (tbl) => tbl.categoryId.equals(id) & tbl.deletedAt.isNull(),
                ))
                .get();
        return rows.length;
      case CategoryKind.shopping:
        final rows =
            await (db.select(db.shoppingItems)..where(
                  (tbl) => tbl.categoryId.equals(id) & tbl.deletedAt.isNull(),
                ))
                .get();
        return rows.length;
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/category_repository_test.dart`
Expected: PASS (all groups, including the three new tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/category_repository.dart \
  test/data/repositories/category_repository_test.dart
git commit -m "Add CategoryRepository.countActiveReferences"
```

---

## Task 2: ARB copy — four new keys, ICU plural, both locales

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

**Interfaces:**
- Produces (after `flutter gen-l10n` in Task 3): four generated getters/
  methods on `AppLocalizations` —
  `String categoryDeleteDialogBodyChoresZero(String categoryName)`,
  `String categoryDeleteDialogBodyChoresCount(String categoryName, int count)`,
  `String categoryDeleteDialogBodyShoppingZero(String categoryName)`,
  `String categoryDeleteDialogBodyShoppingCount(String categoryName, int count)`.
  Consumed by Task 3.

- [ ] **Step 1: Remove the old key, add the four new ones, in `app_en.arb`**

In `lib/l10n/app_en.arb`, replace the `categoryDeleteDialogBody` entry
(currently lines 1000-1009) with:

```json
  "categoryDeleteDialogBodyChoresZero": "This deletes '{categoryName}'. No chores use it right now.",
  "@categoryDeleteDialogBodyChoresZero": {
    "description": "Body of the category delete-confirmation dialog for a chore-kind category that no active chore currently references.",
    "placeholders": {
      "categoryName": {
        "type": "String",
        "example": "Cleaning"
      }
    }
  },
  "categoryDeleteDialogBodyChoresCount": "{count, plural, one{This deletes '{categoryName}'. 1 chore uses it and will become uncategorized.} other{This deletes '{categoryName}'. {count} chores use it and will become uncategorized.}}",
  "@categoryDeleteDialogBodyChoresCount": {
    "description": "Body of the category delete-confirmation dialog for a chore-kind category currently referenced by at least one active chore.",
    "placeholders": {
      "categoryName": {
        "type": "String",
        "example": "Cleaning"
      },
      "count": {
        "type": "int",
        "example": "3"
      }
    }
  },
  "categoryDeleteDialogBodyShoppingZero": "This deletes '{categoryName}'. No shopping items use it right now.",
  "@categoryDeleteDialogBodyShoppingZero": {
    "description": "Body of the category delete-confirmation dialog for a shopping-kind category that no active shopping item currently references.",
    "placeholders": {
      "categoryName": {
        "type": "String",
        "example": "Dairy"
      }
    }
  },
  "categoryDeleteDialogBodyShoppingCount": "{count, plural, one{This deletes '{categoryName}'. 1 shopping item uses it and will become uncategorized.} other{This deletes '{categoryName}'. {count} shopping items use it and will become uncategorized.}}",
  "@categoryDeleteDialogBodyShoppingCount": {
    "description": "Body of the category delete-confirmation dialog for a shopping-kind category currently referenced by at least one active shopping item.",
    "placeholders": {
      "categoryName": {
        "type": "String",
        "example": "Dairy"
      },
      "count": {
        "type": "int",
        "example": "5"
      }
    }
  },
```

Keep `categoryDeleteDialogTitle` unchanged — only the body is being split.

- [ ] **Step 2: Same four keys, German du-form, in `app_de.arb`**

In `lib/l10n/app_de.arb`, replace the `categoryDeleteDialogBody` entry
(currently line 222) with:

```json
  "categoryDeleteDialogBodyChoresZero": "Damit löschst du '{categoryName}'. Sie wird gerade von keiner Aufgabe verwendet.",
  "categoryDeleteDialogBodyChoresCount": "{count, plural, one{Damit löschst du '{categoryName}'. 1 Aufgabe verwendet sie noch und wird danach unkategorisiert.} other{Damit löschst du '{categoryName}'. {count} Aufgaben verwenden sie noch und werden danach unkategorisiert.}}",
  "categoryDeleteDialogBodyShoppingZero": "Damit löschst du '{categoryName}'. Sie wird gerade von keinem Artikel verwendet.",
  "categoryDeleteDialogBodyShoppingCount": "{count, plural, one{Damit löschst du '{categoryName}'. 1 Artikel verwendet sie noch und wird danach unkategorisiert.} other{Damit löschst du '{categoryName}'. {count} Artikel verwenden sie noch und werden danach unkategorisiert.}}",
```

No `@`-metadata blocks needed in `app_de.arb` — this file only carries
translated strings, matching every other entry in it.

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: no errors; `lib/l10n/app_localizations.dart`,
`app_localizations_en.dart`, and `app_localizations_de.dart` are rewritten
with the four new members and `categoryDeleteDialogBody` removed from all
three.

- [ ] **Step 4: Confirm nothing else still references the removed key**

Run: `grep -rn "categoryDeleteDialogBody\b" lib/ test/`
Expected: no matches (the old key had no trailing suffix, so this must come
back empty once Task 3 also updates `category_delete_dialog.dart` — if this
step is run before Task 3, one match in
`lib/features/settings/category_delete_dialog.dart` is expected and fine to
leave for Task 3 to fix).

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb \
  lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart \
  lib/l10n/app_localizations_de.dart
git commit -m "Split category-delete body copy into kind/count-aware ARB keys"
```

---

## Task 3: `showCategoryDeleteDialog` takes `kind` + `referenceCount`

**Files:**
- Modify: `lib/features/settings/category_delete_dialog.dart`
- Test: `test/features/settings/category_delete_test.dart`

**Interfaces:**
- Consumes: the four `AppLocalizations` members from Task 2.
- Produces: `Future<bool> showCategoryDeleteDialog(BuildContext context, {required String categoryName, required CategoryKind kind, required int referenceCount})` —
  the two new named params are both required. Consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/settings/category_delete_test.dart` (new
`import 'package:chore_app/data/repositories/shopping_repository.dart';`
needed alongside the existing imports). Add it as a second top-level test in
the same file, after the existing one:

```dart
  testChoreApp(
    'delete: body names the exact count and reads differently at zero',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final choreCategories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = choreCategories.firstWhere((c) => c.name == 'Cleaning');

      // Zero case: nothing references 'Cleaning' yet.
      await openManageCategories(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("This deletes 'Cleaning'. No chores use it right now."),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.cancel'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();

      // Attach one chore, then re-open: singular non-zero wording.
      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      await choreService.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate.fromDateTime(today),
        assignmentMode: AssignmentMode.anyone,
        categoryId: cleaning.id,
      );
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This deletes 'Cleaning'. 1 chore uses it and will become "
          'uncategorized.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/category_delete_test.dart`
Expected: FAIL — the dialog still shows the old single-body text and/or
`showCategoryDeleteDialog` doesn't yet require `kind`/`referenceCount`
(compile error at this stage is also an acceptable failure — Task 4 hasn't
wired the call site yet, so treat any failure here as expected until Tasks
3+4 both land; if the harness won't compile at all because
`category_edit_sheet.dart` doesn't pass the new required params yet, do
Step 3 of this task and Task 4 together before re-running).

- [ ] **Step 3: Implement the new dialog signature**

Replace the full contents of `lib/features/settings/category_delete_dialog.dart`:

```dart
/// The delete-confirmation dialog for a category.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for deleting the category named
/// [categoryName], resolving to whether the user confirmed (defaults to
/// `false` if dismissed).
///
/// Deleting a category detaches it from every active chore/shopping item
/// that references it (they become uncategorized) — costly enough to
/// confirm, per `docs/specs/design-language.md` rule 3. [kind] picks
/// chore-worded or shopping-worded copy (a category only ever references
/// one or the other); [referenceCount] must already be resolved by the
/// caller — this dialog never queries the database itself — and is the
/// exact number of active rows the delete will detach, per
/// `CategoryRepository.countActiveReferences`. `referenceCount == 0` reads
/// as a distinct, lower-stakes sentence rather than a "0 chores" plural.
Future<bool> showCategoryDeleteDialog(
  BuildContext context, {
  required String categoryName,
  required CategoryKind kind,
  required int referenceCount,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      final body = switch ((kind, referenceCount)) {
        (CategoryKind.chore, 0) => l10n.categoryDeleteDialogBodyChoresZero(
          categoryName,
        ),
        (CategoryKind.chore, final count) =>
          l10n.categoryDeleteDialogBodyChoresCount(categoryName, count),
        (CategoryKind.shopping, 0) =>
          l10n.categoryDeleteDialogBodyShoppingZero(categoryName),
        (CategoryKind.shopping, final count) =>
          l10n.categoryDeleteDialogBodyShoppingCount(categoryName, count),
      };
      return AlertDialog(
        title: Text(l10n.categoryDeleteDialogTitle),
        content: Text(body),
        actions: [
          semantic(
            'settings.categories.delete.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'settings.categories.delete.confirm',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.commonDelete),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
```

- [ ] **Step 4: Run test to verify it passes**

This test also needs Task 4's call-site change to compile and pass (the
sheet must actually pass `kind`/`referenceCount` into the dialog) — do not
expect green until Task 4, Step 3 is also done. Once both are in place, run:
`flutter test test/features/settings/category_delete_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit together with Task 4 (they form one working change) — see Task 4,
Step 5.

---

## Task 4: Wire the call site — fetch the count before showing the dialog

**Files:**
- Modify: `lib/features/settings/category_edit_sheet.dart`

**Interfaces:**
- Consumes: `CategoryRepository.countActiveReferences` (Task 1),
  `showCategoryDeleteDialog`'s new signature (Task 3).

- [ ] **Step 1: Update `_delete()`**

In `lib/features/settings/category_edit_sheet.dart`, replace the existing
`_delete()` method (currently lines 196-213) with:

```dart
  Future<void> _delete() async {
    final existing = widget.category;
    if (existing == null) {
      return;
    }
    final repo = ref.read(categoryRepositoryProvider);
    final referenceCount = await repo.countActiveReferences(
      existing.id,
      existing.kind,
    );
    if (!mounted) {
      return;
    }
    final confirmed = await showCategoryDeleteDialog(
      context,
      categoryName: existing.name,
      kind: existing.kind,
      referenceCount: referenceCount,
    );
    if (!confirmed) {
      return;
    }
    await repo.softDeleteCategory(existing.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
```

(`repo` replaces the previous inline
`ref.read(categoryRepositoryProvider)` call at the old delete site — reused
once here, once for the count, so it's hoisted into a local.)

- [ ] **Step 2: Run the full settings test suite**

Run: `flutter test test/features/settings/`
Expected: PASS — both `category_delete_test.dart` (Task 3's new test plus
the pre-existing one) and `category_edit_test.dart`.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: no new lints (public members still documented, no unused
imports).

- [ ] **Step 4: Commit (Tasks 3 + 4 together)**

```bash
git add lib/features/settings/category_delete_dialog.dart \
  lib/features/settings/category_edit_sheet.dart \
  test/features/settings/category_delete_test.dart
git commit -m "Show the exact chore/item count in the category delete dialog"
```

---

## Task 5: Close out B-2 in the backlog

**Files:**
- Modify: `docs/backlog.md`

- [ ] **Step 1: Move B-2 into the closed list**

In `docs/backlog.md`, the top-of-file "Closed since they were written,
verified in code" paragraph (lines 10-14) lists closed items by their
source doc reference. Append `triage T2.2` to that list (it currently reads
"...triage Tier 1 except T1.3, the `2026-08-07` field-feedback..." — extend
the Tier-1 clause to also name T2.2, e.g. "...triage Tier 1 except T1.3 (and
T2.2 from Tier 2)..."). Then delete the **B-2** row from the "B. Trust and
safety gaps" table (lines 56-62) — it's no longer open.

- [ ] **Step 2: Commit**

```bash
git add docs/backlog.md
git commit -m "Close B-2: category delete now shows its impact count"
```

---

## Self-review notes

- **Spec coverage:** counting query (Task 1), where it lives + why
  (Analysis + Task 1), how it loads — pre-fetch decision (Analysis), exact
  copy incl. zero case (Task 2), truthful mechanism check (Analysis, backed
  by reading `softDeleteCategory`) — all covered.
- **No placeholders:** every step has literal code/JSON, no "add
  appropriate X".
- **Type consistency:** `countActiveReferences(String id, CategoryKind kind)`
  used identically in Task 1 (defined), Task 3 (doc reference), Task 4
  (call site). `showCategoryDeleteDialog`'s three named params
  (`categoryName`, `kind`, `referenceCount`) match between Task 3's
  definition and Task 4's call site.
- **Scope:** single ticket (B-2 / T2.2), five tasks, no unrelated
  refactoring pulled in.
