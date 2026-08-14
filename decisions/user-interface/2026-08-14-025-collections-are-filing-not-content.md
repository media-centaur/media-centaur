---
status: accepted
date: 2026-08-14
---
# Collections are filing, not content — activity surfaces speak in movies

## Context and Problem Statement

A movie collection exists to keep related movies together: members do not
always share a name, so alphabetization scatters them, and the collection
card is the fix. It is a shelf. A TV series is different in kind — its
episodes are continuations, and progressing through the whole series is
the point ("one long movie"). A movie is a self-contained, bite-sized
work; a collection is a shelf of those.

The home feed contradicted these semantics. Continue Watching presented
the collection entity as a single in-progress thing with a blended saga
percentage (`(movies_completed + current_fraction) / movies_total`) and a
computed "1 / 3 movies" label; a collection stayed on the strip after a
member finished, nudging the next member as if the saga were a series.
Recently Added surfaced "‹Collection›" when the new thing was a member
movie. The hero banner featured the collection entity, whose description
and artwork are franchise-level filler, when each member has better art
and a real synopsis. Meanwhile UIDR-023 had already made members
first-class destinations inside the modal — the feed hadn't caught up.

## Decision Outcome

**Collections manifest in exactly two places: the library view (the shelf
card) and the collection modal's poster rail (the shelf's contents).
Every activity surface — Continue Watching, Recently Added, the hero
banner — presents member movies as movies.** A collection has no
completion fraction anywhere; watched state appears only as the rail's
per-member checkmarks.

* **Continue Watching**: one card per member movie with incomplete
  partial progress, carrying that movie's backdrop, logo, and
  within-movie progress bar. Finishing a member with the next unstarted
  removes the collection's presence from the strip entirely — a shelf
  earns no "up next" nudge. Two members paused at once means two cards.
  The blended-percentage and "N / M movies" label paths for
  `movie_series` are deleted, not hidden.
* **Recently Added and hero**: member movies appear individually with
  their own poster, backdrop, and synopsis; the collection entity never
  appears. Hero eligibility (description + backdrop) is evaluated per
  movie.
* **Click contract**: any surface presenting a member movie opens the
  collection modal explicitly pre-selected on that movie. The UIDR-023
  resume-target ladder applies only when the modal is entered without a
  selection (the library shelf card).
* **Relationship to ADR-050**: the possession-count resolver remains the
  single authority for movie-vs-collection — but its scope narrows from
  "every surface" to filing surfaces and click routing. Activity
  surfaces never ask the presentation question (the answer is always
  "movie"); they consume the resolver solely to route a member movie's
  click to the right modal. This dissolves the per-surface
  singleton-hoist special cases: activity surfaces fetch movies, period,
  and the hoist matters only where a shelf is drawn.
* **One component family per idiom**: the strip keeps a single card
  anatomy for all title kinds, and the collection modal remains the
  parameterized standalone-movie panel of UIDR-023. No kind-specific
  forks — the modal family is under continuous improvement and forks
  drift.

### Consequences

* Good, because every surface now tells the truth about its unit: what
  you continue is a movie, what was added is a movie, what is featured
  is a movie; the shelf appears where filing is the job.
* Good, because it deletes semantics-bearing code (saga blend, movies
  label, collection branches in three feed fetchers) rather than adding
  a display variant.
* Good, because dormant wrong data can't resurface: the never-rendered
  "1 / 3 movies" label dies with the semantics that produced it.
* Bad, because a bulk-imported large collection floods Recently Added
  with one poster per member, evicting other entries. This is truthful
  (that many movies were added) and typical imports are small; accepted
  as a watch-item. A "collapse same-batch siblings" rollup is explicitly
  rejected — it reintroduces collection-as-content through the side
  door.
* Bad, because a viewer who relied on the between-movies nudge loses it;
  the next member is findable on the shelf and the rail, by design.
* Neutral, because members missing backdrop or logo fall back per the
  UIDR-021 artwork ladder (collection art, then text title) — same
  ladder the modal already uses.
