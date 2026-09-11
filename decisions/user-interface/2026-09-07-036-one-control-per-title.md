---
status: accepted
date: 2026-09-07
---

> **Amended 2026-09-11** by [UIDR-039](2026-09-11-039-add-to-watchlist-then-the-tracking-controls.md):
> the control has two forms decided by the title's rung — a title not on the
> list offers only **Add to watchlist**; a listed one shows the seven-way
> tracking controls. Point 5 (the bookmark) is superseded: the first form is
> the listing verb, and nothing else toggles the bottom of the record.
> **Amended 2026-09-11** by [UIDR-038](2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md):
> on a Feed entry the Ignore shortcut and the List bookmark (point 5) sit
> in a hover/cursor toolbar under the entry, together with Download. The
> toolbar shows state and verb as one control; the ladder remains the
> verb everywhere else.
> **Amended 2026-09-09:** the ladder gained a seventh rung, **Ignore**,
> left of Off — a record that keeps friends' recommendations of the
> title off the Recommendations tab, and nothing else. Off stays the
> absence of a record. The Recommendations row's hover-revealed `×` is
> a one-click shortcut to that rung, the one exception to point 4
> below; the ladder remains the verb everywhere else. See
> `docs/superpowers/specs/2026-09-09-ignore-recommendation-design.md`.

# One control per title, because there is one ladder

Supersedes the clause in [UIDR-035](2026-09-07-035-two-title-surfaces.md)
that reads "**`Remove from watchlist`** becomes the separate, unrelated
act it always should have been". The rest of UIDR-035 stands and is
strengthened: the control is the same control everywhere, and now there
is one of it.

## Context and Problem Statement

The title detail carried two controls for one idea. `Add to watchlist` /
`Remove from watchlist` were verbs in the action strip; the tracking-mode
strip below offered Off · Watch · Ask · Grab · Default. UIDR-035 called
de-listing "separate and unrelated", which was true of the storage —
two tables — and false of what a person was doing.

They could contradict each other. Removing from the watchlist while the
title sat at Grab was a legal click that tore down the calendar, the
wants and the tracking as a side effect, with no confirmation and no
statement that it would. The library detail panel, meanwhile, hid the
tracking control entirely for a title that was not already tracked —
which, once the app stopped tracking titles on its own, would have left
an owned series with no way to start.

## Decision Outcome

Chosen option: "one control, six rungs", because listing a title and
following its releases are the same decision at different strengths
([ADR-066](../architecture/2026-09-07-066-one-ladder-per-title.md)).

1. **`Discovery.IntentControl` replaces `TrackingModeControl` and the two
   watchlist verbs.** Six buttons, ladder order:

   > Off · List · Follow · Ask · Grab · Default

   The pressed rung carries `aria-pressed`; beneath it, that rung's
   one-line consequence, then the notes, then the per-title quality
   acceptance row when set.

2. **Off states that it deletes, before the click.** Its consequence line
   is the whole disclosure, which is why it needs no second confirmation:
   the person reads what Off does and then chooses it. (Nothing about the
   title is lost that TMDB cannot supply again; the tracking event log
   survives the row.)

3. **The control renders whether or not the title is tracked.** Off is a
   rung like any other, so hiding the control on an untracked title would
   hide the way onto the ladder. The only thing that suppresses it is a
   subject with no TMDB identity, which has no rung to set.

4. **A row wears a marker, never the control.** List rows and search rows
   show where a title sits and open its modal to change it. The one
   exception is the bookmark, below.

5. **The bookmark toggles the bottom of the ladder only.** On a search
   row or the library detail's view controls, the bookmark adds a title
   at List and removes one that is still at List. At Follow and above it
   is a marker, not a toggle, and its label says where the ladder lives.
   A one-click affordance must not destroy a calendar and its wants.

### Consequences

* Good, because the two controls can no longer disagree — there is one.
* Good, because an owned series can be followed from the library detail,
  which it could not be once the library stopped doing it unasked.
* Good, because a person who wants a title off their list entirely has
  one gesture for it, and reads what it does first.
* Bad, because `Remove from watchlist` disappears as a named verb, and
  someone looking for it has to recognise Off. The consequence line
  carries that, and the bookmark's label repeats it.
* Bad, because Off on a surface whose titles *are* the list (the
  watchlist tab, Coming up) closes the modal — the page no longer knows
  the title. That reads as abrupt, and is the honest consequence of the
  page's own source of titles rather than a decision of this record.
