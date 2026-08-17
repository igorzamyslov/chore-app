# Spec: Onboarding v2 — the welcome gate

*Status: BINDING. Replaces the silent local bootstrap with an explicit
first-run choice. Source: field feedback round 3
(docs/feedback/2026-08-01-field-feedback.md) — a first-time user could
not find registration, and the bootstrap-then-replace model produced
"two users" confusion. Interacts with the sync spec
(docs/specs/sync-backend.md §7); changes nothing server-side.*

## 0. Principles

- **No household exists until the user chooses.** The lazy
  `ensureLocalHousehold()` bootstrap is retired for fresh installs; the
  app opens on a welcome screen until a household exists locally —
  created ("start fresh") or downloaded ("join").
- **Local-first is untouched as a capability.** "Set up a new
  household" needs no account, no network, nothing — one tap + a name.
  Sync remains an upgrade, never a requirement.
- **The joining persona never touches local scaffolding.** Sign-in and
  invite code come FIRST; no local household, no "Me" member, no
  archive, no import offer — there is nothing local to preserve.
- **Existing installs never see the gate.** A device with a household
  row behaves exactly as today (including the Settings join path with
  its archive/import machinery, which remains the ONLY correct flow
  once local data exists).

## 1. The welcome screen

Shown when (and only when) the local database has no `households` row.
Full-screen, no tab shell. Content:

- App name + one-line purpose (l10n; friendly, du-form in DE).
- **Primary card: "Set up a new household"** (`welcome.create`) —
  subtitle "Keep it on this phone — you can sync later." Tapping asks
  for the user's name inline (field `welcome.create.name`, button
  `welcome.create.confirm`; same validation as the member edit sheet)
  and creates the household with ONE member carrying that name (admin,
  first seed color), then seeds default categories and lands on the
  chores tab. The onboarding NAME BANNER is thereby dead for this path
  — mark `onboardingNamePromptShownAt` at creation so it can never
  appear; the banner code itself stays for upgraded installs.
- **Secondary card: "Join my family's household"** (`welcome.join`) —
  subtitle "Sign in and use an invite code from a family member's
  phone." Flow: email + magic-link sign-in INLINE on a welcome subpage
  (`welcome.join.email`, `welcome.join.send`; reuse the Account
  section's gateway + copy, not its widget) → after the deep link
  returns: if `findMyMembership()` reports an existing membership,
  offer reconnect first (`welcome.join.reconnect`, reusing the P2d
  service path minus archive — nothing local exists); otherwise code
  entry → claim/"I'm new here" (reuse the join sheet's chooser
  machinery) → download → land on chores tab. Acting member = the
  claimed/new profile. No archive step, no import offer: with no local
  household both are meaningless (the join SERVICE keeps them for the
  Settings path; the welcome path calls a variant that skips them —
  implementer's choice how to parametrize, flagged in review).
- Small print at the bottom (`welcome.offline`): "No account needed —
  everything stays on your phone unless you sign in." Links nothing.

If Supabase is unconfigured (offline/F-Droid builds, tests), the join
card is hidden entirely and only "set up new" shows.

Kill-the-app-mid-welcome, BEFORE any sign-in, resumes at the plain welcome
screen (state is simply "no household yet"). Once sign-in has completed, a
kill-and-relaunch instead resumes DIRECTLY on the join subpage, skipping the
two-card chooser: `WelcomeScreen` auto-pushes `WelcomeJoinPage` the first
time it observes a signed-in `currentAuthUserProvider` with no household yet
(at most once per screen instance, and never while its own route is not the
topmost one, so backing out of the subpage neither loops nor stacks a second
copy over a subpage the user is already on). That subpage's own build-time
derivation (above) takes it from there — to the P2d reconnect offer if
`myMembershipProvider` already resolves one, otherwise to code entry. The
invite code most recently accepted by the server also survives
(`settings.pendingJoinCode`, cleared on a successful join and on starting a
new household instead) and prefills the code field, so a kill after code
entry but before the claim/join RPC completes does not force retyping an
8-character code the joiner may never have written down.

Neither mechanism is authoritative: the step shown is always re-derived from
live `currentAuthUserProvider`/`myMembershipProvider` state, never from a
cached "where was I" flag, and `pendingJoinCode` only ever seeds a text field
the user can overwrite. A half-succeeded claim/join RPC self-heals through
the same reconnect-offer path a returning device uses (spec
`docs/specs/sync-backend.md` §7.6) — by the time that RPC returns, the
account is already a claimed member server-side, whether or not the local
device finished applying it.

## 2. App-spine changes

- `bootstrapProvider` no longer CREATES anything. Split:
  - `householdGateProvider` (new): watches whether any household row
    exists (drift stream, `watchSingleOrNull`-shaped). The root app
    widget shows WelcomeScreen when null, the tab shell otherwise.
  - `bootstrapProvider` keeps its id-resolving + side-effect role
    (seed categories if missing, catch-up, stale-checked cleanup) but
    ASSUMES the household exists; it is only reachable once the gate
    passed. `ensureLocalHousehold()` becomes
    `createLocalHousehold(name)` (explicit, called by the welcome
    create path) plus a plain `getHousehold()`; the idempotent-race
    guard stays.
- Upgrade path: any existing install has a household → gate never
  appears; nothing else changes for it.
- The welcome join path reuses `HouseholdJoinService` internals; the
  post-join `ref.invalidate(bootstrapProvider)` pattern applies here
  too (the gate stream flips on insert, showing the shell).

## 3. Testing

- Widget-test harness: `testChoreApp` seeds a household + member 'Me'
  directly (repository call) before pumping, so every existing test
  bypasses the gate unchanged — including the name-banner tests, whose
  bootstrap shape ('Me') the harness now owns explicitly.
- New widget tests: gate shows on empty db; create path (name typed →
  household + named admin member + categories seeded + shell shown +
  name banner never appears); join card hidden under Noop gateways;
  welcome-join happy path with fakes (sign-in → membership-null → code
  → claim → downloaded household → shell, acting member set); reconnect
  offer when membership exists; mid-flow kill resumes at gate
  (pump fresh app against same db).
- E2E: every flow currently assumes the shell after `clearState`
  launch. Add `e2e/flows/common/onboard_fresh.yaml` (tap
  `welcome.create`, type name "Me", confirm) and prepend
  `- runFlow: ../common/onboard_fresh.yaml` (path-relative) to every
  flow right after its launch/settle steps. `first_run_banners.yaml`
  changes meaning: the name banner no longer exists on a fresh install
  — the flow becomes "welcome create → digest preprompt journey" (its
  permissions machinery and the digest assertions stay; the
  onboarding.name assertions are REPLACED by welcome-gate steps). The
  first-frame settle (README convention 8) now waits for
  `welcome.create` instead of `shell.tab.chores` on cold launches.
  Update e2e/README.md accordingly.

## 4. Out of scope (tracked, not in this slice)

- Contextual category management entry points (same feedback round,
  separate slice — pickers gain an "edit" affordance).
- Acting-member switcher rethink for signed-in devices; day-to-day
  flow friction (awaiting concrete examples).
- Any server change: none needed.
