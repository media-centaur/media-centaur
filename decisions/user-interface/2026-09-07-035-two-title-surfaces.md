---
status: accepted
date: 2026-09-07
---
# Two title surfaces, split by whether the title has files

Supersedes the straggler half of
[UIDR-017](2026-08-03-017-coming-up-title-depth.md).

## Context and Problem Statement

Three modals rendered one title, all tenants of the same cinematic frame:

* **`DetailPanel`** (`entity_modal.ex`) — owned titles: episodes, files,
  playback, tracks, and a **bell** toggling `ReleaseTracking.Item.status`.
* **`Discovery.TitleDetailModal`** — titles the library does not own: overview,
  provenance, pennants, and the verbs `Download` / `Track` / `Add to watchlist`.
* **`ReleaseTracking.TitleModal`** — tracked titles, keyed by `item_id`: the
  next release, the automation section, the release timeline, recent activity,
  and `Stop tracking`.

The split is by **which table the title came from** — a distinction nobody
outside the codebase can perceive. One title walks through all three over its
life (watchlisted → tracked → downloading → owned) and gets a different modal, a
different route and a different vocabulary at each step. Worse, the states
overlap: an owned series with an announced season exists in two of them at once,
the library modal showing files and a bell, the tracking modal showing the
timeline and the automation control, and neither showing the whole title.

The bell is a one-bit view of what [ADR-065](../architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md)
establishes as a five-value `tracking_mode`.

## Decision Outcome

Chosen option: "two surfaces, split by whether the title has files", because
that is a fact a person can see, and it is the only difference between the three
that a person could name.

1. **Library detail** — titles with files. Gains the release timeline and the
   tracking-mode control. The bell is removed.
2. **Title detail** — titles without files. `ReleaseTracking.TitleModal` is
   absorbed into `Discovery.TitleDetailModal`.

**The release timeline and the tracking-mode control become two shared
components mounted by both.** That is the real de-duplication: one idea,
rendered twice today, in different markup with different words.

**`Track` disappears as a verb.** Adding to the watchlist and arming replace it.
**`Stop tracking` disappears as a verb** — it is setting the mode to None.
**`Remove from watchlist`** becomes the separate, unrelated act it always should
have been.

**Three lists, one job each:** the watchlist is authored intent and the arming
surface, each row showing its mode and its next date when it has one; Coming up
is the schedule across every tracked title; the library is what you have.

**The "Not scheduled yet" stragglers line on Coming up is retired**, and
`UpcomingFeed.Straggler` with it. Its population is a tracked title with no
announced date, which under ADR-065's invariant is either owned (visible in the
library, mode on its detail) or on the watchlist (visible there, mode on its
row). It existed only because no other list showed tracked-but-undated titles.

### Consequences

* Good, because a title keeps one surface and one vocabulary for its whole life,
  and an owned series with an announced season is finally described in one place.
* Good, because the tracking-mode control is the same control everywhere,
  instead of a bell here and an automation section there.
* Bad, because it touches `DetailPanel`, the most load-bearing UI in the app.
  Sequenced last for that reason, after the two no-files surfaces have merged.
* Bad, because between those two steps the bell remains a knowingly-stale second
  representation of `tracking_mode` — an explicit scheduled convergence, tracked
  in `campaigns/watchlist-and-release-tracking.md`, not a silent one.
