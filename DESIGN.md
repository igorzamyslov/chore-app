# Family Chores App — Design Document

*Status: brainstorm / pre-implementation. Last updated: 2026-07-24.*

A mobile app (Android + iOS) for families to manage recurring household chores and a
shared shopping list, with respectful notifications and strong filtering/sorting.

---

## 1. Core concepts & domain model

```
Household ─┬─ Member (user, role: admin | member)
           ├─ Chore (definition) ──< ChoreOccurrence (due instance)
           ├─ ShoppingItem
           └─ Category (two sets: chore categories, shopping categories)
```

- **Household**: the sharing boundary. Created by one user; others join via
  invite code / link. A user can belong to multiple households (v2; model it
  from day one, UI can assume one).
- **Member**: profile (name, avatar/color), role. Admin can edit household,
  remove members; everyone can create/edit chores (keep it low-friction —
  families aren't corporations).
- **Chore (definition)**: title, optional notes, category, recurrence rule,
  assignment mode, reminder overrides, active/paused flag, created-by.
- **ChoreOccurrence**: generated from the definition. Due date, status
  (`pending | done | skipped | missed`), completed-by, completed-at.
  Occurrences are the source of history/stats ("who actually cleans the
  bathroom") and what the todo list renders.
- **ShoppingItem**: name, optional quantity/note, category (≈ store aisle),
  added-by, checked state, checked-at. Checked items collapse into a "done"
  section and auto-clear on "finish shopping" or after 24h.
  **Suggestions**: purchase history feeds *type-ahead* suggestions only —
  top ~8 matches ranked by frequency + recency — plus an optional small
  "frequent items" quick-add row (~10 chips). History is never shown as a
  browsable list (decided: no walls of 900 historic entries).
- **Category**: name + icon + color. User-editable with sane defaults.
  Chores: Cleaning, Kitchen, Garden, Pets, Maintenance…
  Shopping: Produce, Dairy, Frozen, Household…
  **Icons are flat/monochrome** (Material Symbols outlined set, tinted with the
  category color), *not* colored emoji — decided: icons act as quiet indicators,
  not decoration. Stored as an icon identifier string.

## 2. Recurrence engine

The heart of the app. Two anchor modes — this distinction is the #1 complaint
about existing chore apps when it's missing:

| Mode | Example | Next due date |
|---|---|---|
| **Fixed schedule** | "Trash out every Tuesday" | Next slot in the calendar pattern, regardless of when/whether the last one was done |
| **After completion** | "Water plants every 4 days" | N units after the *actual* last completion |

Rule shape (simplified RRULE):

```
Recurrence {
  interval: int              // every N …
  unit: day | week | month
  anchor: schedule | completion
  weekdays: [mon..sun]?      // weekly only: pin to specific day(s)
  monthlyMode: dayOfMonth | nthWeekday?   // "on the 15th" vs "first Saturday"
}
```

- One-off (non-repeating) chores are also allowed.
- Implemented as a **pure Dart function** `nextDueDate(rule, lastCompletion, tz)`
  with exhaustive unit tests + property-based tests. Timezones/DST are the
  classic failure zone — test explicitly (Europe/Berlin DST transitions).
- All-day due dates by default (chores are day-granular); optional due time later.

**Assignment modes**: fixed member | **rotation** (round-robin through selected
members — the fairness feature) | anyone (claimable). Rotation state advances on
completion, not on schedule, so a skipped turn can either stick (default) or pass.

**Skip vs. done**: "skip this one" advances the schedule without crediting
anyone and without wrecking stats. **Pause** (vacation mode) per chore and per
household.

## 3. Todo list & notifications

**List**: grouped by Overdue / Today / Tomorrow / This week / Later. Complete
with one tap; swipe for skip/snooze.

**Notification philosophy — digest by default, per-chore is opt-in:**

- **Daily digest**: one notification at a user-chosen time ("8:00 — 3 chores
  today"). This is the default and for many users the only notification.
- **Per-user settings** (not per-household): digest time, quiet hours,
  evening re-reminder if chores remain, overdue behavior (badge only / one
  repeat / silent).
- Scope: the digest counts **the recipient's own chores plus unassigned
  ("anyone") chores**. *Amended 2026-08-08 (decision OPD-1,
  `docs/plans/2026-08-08-daily-digest-scheduling.md`); this line previously
  read "'my chores' by default; 'unassigned chores' opt-in".* The opt-in
  framing was retired because it was written for the pre-sync,
  single-device era — one phone stood in for the whole household, so
  "unassigned" barely differed from "everything". With per-recipient
  scoping actually implemented (triage T2.3), defaulting "anyone" chores
  OFF would leave a household that assigns everything to "anyone" — the
  common case — with a permanently silent digest, which is a worse failure
  than slight over-inclusion. A genuine per-device toggle remains possible
  later; see backlog G-9.
- Per-chore override: individual reminder for the important ones.
- Notification actions: **Done ✓** and **Snooze to tomorrow** directly on the
  notification (supported on both platforms).
- Cross-user events ("Anna completed X", "5 items added to shopping") default
  **off** or bundled into the digest.

**Mechanics**: own-chore reminders = **local notifications** (offline-capable,
no server dependency; reschedule on app open + after sync). Cross-user events =
push (FCM/APNs). Server-side scheduled push via Supabase Cron (see §6) as a
reliability backstop for digests if local scheduling proves flaky (Android OEM
battery killers).

## 4. Filtering, sorting, categories

- One reusable **filter/sort component** used by both chores and shopping:
  - Filter chips row: member, category, status.
  - Sort: due date | name | category | recently added.
  - Group-by: day (default for chores) | member | category (default for
    shopping — aisle order).
  - Text search.
- **Saved views** ("My week", "Kids' chores") — fast-follow once filters are
  serializable objects.
- Shopping sorted by category = walk-the-store order; consider manual category
  ordering per household ("our supermarket's aisle order").

## 5. Monetization — DECIDED: no ads, tip-jar only

**Decision (2026-07-24):** no ads at all. Voluntary tip jar only. This removes
the entire compliance surface that ads would have required (GDPR/UMP consent
flow, iOS ATT considerations, ad content rating / Play Families policy, ad SDK
weight) and, per research, sacrifices only negligible revenue for a niche
utility app.

**Compliance rules for the tip jar (verified against 2026 policy):**

- Tips are **in-app purchases** on both stores — Apple guideline 3.1.1 treats
  in-app payments to the developer as digital purchases; Google Play Billing is
  mandatory for digital goods (its donation exemption covers only tax-exempt
  charities). **Never** link out to PayPal/Ko-fi/etc. from inside the app.
- Implemented as **consumable** IAP tiers (€0.99 / €2.99 / €4.99 / €9.99,
  "coffee"-style naming) so people can tip more than once. Stores don't allow
  free-form amounts; tiers are the standard indie pattern.
- Tips unlock **nothing functional** (pure support + optional cosmetic
  "supporter ❤" badge in settings) — keeps review simple and expectations
  honest.
- DMA/Epic external-payment entitlements: deliberately not used (built for
  large commerce; paperwork + EU Core Technology Commission 5–13% make them
  pointless for tips).

## 6. Tech stack (researched 2026-07)

| Layer | Choice | Why (short) |
|---|---|---|
| Framework | **Flutter** | Most mature plugin ecosystem for CRUD+scheduling+notifications; first-party AdMob plugin if ever needed; best static analysis out of the box. RN had a breaking New-Architecture wave + notification-lib churn (Notifee archived 2026); Compose Multiplatform iOS has accessibility gaps that break E2E tools. |
| E2E testing | **Maestro** (primary) | YAML flows, low CI flakiness, handles OS permission dialogs (incl. notifications). Patrol as fallback for deep native-widget needs. |
| State mgmt | Riverpod | Compile-safe, testable, standard. |
| Local DB | drift (SQLite) | Typed, reactive queries, works offline. |
| Backend | **Supabase** (Postgres + RLS + Auth + Realtime + Cron + Edge Functions) | Household isolation = simple RLS on `household_id`; pg_cron on free tier runs the reminder-push scheduler; ~$0/month at hobby scale; plain Postgres → minimal lock-in. Well funded (Series F 2026). |
| Offline sync | Start: cache + outbox queue on drift. Upgrade path: **PowerSync** (open-source, layers on Supabase without schema change) if true offline-first becomes a pain point. |
| Push | FCM + APNs via Supabase Edge Function; local notifications (`flutter_local_notifications`) for own reminders. |
| IAP | StoreKit 2 / Play Billing via `in_app_purchase` (or RevenueCat if receipt validation gets annoying). |

**Firebase fallback**: if RLS/sync work feels heavy, Firestore gives offline
sync out of the box — at the cost of NoSQL lock-in and Google's product-culling
track record (Dynamic Links †2025, Extensions/ML †2027).

## 7. Code quality & testing strategy

> Full strategy — including the non-happy-path E2E catalog, testability
> requirements (stable semantic IDs, injectable clock, seedable local
> backend), and the zero-flake policy — lives in
> [docs/specs/testing-strategy.md](docs/specs/testing-strategy.md).
> Decided 2026-07-24: every interaction gets happy + error/edge coverage at
> an explicitly chosen layer; E2E covers all paths that need the real stack.

- **Lints**: `very_good_analysis` (strict), `dart analyze` in CI, `dart format --set-exit-if-changed`.
- **Unit tests**: recurrence engine (property-based via `glados` or table-driven,
  DST cases), rotation logic, filter/sort logic. These are pure functions — keep them that way.
- **Widget tests**: list rendering, filter component, chore form validation.
- **E2E (Maestro)**: core flows on Android emulator + iOS simulator:
  create household → add chore w/ recurrence → complete → verify next occurrence;
  shopping add/check/clear; notification permission grant; tip-jar purchase (sandbox).
- **Backend tests**: RLS policies tested via Supabase local dev (`supabase start`) + pgTAP or SQL test scripts.
- **CI (GitHub Actions)**: lint + unit/widget tests on Linux (cheap, every push);
  E2E on Android emulator (Linux) every push; iOS simulator E2E on macOS runner
  (main branch / nightly to control cost). Release automation later via Fastlane
  or Codemagic.

## 8. MVP phases

**Phase 1 — usable by one family (ours):**
household create/join via invite code · chores CRUD with both recurrence modes +
weekday pinning · rotation · today/upcoming list with filters · complete/skip ·
local daily digest notification · shopping list with categories · categories CRUD.

**Phase 2 — polish & multi-user robustness:**
cross-user push, per-chore reminders + quiet hours, stats/history screen,
saved views, shopping type-ahead suggestions, offline hardening (PowerSync
decision point), tip-jar IAP.

**Phase 3 — nice-to-haves:**
home-screen widgets (today's chores / shopping), multiple shopping lists,
Siri/Assistant shortcuts, light gamification (streaks — deliberately parked;
polarizing in families).

## 9. Open decisions

1. **Offline depth for v1**: cache+outbox (simpler) vs PowerSync from day one
   (heavier, but shopping lists die in supermarket basements without it).
2. Auth method: email magic-link vs Sign in with Apple/Google (Apple sign-in is
   mandatory on iOS if any third-party social login is offered — magic-link-only
   avoids that).
3. Chore due *times* (vs day-granular only) in v1?
4. ~~App name (bundle ID uses a placeholder until decided).~~ Resolved
   2026-07-31: **Famdo**, bundle/application id `io.github.igorzamyslov.famdo`
   on both platforms (F-Droid convention for ids the developer verifiably
   controls, ahead of open-source distribution).
