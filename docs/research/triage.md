# Persona walkthrough — triage

*2026-08-07. Synthesis of `persona-anna.md`, `persona-ben.md` and
`persona-mia.md` into one ranked plan. Overlapping findings are merged and
credited to whoever found them. Every item was verified against source by
the persona agent and spot-checked by me where it drives a decision.*

**Already fixed** (commit `60c15ce`): Mia #1 — pull-to-refresh could never
report failure, because `onRefresh` called `pushDirty()`, which swallows
every error by contract, and the promised sync-error copy did not exist.

## Tier 1 — The app misleads the user (fix without asking)

These break the thing all three personas depend on differently: that what
the app shows is true.

| # | Finding | Who | Why it's tier 1 |
| --- | --- | --- | --- |
| T1.1 | **The progress card and the list under it disagree.** The card counts the whole household unfiltered (`chores_list_screen.dart:62-74`); the sections below respect the active member/category filter (`:353-391`). Filter to yourself and the ring says "3 of 8" over a list of 2 | Anna 1, Ben 2 | A number contradicting the list directly beneath it, on the most-opened screen |
| T1.2 | **"Its history is kept" is unverifiable.** True in the DB (`chore_repository.dart:232-249`), but every read path filters `deletedAt IS NULL` and no history screen exists. The dialog invites a destructive tap by promising a safety net that has no mechanism | Anna 2, Ben 3 | Same "promise without a mechanism" class as ux-audit A4 |
| T1.3 | **Acting-member misattribution.** The switcher still shows for linked households (B1 decided, unbuilt), AND `actingMemberId` is device-scoped and never syncs — so two devices can silently credit different people for the same work | Anna 4, Ben 6 | Multi-device makes B1 worse than the single-phone case it was written for |
| T1.4 | **"Clear checked" is the only destructive action with no undo** (`shopping_checked_section.dart:113-119`), while single-item delete has one | Ben 4, Mia | Inconsistent exactly where the bulk action is riskier |
| T1.5 | **Pause gives no feedback at all** (`chores_list_screen.dart:226-227`) — every other state change snackbars. Its undo lives in a collapsed section the user doesn't know exists | Ben 7 | Silent state change + hidden recovery |
| T1.6 | **Join errors can't be self-corrected.** Typo, expired, and revoked all produce one string (`app_en.arb:1203`) on the screen where a new member is most anxious | Ben 9 | First real interaction; failure here loses the user entirely |
| T1.7 | **The member Delete button vanishes with no explanation** when the member is claimed or last (`member_edit_sheet.dart:79-86`) — no disabled state, no reason | Anna 6 | A quiet dead end where the audit said deletion now works |

## Tier 2 — Missing context and safety (fix, lower urgency)

| # | Finding | Who |
| --- | --- | --- |
| T2.1 | **Catch-up after a lapse is invisible** — `catchUpOverdue` (`chore_service.dart:138-178`) converts a backlog to "missed" before the list renders, with no explanation. To Ben this reads as an accusation | Ben 1 |
| T2.2 | **Category delete never says how much it affects** — no "3 chores and 5 items" before an irreversible tap | Anna 7 |
| T2.3 | **The daily digest isn't scoped to the recipient** (`providers.dart:736-745`) — both partners get the identical household-wide count each morning | Anna 9 |
| T2.4 | **The join wizard keeps no persisted state** (`welcome_join_page.dart:51-64`) — switching to Mail to tap the magic link can drop the user back to the welcome screen mid-join | Anna 3 |
| T2.5 | **Rotation order can't be edited, only rebuilt** — re-tapping always re-appends (`chore_form_screen.dart:409-424`), while Categories next door has drag-reorder | Anna 5 |
| T2.6 | **A denied notification permission is permanent in practice** — the only nudge is a one-shot banner (`digest_preprompt_banner.dart:91-93`) and the recovery lives in Settings, which Ben never opens | Ben 8 |
| T2.7 | **Push has no periodic retry; only pull does** (`sync_engine.dart:290-301`). A write made as connectivity drops can sit unpushed until the next local write or resume | Mia 3 |

## Tier 3 — Needs your decision (do not fix unilaterally)

### D1 — Is a household flat, or does it have admins?

`members.role` is stored and set to `admin` for the creator, but **nothing
reads it** — not one RLS policy, not one RPC, not one widget. Worse,
`grant update (name, color, role, deleted_at) on members` lets any member
rename, re-role, or soft-delete *any other member*, including the admin.

Three honest options:
- **(a) Flat by design.** Delete the `role` column's implied meaning, drop
  it from the schema or document it as vestigial, and state in the UI that
  everyone in a household has equal power. Cheapest, and arguably right for
  families.
- **(b) Minimal admin.** Enforce admin-only for exactly three things:
  rename household, remove a member, revoke/regenerate invites. Requires
  RLS changes plus client gating plus a story for "the admin left".
- **(c) Leave as-is.** Not recommended: the column actively implies a model
  that does not exist, so a future reader will assume protection that isn't
  there.

**My recommendation: (a)**, plus one narrowing — revoke the `deleted_at`
grant on `members` so one member cannot soft-delete another server-side.
Flat trust is honest for a household; silently deletable people are not.

### D2 — What does "history is kept" mean?

T1.2 can be fixed two ways: **cheaply**, by changing the delete copy to
stop promising something unobservable; or **properly**, by building the
stats/history view (backlog F19) that makes the promise true. The cheap fix
is a one-line ARB change and I'd do it now regardless; the question is
whether F19 moves up.

### D3 — Should the progress card follow the filter?

T1.1 has two fixes: make the card respect the active filter (so the numbers
always match the list), or leave it household-wide and label it so. I
recommend **the card follows the filter**, with its sub-line naming the
filter when one is active — a summary that contradicts the list beneath it
is worse than a summary that narrows.

## Tier 4 — Accepted limitations (document, don't fix)

These are consequences of last-push-wins and the local-first design. They
are real, and the right response is to write them down rather than pretend
otherwise. Added to `future-improvements.md`'s trade-offs section.

- **Delete-vs-check resurrection** (Mia 4): a check pushed after someone
  else's delete un-deletes the item for both. Full-row upsert + LWW.
- **Cross-device duplicate names** (Mia 5): duplicate prevention is a local
  query (`shopping_repository.dart:271-283`); "Bread" and "bread" added on
  two devices before either syncs both survive.
- **Rotation drift from missing `chore_assignees` tombstones** (Anna 10):
  removing someone from a rotation on one device never reaches the other,
  so the removed person keeps getting turns there. The general limitation
  is in `sync-backend.md` §8.5; the fairness consequence is new.
- **The 60-second pull bound** (Mia 2): with realtime degraded, up to a
  minute can pass before a change appears. Bounded, and pull-to-refresh is
  the escape hatch — which now actually reports failure.

## Suggested order

1. **T1.1, T1.4, T1.5, T1.7** — small, self-contained, all trust bugs.
2. **T1.2** cheap copy fix now; D2 decides whether F19 follows.
3. **T1.3** — the B1 work (pin acting member, add "Mark done for…"), now
   with the device-scoped-drift finding folded in.
4. **T1.6**, then Tier 2 in listed order.
5. **D1** once you've picked (a), (b) or (c) — it touches migrations.
