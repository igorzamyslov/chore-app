# Famdo Features — design canvas, readable extract

Source: Claude Design project 401f8c45-5659-4f30-9760-847eb7965636,
file "Famdo Features.dc.html", captured 2026-08-18. The canvas itself is
committed beside this file as `2026-08-18-famdo-features.dc.html` — open THAT
in a browser for the live prototype. It is the authority: the extract below
drops the inline prototype logic (`sentence()`, `nextDates()`, the `RING`
palette, the `g2notes`/`g4notes`/`g8notes` arrays) that several plans cite
directly.

Section numbering used by the plans: 1a G-2 repeat form · 1b G-4 avatars ·
1c G-8 several lists · 1d G-5 icons and colours · 1e G-7 search ·
1f F-2 share-to-app · 1g F-3 home-screen widget.

---

@@@SECTION@@@
Turn 1 · backlog G + F · light theme
Seven parked features, designed
On the Famdo light theme from the previous turn. 1a 1b 1c are the deep ones — the repeat form, avatars and multiple lists carry real structural change. 1d 1e 1f 1g are one screen each. Where you left a question blank I decided and said so under the frame.
1a
G-2 · Repeat form, rebuilt as one sentence
The old form showed an interval field, a unit segmented control, a weekday chip row, a monthly mode row and two anchor cards all at once — five controls with no stated relationship. Now there is one sentence you fill in. Each hole is a tap target; the fields that do not apply to the chosen unit do not exist. The anchor moved below the sentence because it is not part of the pattern — it decides what the pattern counts from. Tap the chips: the frame is live.
arrow_back
Edit chore
Save
Chore
Water the plants
repeat
Repeats
Repeat every
{{ interval }}
{{ unitLabel }} unfold_more
{{ tailWord }}
{{ domLabel }} unfold_more
{{ ordinalLabel }} unfold_more
{{ monthWeekdayLabel }} unfold_more
{{ d.label }}
{{ m.label }}
Counting from
{{ a.icon }}
{{ a.title }}
{{ a.sub }}
event_upcoming
{{ preview }}
What changed, and why
{{ n.icon }}
{{ n.text }}
Recurrence keeps its current shape — interval, unit, weekday set, monthly mode, anchor — so this is a form rewrite, not a schema change. The plain-language sentence you asked for is the same string the paused rows and chore tiles already render, so one formatter serves three places.
1b
G-4 · Avatars: colour ring, initials inside
No photos — so no storage, no sync payload, no permissions, no moderation question. A member is initials on the neutral surface with a 2.5px ring in their colour, which means the same avatar reads at 16px in a chore tile and at 66px in the edit sheet. Twelve curated colours, all tone-mapped for both themes and all clearing 3:1 against paper and ground.
arrow_back
Household
4 members
{{ m.initials }}
{{ m.name }}
{{ m.meta }}
chevron_right
person_add Add someone
MI
Name
Mia
Ring colour
check
info
Your colour is how you show up on every chore, in the digest and in Chore history. Two people can’t take the same one.
Cancel
Save
Decisions I made for you
{{ n.icon }}
{{ n.text }}
1c
G-8 · Several lists, one screen
Lists are collapsible sections, as you picked — no tabs, no second screen, so a glance still answers “is there anything to buy anywhere”. Aisle grouping survives inside the open list. You left the mechanics blank, so: one list open at a time, the quick-add row carries a list chip you can tap to retarget, and the first list is pinned and cannot be deleted (it is where a share-sheet add lands when nothing else is chosen).
Shopping
playlist_add
search
add
Add an item…
Groceries unfold_more
{{ L.icon }}
{{ L.name }}
{{ L.meta }}
push_pin
{{ L.chevron }}
{{ A.name }}
{{ it.name }}
{{ it.qty }}
shopping_basket
In the cart (4)
Clear
The rules
{{ n.icon }}
{{ n.text }}
warning
This is the XL one, and the reason is not the UI: shopping_items has no list FK, the digest counts a single list, and sync/export both assume one. The design above works with exactly one new table and one nullable column — but it is a schema migration and a sync change, not a screen.
1d
G-5 · More icons and colours
You left the missing-category list blank, so I picked the nine that cover what a household actually tracks and that the current fifteen cannot say: bathroom, bins, plants indoors, baby, bike, admin, hosting, heating, sport. Twelve colours, same set as the avatar rings — one palette, two uses.
{{ catIcon }}
Category
Bathroom
Icon
24
{{ i.name }}
Colour
12
check
Cancel
Save
The dot marks the nine new icons only for this review — it does not ship. Both grids stay six across so the sheet height does not grow past a thumb’s reach; icons scroll inside the sheet if the set grows again.
1e
G-7 · Search, per screen, with filters
Search replaces the title in the bar it belongs to, and the existing member/category filter bar stays visible under it rather than being a second, competing mechanism. The count line is the honest answer to the persona finding: while a query or filter is active the day-progress card is replaced, not left to disagree with the list beneath it.
arrow_back
bath |
close
person Anna
label Category
schedule Any time
3 chores
matching “bath”, assigned to Anna
{{ r.pre }} {{ r.hit }} {{ r.post }}
{{ r.cat }}
· {{ r.when }}
{{ r.due }}
info
Paused and done chores are searched too — they appear at the bottom, greyed.
Same pattern on Shopping and Chore history; the search icon only appears once a list is long enough to need it (I would gate it at 15 rows), so small households never see it.
1f
F-2 · Share-to-app
You left this blank. With 1c there is more than one place an item can land, so a silent add would be a guess the user cannot see — it gets a small sheet naming list and aisle, both pre-filled, dismissible with one tap on Add. Shared text is split on newlines and commas, so a pasted recipe line becomes several items you can strike out before adding.
Shared from Notes
“oat milk, sourdough, 6 eggs”
add_shopping_cart
Add 3 items
check_box
{{ s.name }}
{{ s.aisle }}
list
Groceries unfold_more
Add to Groceries
Famdo stays closed — you land back in Notes.
1g
F-3 · Home-screen widget
Tick-only, as you picked: no text entry, so no keyboard-in-a-widget and no half-typed item lost to a widget reload. A tick strikes the row in place and the count in the header drops. The list name is a tap target that opens the app on that list — which is the whole of the widget’s navigation.
home Home screen · 4×3
shopping_cart
Groceries
7 to buy
refresh
check
{{ w.name }}
{{ w.qty }}
+3 more
Open list
One widget per list, configured when you place it — which is how a household with three lists gets three widgets without any new UI inside the app.
If you want an order
You left the sequencing blank in round one and asked for the deep three in round two, so here is the order I would ship in: G-5 first (a day’s work, no schema, and the backlog already says its only open question was which icons — this answers it), then G-4 (one column on members , and it makes every other screen more legible), then G-2 (form-only rewrite, no migration, and it retires a known field-feedback complaint). G-7 after those, because search gets more useful once categories and members are distinguishable. G-8 and F-3 last and together — the widget is only worth building against the final list model — with F-2 alongside them, since its sheet needs the list picker G-8 introduces.