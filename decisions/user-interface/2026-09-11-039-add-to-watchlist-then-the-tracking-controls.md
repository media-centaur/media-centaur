---
status: accepted
date: 2026-09-11
---
# Add to watchlist first, then the tracking controls

Amends [UIDR-036](2026-09-07-036-one-control-per-title.md): the one control
keeps its shape as one control, and gains a second form. Point 3 there ("the
control renders whether or not the title is tracked") stands; point 5 (the
bookmark) is superseded — there is no separate bookmark, the control's first
form is the listing verb.

## Context and Problem Statement

Adding a title to the watchlist and enabling release tracking for it are two
acts, in that order, and the second happens only on the watchlist. The record
already worked that way — one title intent, one write path, List and above
is the list, Follow and above is tracked — but the full seven-way control was
mounted on every title view, so a search result, a Feed entry or a friend's
card reached Grab in one click without the title ever being on the list as a
step of its own. Four download-side controls raised a title to Follow or Grab
as a side effect of a download; those were removed first (campaign
`watchlist-single-entry-point`, Phase 1). This record settles the control.

Two rules were considered for which form a title view shows. *By surface*:
surfaces that find titles (search results, the Feed, Friends cards, the plan
modal) show the listing verb, surfaces that show the watchlist (the Watchlist
tab, Coming up, the Library) show the controls. It reads the brief literally,
but the title view would have to know which page opened it — Incoming opens
`?title=` from search results and from Coming up alike — and two classes of
surface would need names. *By the title's state*: the form follows the rung.

## Decision Outcome

Chosen option: "by the title's state", because it enforces the order without
a vocabulary for surfaces, and it makes the Library question dissolve — an
owned title's view follows the same rule as every other.

1. **A title not on the list offers one verb: `Add to watchlist`.** That is
   a title with no record (Off) or an ignored one. Beneath it, the line that
   says where the title stands ("Not on your list." / "Hidden from the
   Feed."). Nothing above List is reachable from this form. On an ignored
   title the verb replaces Ignore, the way any rung at List or above does.

2. **A title on the list shows the tracking controls**, the seven-way
   control of UIDR-036 unchanged: Ignore · Off · List · Follow · Ask · Grab ·
   Default, with the pressed rung's consequence beneath. Off returns the
   view to the first form.

3. **The rule is the rung, wherever the title was opened.** From a search
   result: open, Add to watchlist, then the controls appear on the same
   view. From the Watchlist tab or Coming up the title is by definition
   listed, so the controls are what shows. In the Library an owned series
   that nobody listed offers Add to watchlist first — owning a series is
   not listing it.

4. **A download never moves a rung.** No scope of a download, no checkbox on
   a picker, no handoff from a plan's missing units. The only thing that
   raises a title above List is the tracking controls on a title view.
   `ReleaseTracking.set_rung/3` stays the one write path.

5. **Ignore for a title not on the list lives on the Feed entry only.** Its
   one effect is keeping the title off the Feed, and the Feed entry's Ignore
   (UIDR-038) is where that decision is made. The title view of an unlisted
   title does not offer it.

### Names

*Tracking controls* is the seven-way control; the word is the owner's, and
it is what the heading above the control has said since UIDR-036. *Add to
watchlist* is the first form's verb and the name for that form. Neither
"bookmark" nor "ladder" names a user-facing thing; the stored level keeps
its code name, `rung`.

### Consequences

* Good, because the order is visible: a person sees the title join the list
  before they see what tracking it could do.
* Good, because nothing on the title view depends on where it was opened —
  no host-origin tracking, no surface names.
* Good, because a watchlist add from a Feed entry, a friend's card or a
  search result is the same click with the same label everywhere.
* Bad, because raising an unlisted title to Grab is two clicks where it was
  one. That is the point.
* Bad, because Ignore is one form further from a title opened from a
  friend's card; the Feed entry keeps the shortcut.
