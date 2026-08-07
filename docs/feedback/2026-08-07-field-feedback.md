# Field feedback — 2026-08-07 (post-v0.4.0)

Igor, after living with v0.4.0. Eight items. Findings below were verified
against the source, not assumed.

## A. Correctness / honesty (do first)

### A1 — Signed out ≠ local, and the app says nothing

> "if i log out — my household is just 'converted' to the local one, but
> the other person can continue working in the online household? what
> happens if i logged out and made some changes and then log in again?"

**What actually happens.** `_signOut` (`account_section.dart`) calls
`authGateway.signOut()` and nothing else. The household keeps its
`syncHouseholdId`, so the device is still *linked* — but `syncEngineProvider`
gates on a signed-in user (spec `2026-08-01-ux-audit.md` A5), so the engine
drops to `NoopSyncEngine` and all sync stops.

Therefore, while signed out:
- the other member keeps working; their changes accumulate server-side;
- local edits keep setting `syncDirty = true`;
- nothing pushes or pulls.

On signing back in, `start()` runs `pushDirty()` (dirty rows go up) and then
pulls. Because the conflict rule is **last-push-wins per row** (spec
`sync-backend.md` §3), a row edited on both sides resolves to *the signed-out
device's* version — even when the other member's edit was newer in real
time, because the re-login push happens later in server time. The longer the
signed-out window, the more rows this can silently clobber.

**Decisions.**
1. The signed-out-but-linked state gets its own honest UI: name the
   household, say sync is paused, and offer *Sign in to resume* as the
   primary action. Today it renders a bare sign-in form, indistinguishable
   from "never linked".
2. Add an explicit **Disconnect from the online household** action, distinct
   from Sign out: it clears `syncHouseholdId` and the pull cursor, and keeps
   the local data as a genuinely local household. That is the operation the
   phrase "converted to the local one" describes, and it does not exist yet.
3. Sign out keeps the link (unchanged) — but the confirm dialog must state
   what it does: sync pauses, local changes are kept and will be pushed when
   you sign in again, and the household stays on this device.
4. **Not in scope here:** replacing last-push-wins. It is a documented
   family-scale trade-off; changing it is its own spec. A1 is about making
   the state visible and giving the user the missing exit.

### A2 — No welcome screen after logout

> "if i logged out - i don't see the welcome screen"

Correct as designed, and it stays: the welcome gate keys on *no household on
the device*, and logging out does not remove one (see spec
`onboarding-v2.md` §2). The real defect is A1's — the app presents the
signed-out state as if nothing had ever been linked. Fixing A1 removes the
surprise; A2 needs no separate change. The new Disconnect action (A1.2) is
what a user actually wants when they expect "back to the start", and
Settings → Data → Reset app data remains the full wipe.

## B. Interaction model

### B1 — Acting-member switching is wrong for online households

> "I never want to 'be another person' on my phone, but in very rare cases
> I might finish something for another person"

The acting-member switcher is a leftover from the local-only era, where one
phone stood in for the whole household. In a synced household the phone
*is* a person: the signed-in member. Offering "become Anna" in the app bar
of every screen inverts the common case.

**Decision** (approved by Igor 2026-08-07). When the household is linked and
signed in, the acting member is pinned to the claimed member and the app-bar
switcher is hidden. The rare case moves to where it belongs: the chore's own
action sheet gains **Mark done for…**, which completes that occurrence
crediting another member without changing who you are. Local-only households
keep the switcher unchanged — there, standing in for others *is* the model.

**Constraint from Igor: "Mark done for… shouldn't be annoying."** It is a
rare action and must stay one — one ordinary row in a sheet the user already
opened deliberately. Specifically: it does NOT get a place on the tile, does
NOT prompt or confirm when you complete something normally, does NOT ask
"who did this?" on the common path, and never appears as a banner, tooltip
or first-run hint. Completing a chore as yourself must stay exactly one tap.

### B2 — Settings: Account and Household belong together

> "account and household in settings should be bound together"

Agreed. The v0.4.0 grouping split them because Household = "things in the
household" and Account = "your login", but from the user's side sign-in,
invite, members and categories are all *this household*. Merge into one
**Household** group ordered: sync/sign-in state, Invite, Members,
Categories. Preferences / Data / About are unchanged.

### B3 — Swipe between tabs

> "not possible to change screens by swiping left/right"

Real gap (conventions audit C-class). The shell uses an `IndexedStack`
specifically to preserve each tab's scroll position and in-flight state.
Moving to a `PageView` must keep that (keep-alive per page) and must keep
every `shell.tab.*` id and the hand-rolled bar's semantics workaround.
Medium effort, not a one-liner.

**Deferred to the future-improvements list** (Igor, 2026-08-07) — see
`docs/next-session-plan.md`. Not dropped, just not now.

## C. Polish

### C1 — Pull-to-refresh indicator appears too eagerly

> "the refresh icon when swiping down is a bit annoying — could it appear a
> bit later?"

Flutter's `RefreshIndicator` starts drawing the spinner from the first pixel
of over-scroll and fires at a fixed 25% of viewport extent
(`_kDragContainerExtentPercentage`) — the trigger distance is **not** a
parameter. The available lever is `displacement` (default 40), which sets
how far down the indicator settles, so a larger value means more drag before
it reads as present. Raise it and check on device; if that is not enough,
the honest options are a custom `RefreshIndicator` fork or a
`ScrollPhysics` with more resistance, both of which are real work.

### C2 — Tab-bar tap feedback looks bad

> "the gray background on tap on bottom buttons doesn't look really good"

Confirmed: `_BottomTabBar` uses a bare `InkWell` with no `borderRadius`, so
the ripple is a grey rectangle spanning the whole tab column while the
active state is a rounded pill. Constrain the ink to the pill's shape and
tint it with the accent instead of the default grey.

### C3 — Tapping a suggestion animates the *next* one

> "i click on first proposal, it's added immediately and then the other
> proposal gets 'tapped' animation"

**Cause found.** `ShoppingSuggestionsList` builds its chips in a `for` loop
with **no `Key`**. Flutter therefore matches chip elements by position.
Adding the tapped item re-ranks the list, chip 0 disappears and the rest
shift up — so the element that was chip 0 is reused for what was chip 1, and
the in-flight ink splash keeps playing on it. The next suggestion appears to
tap itself.

**Fix.** Give each chip a `ValueKey(suggestion.name)` (name is the identity
the suggestion engine ranks on). Keep the positional `shopping.suggestion.N`
semantic id — the E2E suite addresses chips by index.

## Order of work

1. **C3, C2** — small, clearly-diagnosed defects.
2. **A1** — signed-out honesty + Disconnect action + accurate sign-out copy.
3. **B2**, then **B1** — settings regrouping is small; the acting-member
   change needs the "Mark done for…" sheet action.
4. **C1** — tune `displacement`, verify on device.
5. **B3** — tab swiping, once the rest has settled.
