# Audit: established mobile conventions

*2026-08-06. Prompted by Igor: the missing pull-to-refresh "made me think —
should we generally analyze well-established UX patterns and apply them to
the application?"*

**Yes, and it deserves to be a recurring pass, not a one-off.** This is the
sibling of the 2026-08-01 reachability audit
(`docs/feedback/2026-08-01-ux-audit.md`). That one asked *"can the user
always get to the state they want?"*. This one asks a different question:

> **"When the user does the thing every other app has taught them to do,
> does anything happen?"**

A missing convention is invisible in a feature list and invisible in
testing-by-the-author, because the author knows where the buttons are. It
only shows up as the feeling the new tester reported in round 3: *clunky*.
Nothing is broken; the app just doesn't answer gestures the user already
has in their hands.

Every finding below was verified against the source, not assumed.

## Findings

| # | Convention | State today | Impact | Effort |
| --- | --- | --- | --- | --- |
| C1 | **Pull-to-refresh** | Absent everywhere (`RefreshIndicator`: 0 hits) | High | S |
| C2 | **Swipe on a list row** | Absent everywhere (`Dismissible`: 0 hits). Deleting a shopping item means opening its edit sheet | High | S |
| C3 | **Haptics on the core action** | Absent (`HapticFeedback`: 0 hits). Completing a chore and checking an item are the app's two reward moments and both are silent | High | XS |
| C4 | **Unsaved-changes guard** | Absent (`PopScope`: 0 hits). Back out of a half-filled chore form and it is gone | High | S |
| C5 | **Long-press context menu** | Chores have it; shopping items do not | Medium | S |
| C6 | **Re-tap a tab to scroll to top** | Not wired — `onSelected(tab)` only switches tabs | Medium | S |
| C7 | **Keyboard field chaining** | Only `TextInputAction.done`; the chore form's title does not advance to notes | Medium | XS |
| C8 | **Keyboard dismiss on scroll** | Not set (`ScrollViewKeyboardDismissBehavior`) | Medium | XS |
| C9 | **Offline / can't-reach-server state** | No visible state; a linked device that cannot reach Supabase looks identical to a healthy one | Medium | M |
| C10 | **Undo on destructive actions** | Present for complete/skip; absent for deletes | Medium | S |
| C11 | **Actions on the notification** | Daily digest has no actions — cannot mark anything done from it | Medium | M |
| C12 | **Share-to-app** ("add to shopping list" from any app's share sheet) | No share intent filter | Medium | L |
| C13 | **Home-screen widget** for the shopping list | None | Medium | XL |
| C14 | **Search in long lists** | None; fine at family scale | Low | M |
| C15 | **Primary action reachable with the keyboard open** | **Broken on the chore form.** Save lives in the Scaffold's `bottomNavigationBar`; with the keyboard up it is not in the accessibility tree at all — verified 2026-08-06 on a Pixel emulator (keyboard y1517–2274, form content ends y1480, no `chore_form.save` node). The user must dismiss the keyboard to find Save, with nothing telling them so | High | M |

Already correct, for the record: empty / loading / error states exist on
both list screens; optimistic local writes are inherent to the local-first
design; back behavior is standard; drag-reorder exists for categories;
undo exists for the two most common chore actions.

## Recommendation

**Do now** — small, unambiguous, and each one fixes a rule the project
already committed to:

- **C1** — covered by `docs/specs/sync-freshness.md` §2.3, in flight.
- **C3** — haptics. Note this does *not* break the "no custom animation"
  rule: haptics are not animation and do not affect E2E determinism.
- **C4** — `design-language.md` interaction rule 7 already says *"never
  lose user input"*. The form violates it today; this is a bug against an
  existing binding rule, not a new feature.
- **C8** — a two-line fix.
- **C7 was attempted and deliberately reverted.** Chaining title → notes
  made Enter jump into an optional 3-line field and keep the keyboard up,
  which strands the user because of C15 below. It also broke eight E2E
  flows, which is how C15 was found at all: they had been passing only
  because Enter's default `done` action dismissed the keyboard. Chaining
  is right for sequential *required* fields; this form is title-then-save.

**Do next**, as one wave:

- **C2** swipe-to-delete on shopping items (with **C10**'s undo snackbar —
  swipe without undo is worse than no swipe), **C5** long-press parity for
  shopping, **C6** tab re-tap scroll-to-top.

**Needs your call** — real scope, genuine value, not obviously next:

- **C9** offline indicator (pairs naturally with the sync-freshness work).
- **C11** notification actions — "Done" from the digest is a strong fit for
  a chores app, but needs a background isolate handler and its own tests.
- **C12** share-to-app and **C13** a home-screen widget are the two that
  would most change how the app feels day to day for the shopping half —
  and both are multi-day platform work, per platform.

## The method, for next time

Run this pass whenever a batch of screens changes. The checklist is the
table above plus: does every list scroll, refresh, swipe and long-press;
does every form chain, guard and restore; does every async surface show
loading, empty and error; does every destructive action undo; does the
system's own gestures (back, share, notification, keyboard) reach the app.
Cheap to run, and it catches exactly the class of problem no feature spec
ever contains.
