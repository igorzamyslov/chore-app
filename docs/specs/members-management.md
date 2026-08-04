# Spec: Members management + acting member (G7)

*Status: BINDING. Closes the gap found in docs/next-session-plan.md #7 and
docs/app-lifecycle.md G7: repositories support members, the chore form
renders member chips, but no UI ever creates a member and every completion
is attributed to the bootstrap admin.*

## 1. Scope

In scope: list/add/rename members, member color, acting-member switcher,
persistence of the acting member, attribution correctness.
Out of scope (deferred): roles UI (roles become meaningful with sync),
multi-household.

**Amendment (2026-08-01, UX audit A1):** member deletion — deferred here
pending "a reassignment story for chores referencing the member" — shipped
in `docs/feedback/2026-08-01-ux-audit.md` A1 (schema v9 soft delete +
`MemberService.deleteMember`'s referential cleanup is exactly that
reassignment story). §3's "no delete affordance" note below is
superseded; see that spec for the current behavior.

## 2. Data & providers

- **Schema v3**: `settings.actingMemberId` — nullable TEXT, no FK
  constraint (settings is a single device-scoped row; a dangling id must
  degrade gracefully, not fail a constraint). Migration from v2: add the
  column, default NULL. Bump `schemaVersion` to 3.
- **SettingsRepository**: `Future<void> setActingMember(String? memberId)`
  (NULL clears back to the automatic default), included in the existing
  watched settings stream.
- **actingMemberProvider** (lib/app/providers.dart): resolve in order —
  1. `settings.actingMemberId` if it matches a current household member;
  2. otherwise the existing fallback (first admin, else first member).
  A dangling/NULL id therefore silently falls back; nothing crashes and
  nothing writes back to settings (self-healing read, not a repair).
- Ordering: members are listed everywhere in `createdAt` order (stable,
  matches the chore-form chips).

## 3. Members screen

- Entry: a `Members` row on the Settings tab, above `Categories`,
  same row pattern as the existing categories entry.
  Semantic id: `settings.members`.
- Screen (`lib/features/settings/manage_members_screen.dart`): list of all
  household members; each row shows the avatar (colored circle +
  first-letter initial — same rendering as the chore tile avatar; extract
  a shared widget if the tile's avatar is currently private) and the name.
  Row semantic id: `members.row.<name>` is NOT allowed (names collide) —
  use `members.row.<memberId>`; E2E selects rows by visible text, ids
  exist for uniqueness fallback (matches manage_categories conventions).
- Add: FAB or app-bar action (follow manage_categories precedent),
  semantic id `members.add`. Opens an edit sheet with:
  - name: required, trimmed, non-empty; duplicates ALLOWED (consistent
    with the chores duplicate-names decision) — no warning;
  - color: the same fixed palette picker used by the category edit sheet
    (reuse the widget/palette, do not fork it); default = first palette
    color not yet used by another member, else first.
  - New members get `MemberRole.member` and are immediately available in
    the chore form and the acting switcher.
- Rename / recolor: tapping a row opens the same sheet pre-filled
  (`members.edit.name`, `members.edit.save` ids per the category sheet's
  id scheme).
- Delete: superseded by `docs/feedback/2026-08-01-ux-audit.md` A1 -- see
  that spec for the current delete affordance (visibility guards,
  referential cleanup) and `lib/application/member_service.dart`.

## 4. Acting-member switcher

- The chores tab app bar gets a leading avatar button showing the CURRENT
  acting member (color + initial). Semantic id: `chores.actingMember`.
- Tap → modal bottom sheet: title ("Who's doing chores right now?" /
  German du-form equivalent), one row per member (avatar + name +
  check on the current one). Selecting persists via
  `setActingMember(id)` and closes the sheet. Sheet ids:
  `actingMember.sheet`, rows `actingMember.sheet.row.<memberId>`.
- The switcher is GLOBAL (one settings value): chore completions
  (`completedBy`) and any other actingMember reads (shopping quick-add,
  chore form defaults) all follow it. It appears only on the chores tab
  in this version.
- One member in household: the switcher still shows (it is also the
  affordance that teaches "the app knows who I am") but the sheet just
  lists the single member.

## 5. l10n

All new strings via gen_l10n, EN template + DE (du-form). Keys prefixed
`members*` / `actingMember*` / `settingsMembers*`. Reuse existing
save/cancel keys where they exist.

## 6. Tests

Unit/repository:
- settings v2→v3 migration keeps the existing row; new column NULL.
- `setActingMember` set/clear round-trip through the watched stream.

Provider:
- actingMemberProvider honors a valid stored id; falls back on NULL and
  on a dangling id (member id that doesn't exist).

Widget (integration-style, only `appDatabaseProvider` + `clockProvider`
overrides, drift streams never awaited outside pump):
- Members screen: bootstrap-only state shows 'Me'; add flow (save
  disabled on empty/whitespace name; new member appears in list AND in
  chore-form chips); rename updates everywhere; recolor updates avatar;
  duplicate name accepted.
- Switcher: switch to a second member → complete a chore → Done-today
  attribution shows the second member's name; switch persists across a
  fresh ProviderScope over the same database (app-restart simulation).

E2E (e2e/flows/settings/, follows e2e/README.md conventions, id-first
selectors):
- Journey: Settings → Members → add 'Anna' → back to Chores → tap
  `chores.actingMember` → pick Anna → complete a seeded chore → assert
  the done-today entry attributes Anna.

## 7. Non-goals / invariants

- Rotation semantics unchanged: rotation order remains the chore's
  assignee list order and advances on `assigned_member_id`. The acting
  member owns `completedBy` for EVERY UI completion — assigned or not
  (user decision 2026-07-31: credit records who actually did the work;
  see ui-foundation-chores.md tile contract).
- Bootstrap unchanged: 'Me' is still created on first run (renaming it
  is exactly what this screen is for; the G2 name prompt stays a
  separate, later task).
