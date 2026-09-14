---
status: accepted
date: 2026-09-07
amended: 2026-09-09
---
# One ladder per title: an authored rung, and machinery derived from it

Supersedes ADR-065 (retired), whose surviving rules are restated here.

## Context and Problem Statement

"What should the app do about this title" was stored twice — presence in the
watchlist and a `tracking_mode` on the tracked title — and rendered twice,
as an Add/Remove control beside a five-value mode strip that could
contradict it. Keeping two rows agreeing about one fact needed a listener, a
reconcile pass, a `Reasons` module and a migration-proven invariant. Once
the app never starts tracking a title by itself, none of that has a job.

## Decision Outcome

One authored record carries the whole ladder: listing a title and following
its releases are one decision at different strengths.

1. **A title intent is authored by a person.** The system never creates or
   removes one, and never raises a rung; a rung is set by a person or seeded
   once at creation. `:default` follows the global auto-grab setting live.
2. **`Discovery.TitleIntent`** (`title_intents`) carries the TMDB title, its
   provenance and the rung: `:ignored` (amended 2026-09-09: keeps friends'
   reviews of the title off the Feed, nothing else) · `:list` · `:follow`
   (keeps the calendar; releases appear under Coming up) · `:ask` (parks a
   draft plan when a release drops) · `:grab` · `:default`.
3. **Off is the absence of a record**, never a stored value. Turning
   tracking off deletes the record, so nothing can silently re-arm a title
   and no durable disarm is needed.
4. **A tracked title is derived, and only derived.** It exists exactly while
   the rung follows releases and the title is not a film already in the
   library. It carries no authored field. `ReleaseTracking.set_rung/3` is
   the one write path — it writes the record and derives the machinery —
   and `reconcile/2` re-applies the rule when the library moves under a rung
   nobody touched.
5. **The library is never a reason.** `ReleaseTracking.LibraryLinks` links a
   followed title to the container that arrives and unlinks when it goes;
   the rung decides. Deleting a series from the library does not stop
   something a person asked for.
6. **Listing announces; machinery is silent.** A rung first reaching List
   publishes a social act ([ADR-067](2026-09-11-067-listing-replaces-tracking-on-the-wire.md));
   creating or dropping derived tracking announces nothing.
7. **Per-title download params belong to Acquisition**
   (`Acquisition.TitleDownloadParams`, keyed by TMDB identity), so adjusting
   a quality acceptance never starts following a show.
8. **The dependency runs one way.** `ReleaseTracking` depends on `Discovery`
   and derives from it; `Discovery` stores an enum and knows nothing about
   calendars, wants or grabs. `Acquisition` reads the rung, so it too depends
   on `Discovery`.
9. **There is no collection case.** A tracked movie collection cannot be
   listed (its id is a TMDB collection id, a different namespace); its only
   writer was a scanner with no caller, deleted with the carve-out.

The invariant ADR-065 had to prove by migration — every active tracked title
is owned or listed — is unrepresentable here: nothing creates a tracked
title except derivation from a record.

### Consequences

* A title a person follows keeps following after they delete it from the
  library; this reversed the day-old behaviour of ADR-065 §2 deliberately.
* The upgrade stopped tracking every title with no record behind it —
  everything the app had started on its own.
