---
status: planning
started: 2026-09-06
last_updated: 2026-09-06
---
# Exact ID search against indexers

## Goal

Ask indexers for a title by its **identifier** rather than by its name.
Newznab indexers accept `imdbId` on a movie search and `tvdbId` + `season` +
`ep` on a TV search, and Prowlarr surfaces which of those each indexer
supports. Today we send free text and then reverse-engineer identity by
parsing release titles with a ±1-year tolerance. An id match is exact, so it
retires that heuristic for every result that carries an id, kills the
year-drift problem at the source, and removes a class of false negative the
matcher can only paper over.

## Status

Planning, no code. **Unblocked 2026-09-06** — the probe is done and the answer
splits the campaign into a cheap phase worth doing and an expensive one that
may not be.

## Decisions made

* `2026-09-06` — Deferred out of the movie best-of-both-terms work rather than
  folded in: it needs identifiers plumbed onto plans and pursuits, and careful
  handling of a fan-out across indexers with differing capabilities. Commits
  `76994d0`, `24fb572`.
* `2026-09-06` — The generic search type (`type=search`) honours **only** `q`.
  Any id search must therefore also set the matching search type, which is why
  earlier `imdbId` probes appeared to do nothing. Measured on Prowlarr
  2.4.0.5397; recorded in the `Search.Prowlarr` moduledoc.
* `2026-09-06` — **The aggregated `/api/v1/search` ignores `imdbId`.** A
  deliberately wrong id returns byte-identical results to the correct one,
  with the indexer healthy before and after both requests. Same shape as the
  `year` finding: Prowlarr accepts the parameter and drops it.
* `2026-09-06` — **The per-indexer Newznab route honours it.**
  `GET /{indexerId}/api?t=movie&imdbid=…&apikey=…` — the route Radarr and
  Sonarr consume — returned 51 items all carrying the film's id, against 100
  unrelated items for a bogus id. It is also *more complete* than our text
  path: 51 releases where title matching over the aggregated search verified
  49. So exact search is real, but only by bypassing Prowlarr's fan-out.
* `2026-09-06` — **Split into two phases on that basis.** Identity
  *verification* using ids already present in aggregated responses needs no
  query change, no fan-out change and no extra requests, and captures most of
  the value. Identity *querying* needs us to own the fan-out. Phase 1 is
  clearly worth it; Phase 2 is a real trade and may be declined.
* `2026-09-06` — Not adopting `limit` as a companion lever. Indexers advertise
  a `limitsMax` (100 typical) and Prowlarr pages upstream to satisfy a larger
  one, so raising it multiplies requests against rate-limiting indexers.
  Category scoping is the cheaper narrowing lever and already shipped.

## Next steps

### Phase 1 — verify identity by id (no query change, no extra requests)

1. **Capture the ids we already receive.** `SearchResult` discards `imdbId` /
   `tmdbId` / `tvdbId` from every aggregated response. Capture them, and
   round-trip them through the corpus (a column, as `grabs` and `protocol`
   just were — the corpus claims to carry every `SearchResult` field).
2. **Carry the identifiers on the want.** `Library.ExternalIds` already stores
   tmdb / imdb / tvdb per container; `acquisition_plans` and
   `acquisition_pursuits` carry only `tmdb_id`. TMDB supplies `imdb_id` and
   `Tmdb.Mapper` already extracts it. Migration plus capture at creation.
3. **Teach `TitleMatcher` to prefer the id.** A matching id is a verdict, not
   evidence. A *mismatching* id is a rejection — something title parsing can
   never assert. The ±1-year tolerance then applies only to results carrying
   no id at all. Expect this to change what the matcher accepts; it needs the
   existing matcher tests green plus new ones for the three cases.

### Phase 2 — query by id (owns the fan-out; decide before starting)

4. **Decide whether it is worth it.** Per-indexer querying means one request
   per enabled indexer instead of one aggregated call, merging results
   ourselves, gating on each indexer's declared `movieSearchParams` /
   `tvSearchParams`, and probably parsing Newznab XML rather than Prowlarr's
   JSON. Open question that changes the cost: does Prowlarr's `/{id}/api`
   honour `&o=json`? Measure the actual coverage gain first — it was 51
   releases against 49 on one film, which may not justify any of it.
5. **If yes, route the query.** `QueryBuilder` emits the id-shaped query for
   criteria that carry an id and for indexers that accept one, with the text
   query as the fallback for those that do not. Corpus keys must include
   whatever changes the result set.

## Completion criteria

Phase 1 (the committed scope):

* `SearchResult` carries the ids the indexer sends, and they survive the
  corpus round-trip.
* Plans and pursuits carry an IMDb id where TMDB supplies one.
* `TitleMatcher` treats a matching id as a verdict and a mismatching id as a
  rejection; the ±1-year tolerance applies only to id-less results.
* No regression in what the matcher accepts for results that carry no id.

Phase 2 is complete when it is either shipped against the criteria written at
the time, or **explicitly declined in this file with the reason** — an
undecided Phase 2 left dangling is exactly the drift ADR-042 warns about.

## Pointers

* `lib/media_centaur/search/prowlarr.ex` — the capability findings and the
  gotcha about silently ignored parameters live in its moduledoc.
* `lib/media_centaur/search/title_matcher.ex` — the ±1-year rule this replaces.
* `lib/media_centaur/search/search_result.ex` — where the discarded ids arrive.
* `lib/media_centaur/library/external_ids.ex` — where we already keep them.
* `GET /api/v1/indexer/<id>` — `searchParams` / `movieSearchParams` /
  `tvSearchParams` / `limitsMax` per indexer.
* `GET /{indexerId}/api?t=movie&imdbid=…&apikey=…` — the per-indexer Newznab
  route that actually honours ids. Phase 2 only.
