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

Planning, no code. Blocked on one unanswered question (step 1 below) — the
probe that would have answered it was invalidated when the only enabled
indexer entered back-off during the investigation that opened this campaign.

## Decisions made

* `2026-09-06` — Deferred out of the movie best-of-both-terms work rather than
  folded in: it needs identifiers plumbed onto plans and pursuits, and careful
  handling of a fan-out across indexers with differing capabilities. Commits
  `76994d0`, `24fb572`.
* `2026-09-06` — The generic search type (`type=search`) honours **only** `q`.
  Any id search must therefore also set the matching search type, which is why
  earlier `imdbId` probes appeared to do nothing. Measured on Prowlarr
  2.4.0.5397; recorded in the `Search.Prowlarr` moduledoc.
* `2026-09-06` — Not adopting `limit` as a companion lever. Indexers advertise
  a `limitsMax` (100 typical) and Prowlarr pages upstream to satisfy a larger
  one, so raising it multiplies requests against rate-limiting indexers.
  Category scoping is the cheaper narrowing lever and already shipped.

## Next steps

1. **Answer the blocking question.** On a rested indexer, probe
   `type=movie` + `imdbId` against a known film, with a control query before
   and after and an `/api/v1/indexerstatus` check after **every** request — a
   `200 []` means "no results" *or* "every indexer is backed off", and an
   unvalidated empty result is worthless. If the aggregated endpoint does not
   honour it, this campaign closes here.
2. **Decide the fallback contract.** One search fans out to every enabled
   indexer, and `searchParams` differ per indexer. Establish whether an id
   query loses coverage on indexers that only accept `q`, and if so whether the
   design is id-plus-text (two searches, union) or id-only for capable
   indexers. This is the real architectural question, not the plumbing.
3. **Carry the identifiers.** `Library.ExternalIds` already stores tmdb / imdb
   / tvdb per container; `acquisition_plans` and `acquisition_pursuits` carry
   only `tmdb_id`. TMDB supplies `imdb_id` and `Tmdb.Mapper` already extracts
   it. Migration plus capture at plan/pursuit creation.
4. **Use the ids we already receive.** `SearchResult` discards `imdbId` /
   `tmdbId` / `tvdbId` from every response. Capturing them lets `TitleMatcher`
   short-circuit to an exact verdict — and, just as valuable, turn a
   *mismatched* id into a definite rejection, which title parsing cannot do.
5. **Route the query.** `QueryBuilder` emits the id-shaped query and search
   type where the criteria carry an id; `Prowlarr.search/3` forwards it.
   Corpus keys must include whatever changes the result set.

## Completion criteria

* A movie plan with a known IMDb id searches by id, and its results are
  identity-verified by id rather than by parsed title and year.
* A TV pursuit for a known season/episode searches by TVDB id plus season and
  episode where the indexer supports it.
* Coverage is provably not reduced on indexers that accept only `q` — a
  regression test pins the fallback.
* `TitleMatcher` treats a mismatched id as a rejection, and the ±1-year
  tolerance applies only to results that carry no id at all.
* The `Search.Prowlarr` moduledoc's "exact ID search exists and is not used
  yet" paragraph is either deleted or rewritten as the shipped contract.

## Pointers

* `lib/media_centaur/search/prowlarr.ex` — the capability findings and the
  gotcha about silently ignored parameters live in its moduledoc.
* `lib/media_centaur/search/title_matcher.ex` — the ±1-year rule this replaces.
* `lib/media_centaur/search/search_result.ex` — where the discarded ids arrive.
* `lib/media_centaur/library/external_ids.ex` — where we already keep them.
* `GET /api/v1/indexer/<id>` — `searchParams` / `movieSearchParams` /
  `tvSearchParams` / `limitsMax` per indexer.
