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
  1. **Pinned** (§4.2 — linked AND signed in): `claimedMemberProvider`, if
     the claim has reached this device;
  2. `settings.actingMemberId`, if it matches a current household member;
  3. **Not pinned only**: the existing fallback (first admin, else first
     member). While pinned, this step is deliberately SKIPPED — the
     provider resolves to `null` instead of guessing "the first admin",
     which is exactly the misattribution §4.2's pinning exists to remove.
  A dangling/NULL stored id therefore silently falls back while not
  pinned (or resolves to `null` while pinned); nothing crashes and
  nothing writes back to settings (self-healing read, not a repair). See
  §4.2 for the full pinned-mode rationale and the transitional-state
  details step 3's skip depends on.
- Ordering: members are listed everywhere in `createdAt` order (stable,
  matches the chore-form chips).

## 3. Members screen

- Entry: a `Members` row on the Settings tab, above `Categories`,
  same row pattern as the existing categories entry.
  Semantic id: `settings.members`.
- Screen (`lib/features/settings/manage_members_screen.dart`): list of all
  household members; each row shows the avatar and the name. The avatar
  (`lib/features/members/member_avatar.dart`, shared with the chore tile)
  is **a ring in the member's color around their two-letter initials on the
  neutral surface** — radius 21 (42px) on this screen, per the design
  canvas. It was a filled circle with a one-letter initial before G-4.
  - **The initials rule**: the first two characters of the trimmed display
    name, uppercased (`"Mia"` → `"MI"`). A one-character name gives one
    character (`"J"` → `"J"`), never padded. `"Anna Maria"` gives `"AN"`,
    not `"AM"` — these are name-initials, not word-initials. A blank or
    whitespace-only name gives `"?"`. `memberInitials` is exported so the
    picker's taken-swatch badge cannot drift from the avatar.
  - Two characters rather than one because for a color-blind viewer the
    initials are the only channel that separates members. The chore-tile
    avatar was enlarged from 20px to 24px to fit them; the rule was not
    weakened to fit the old size.
  Row semantic id: `members.row.<name>` is NOT allowed (names collide) —
  use `members.row.<memberId>`; E2E selects rows by visible text, ids
  exist for uniqueness fallback (matches manage_categories conventions).
- Add: FAB or app-bar action (follow manage_categories precedent),
  semantic id `members.add`. Opens an edit sheet with:
  - name: required, trimmed, non-empty; duplicates ALLOWED (consistent
    with the chores duplicate-names decision) — no warning;
  - color: the same fixed palette picker used by the category edit sheet
    (reuse the widget/palette, do not fork it) — `CategoryRepository.palette`,
    **twelve** colors since G-5b, drawn six across as theme-rendered rings;
    default = first palette color not yet used by another member, else first.
  - **Member colors are unique per household** (G-4): a color another
    active member holds is drawn inert and badged with that member's
    initials, with a `Taken by <name>` screen-reader label. The member being
    edited is excluded, so their own current color stays selectable. The
    rule **relaxes** once the roster outgrows the palette — a thirteenth
    member gets every swatch enabled rather than being blocked over a color.
    It is UI guidance and never a database constraint: under sync two
    devices can claim the same color concurrently and the loser's save must
    not fail.
  - The sheet shows a live 66px preview avatar (`members.edit.avatar`),
    which updates as the name is typed and the swatch picked, and the
    uniqueness hint (`members.edit.colorHint`).
  - **No column was added to `members`.** The design canvas suggested a
    nullable text column for an initials override; the feature needs none
    (initials derive from `name`, the ring reads `color`), and `members` is
    a synced table, so a column there is a Supabase migration + an RLS
    UPDATE grant + both directions of `row_mappers.dart` + pull/push
    coverage. If an override is ever wanted it is its own ticket.
  - New members get `MemberRole.member` and are immediately available in
    the chore form and the acting switcher.
- Rename / recolor: tapping a row opens the same sheet pre-filled
  (`members.edit.name`, `members.edit.save` ids per the category sheet's
  id scheme).
- Delete: superseded by `docs/feedback/2026-08-01-ux-audit.md` A1 -- see
  that spec for the current delete affordance (visibility guards,
  referential cleanup) and `lib/application/member_service.dart`.

## 4. Who the app acts as

Two modes, decided by `memberIdentityModeProvider` (`lib/app/providers.dart`)
from the linked state (`settings.syncHouseholdId`) and the auth state
(`currentAuthUserProvider`). Amended 2026-08-08 by A-5 / field feedback
`docs/feedback/2026-08-07-field-feedback.md` B1.

### 4.1 Switching mode — local-only, or linked but signed out

Unchanged from this spec's original text: on a local-only household the
phone stands in for everybody, so standing in for others IS the model.

- The chores tab app bar gets a leading avatar button showing the CURRENT
  acting member (color + initial). Semantic id: `chores.actingMember`.
- Tap → modal bottom sheet: title ("Who's doing chores right now?" /
  German du-form equivalent), one row per member (avatar + name + check on
  the current one). Selecting persists via `setActingMember(id)` and closes
  the sheet. Sheet ids: `actingMember.sheet`, rows
  `actingMember.sheet.row.<memberId>`, plus the `acting.manage` row.
