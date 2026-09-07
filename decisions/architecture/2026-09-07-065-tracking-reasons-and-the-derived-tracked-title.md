---
status: superseded in part
date: 2026-09-07
---

> **Superseded in part** by [ADR-066](2026-09-07-066-one-ladder-per-title.md):
> §2 (tracking reasons), §4 (seeded modes), §5 (the durable disarm) and
> the collection carve-out. §1, §3, §6 and §7 stand, restated there in
> the vocabulary that replaced theirs.
# A tracked title is derived from reasons; only a person sets its mode

## Context and Problem Statement

Four things represented one idea — "the app should do something about this
title":

1. presence of a `Discovery.WatchlistItem`,
2. presence of a `ReleaseTracking.Item`,
3. `Item.status` (`:watching` / `:ignored`) — the bell on the library detail panel,
4. `Item.auto_grab_mode` (`global` / `off` / `ask` / `all_releases`).

`Discovery` was inert storage: three files, read by nothing but the UI.
`ReleaseTracking` was the machine. Both keyed `(tmdb_id, media_type)`, both held
a title snapshot, both carried provenance, both promoted artwork. The title
detail modal offered `Add to watchlist` and `Track` side by side, divided by
release date (`Logic.primary/2`), so a person chose between "remember it" and
"watch for it" with no stated difference in outcome — and one of the two had no
outcome.

`Item.source` (`:library` / `:manual`) was write-once first-cause metadata with
one reader — deciding whether to broadcast the social activity — and was wrong
for any title with both causes.

The consequences showed up as behaviour nobody chose.
`detach_library_containers/1` nulled a deleted container's pair and kept *every*
item, so a series deleted from the library kept tracking and kept grabbing
forever, whether or not anyone had asked it to. Meanwhile a person's deliberate
"stop tracking this" lived in a field (`status`) separate from their deliberate
"don't auto-grab this" (`auto_grab_mode`), and neither survived a change to the
other list.

## Decision Outcome

Chosen option: "a watchlist entry is authored intent, a tracked title is derived
machinery", because existence and behaviour are different questions with
different owners, and conflating them is what produced four fields for one idea.

1. **A watchlist entry is authored, exclusively.** A person adds it, a person
   removes it; the system never does either. Library presence is derived at read
   time via `Library.ExternalIds`, never a membership rule.

2. **A tracked title exists while a tracking reason holds.** Two reasons, and
   they are deliberately **not** equivalent:

   * The **library reason** — the library owns an active container — is a
     *default*. The app tracks the title because you own it. A default
     evaporates when its cause goes away.
   * The **watchlist reason** — a person armed the entry — is an *act*, and
     outlives the library.

   **Arming is a watchlist act**: choosing to track a title puts it on the
   watchlist, whichever surface the control was operated from. A tracked title
   with no watchlist entry is therefore the app applying its default, nothing
   more — which is exactly what makes it safe to drop when the library drops it.

3. **One `tracking_mode` replaces `status` and `auto_grab_mode`**: None, Watch,
   Ask, Grab, or Global. It is set only by a person, or seeded once at creation,
   and is **never raised by the system**. `Global` follows the ambient setting
   live, but only while the mode has never been set explicitly — an explicit
   mode is a concrete value and so is immune to a global change.

4. **Seeded modes differ by origin, because auto-grab is opt-in.** A watchlist
   entry a person arms seeds **Watch** — calendar only — so adding something to
   a list can never start a download. The library scan seeds **Global**,
   preserving the established behaviour in which the global auto-grab setting is
   the person's opt-in. Adding to the watchlist creates no tracked title at all;
   arming is a second act.

5. **An explicit disarm is durable.** A row at mode None survives with no reason
   held — inert: no calendar refresh, no wants, no Coming up row, invisible in
   every list. It exists solely so that re-acquiring or re-listing the title
   later cannot silently re-arm what a person turned off. Every other mode
   evaporates with its last reason, because raising is the only direction that
   can surprise, and nothing here raises.

6. **`Item.source` is removed.** `Events.TrackingStarted` moves off the
   creation path and onto the arming path: `track_item/1` is silent, because
   creating a tracked title is machinery, and `arm/2` announces, because arming
   is a person's act. It is announced from `ReleaseTracking` rather than
   `Discovery` — the dependency runs that way (7), and `Discovery` must stay
   free of tracking. `ReleaseTracking.arm/2` is likewise where the act is
   implemented: it puts the title on the watchlist and starts tracking it as one
   operation, which is how the invariant is kept true at the only place that can
   see both sides. "Arming is a watchlist act" is a statement about what the act
   *does*, not about which context holds the function.

7. **Dependency direction stays one-way.** `ReleaseTracking` gains a
   `WatchlistListener` mirroring the existing `LibraryListener` and adds
   `Discovery` to its `Boundary` deps. `Discovery` stays free of tracking; the
   watchlist *view* composes tracking state in the web layer.

The invariant that falls out, and which the migration must prove on real data:

> **Every active tracked title — mode above None — is either owned or on the
> watchlist.**

### A collection has only the library reason

The watchlist is keyed `{tmdb_id, media_type}` on *titles*. A tracked movie
*collection* is keyed by the TMDB **collection** id under `media_type: :movie` —
a different namespace — so listing one would write a watchlist entry claiming to
be a film with that id, which resolves to a different film or to nothing.

So **a collection is never armed as a watchlist act**: raising its mode is a
plain mode change, and its tracked title rests on the library reason alone. That
does not weaken the invariant, because a collection's tracked title is created by
the library scan from a `MovieSeries` container and therefore always has that
reason; when the container goes, the reconcile drops it, which is correct. A
single film needs no such carve-out: it completes on arrival in the library, so
an owned film has no tracked title at all.

### Consequences

* Good, because deleting a series from the library now stops tracking it exactly
  when nobody asked for it, and keeps tracking it exactly when somebody did.
* Good, because a person's explicit choice cannot be destroyed by an unrelated
  act on either list.
* Good, because the invariant gives every active tracked title a list that shows
  it, which is what lets the UI retire the straggler concept
  ([UIDR-035](../user-interface/2026-09-07-035-two-title-surfaces.md)).
* Bad, because inert None rows accumulate — one per title anyone ever
  deliberately disarmed. They are bounded by deliberate acts and are not pruned:
  pruning one would re-arm the title, which is the thing the row exists to
  prevent.
* Bad, because arming from the library detail panel creates a watchlist entry.
  That is the point of "the watchlist is where you arm", but it must be stated
  by the control's copy rather than inferred.
* Bad, because the cutover is a real behaviour change on existing installs:
  anything currently tracking a deleted series without a watchlist entry stops.
  It belongs in the CHANGELOG in plain words, not as a refactor note.