- The switcher is GLOBAL (one settings value): chore completions
  (`completedBy`) and any other actingMember reads (shopping quick-add,
  chore form defaults) all follow it.
- One member in household: the switcher still shows (it is also the
  affordance that teaches "the app knows who I am") but the sheet just
  lists the single member.

### 4.2 Pinned mode — linked AND signed in

On a synced household the phone IS a person, and `settings.actingMemberId`
is device-scoped and never syncs, so acting on it lets two devices credit
different people for the same work.

- The acting member is PINNED to the claimed member —
  `claimedMemberProvider`, resolved from the local `members.userId` mirror
  against the signed-in auth user id. There is no switcher and no switcher
  sheet.
- The `chores.actingMember` slot stays, as a NON-interactive avatar of the
  claimed member with the accessible label "You're signed in as {name}".
  The id is present in every mode, so no selector ever loses its target.
- Crediting someone else moves to the chore action sheet's **Mark done
  for…** row (`chores.menu.markDoneFor`), which opens a member picker
  (`chores.markDoneFor.sheet`, rows `chores.markDoneFor.row.<memberId>`)
  and calls `ChoreService.completeOccurrence(..., completedBy: <picked>)`.
  It never writes `settings.actingMemberId`: crediting somebody is not
  becoming them.
- **Binding constraint (Igor, 2026-08-07):** "Mark done for… shouldn't be
  annoying." One ordinary row, in a sheet the user opened deliberately, on
  a linked household with at least two members. No tile placement, no
  prompt or confirmation on a normal completion, no "who did this?" on the
  common path, no banner/tooltip/first-run hint. **Completing a chore as
  yourself is exactly one tap.**
- `settings.actingMemberId` is never written or cleared by pinning; it is
  simply not read while a claim resolves, and it is correct again the
  moment the device disconnects.
- Transitional states: while either the linked or the auth state is still
  resolving, the slot renders the neutral placeholder (never a switcher
  that would vanish a frame later). While pinned with no claim yet (adopted
  offline, or before the first pull) the stored acting member is used, and
  if it dangles the acting member resolves to `null` rather than guessing
  "the first admin". A signed-in account that is no longer a member of the
  household is a revoked membership — see `household-lifecycle.md` §3.5.

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
- memberIdentityModeProvider: local-only and linked-but-signed-out are
  `switching`; linked + signed in is `pinned`.
- claimedMemberProvider resolves the member whose `userId` matches the
  signed-in auth user, and stays null for another account's claim.
- While pinned, actingMemberProvider returns the claimed member even when a
  stored actingMemberId points elsewhere, and returns null (never the
  first-admin guess) when neither resolves.

Widget (integration-style, only `appDatabaseProvider` + `clockProvider`
overrides, drift streams never awaited outside pump):
- Members screen: bootstrap-only state shows 'Me'; add flow (save
  disabled on empty/whitespace name; new member appears in list AND in
  chore-form chips); rename updates everywhere; recolor updates avatar;
  duplicate name accepted.
- Switcher: switch to a second member → complete a chore → Done-today
  attribution shows the second member's name; switch persists across a
  fresh ProviderScope over the same database (app-restart simulation).
- Pinning: a local-only household keeps the tappable switcher and its
  sheet; once linked AND signed in the same id is present but not a
  control, and tapping it opens nothing.
- Mark done for…: absent local-only and absent in a linked household of
  one; present when linked, signed in and ≥2 members; picking a member
  credits THEM (`completed_by`), leaves `settings.actingMemberId` untouched,
  and confirms with a snackbar naming them. Completing normally stays one
  tap and never opens the picker.

E2E (e2e/flows/settings/, follows e2e/README.md conventions, id-first
selectors):
- Journey: Settings → Members → add 'Anna' → back to Chores → tap
  `chores.actingMember` → pick Anna → complete a seeded chore → assert
  the done-today entry attributes Anna.
- Pinned mode gets NO Maestro coverage: E2E runs with empty Supabase
  dart-defines, so `NoopHouseholdGateway` makes linking unreachable and
  `settings.syncHouseholdId` is always NULL. The existing switcher journey
  is therefore unchanged and still valid. Same conclusion, same reason as
  `household-lifecycle.md` §4.

## 7. Non-goals / invariants

- Rotation semantics unchanged: rotation order remains the chore's
  assignee list order and advances on `assigned_member_id`. The acting
  member owns `completedBy` for every ORDINARY UI completion — assigned or
  not (user decision 2026-07-31: credit records who actually did the work;
  see ui-foundation-chores.md tile contract) — **except** §4.2's "Mark done
  for…" path, which is a deliberate carve-out: it writes
  `completedBy: picked.id` for a member that is, by construction, NOT the
  acting member, and it never calls `setActingMember`. That is intentional
  — crediting someone else is not becoming them — so do not "fix"
  `_markDoneFor` to also update the acting member; doing so would
  reintroduce the device-scoped attribution drift §4.2 exists to remove.
- Bootstrap unchanged: 'Me' is still created on first run (renaming it
  is exactly what this screen is for; the G2 name prompt stays a
  separate, later task).
