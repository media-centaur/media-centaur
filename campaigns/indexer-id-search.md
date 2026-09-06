---
status: active
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

**Phase 1 shipped**, 2026-09-06 — every completion criterion below is met and
`mix precommit` is green. Verified against the live indexer, not only fixtures:
a search for a public-domain film returned 100 results all carrying ids, of
which the id path accepted one the title path rejected
(`Nosferatu.A.Symphony.of.Horror.1922.…` — the subtitle in the release name
defeats title matching) and newly rejected none. **Phase 2 remains undecided**
and is the only open item.

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
* `2026-09-06` — **The aggregated response already carries the ids.** Measured
  against the live instance: every result carries `imdbId`, `tmdbId`, `tvdbId`
  (and `tvMazeId`) as **integers**, with `0` meaning absent, and IMDb ids
  arrive without the `tt` prefix or zero-padding (`1727587` → `tt1727587`).
  Every id is normalized at the boundary to the string spelling
  `Library.ExternalIds` already uses, so one representation crosses the whole
  system.
* `2026-09-06` — **Coverage is real but partial.** In the observed setup only
  the usenet indexer populated ids; public torrent indexers largely do not. The
  id path is therefore strictly additive — a result carrying no id keeps the
  title + ±1-year treatment unchanged.
* `2026-09-06` — **Phase 1 covers tvdb and tmdb, not IMDb alone.** Newznab TV
  results carry `tvdbId` far more often than `imdbId`, and `TMDB.Client.get_tv`
  already appends `external_ids`, so the tvdb id costs nothing to obtain.
  `tmdb_id` needs no new storage at all — plans and pursuits already carry it;
  it only needed projecting onto `Criteria`.
* `2026-09-06` — **Doors snapshot the ids; nothing resolves them centrally.**
  The first design put a single `TMDB.Identifiers` fetch inside
  `Plans.create_plan/2` so all four plan doors got the ids for free. Rejected:
  it puts an HTTP call in the synchronous path of a user's click, and makes
  every plan-creating test depend on a TMDB stub. The ids instead ride the
  route `origin_country` already travels — snapshotted at the door that already
  holds the TMDB payload (`Targeting.Selection`, `Detail.TitlePreview`,
  `ReleaseTracking.Item`) and carried plan → pursuit → recipe → criteria. Only
  the Discovery one-click movie door holds no payload, and it fetches its own
  inside the background task it already runs in.
* `2026-09-06` — **`TMDB.Identifiers` is the one module that knows where TMDB
  puts these ids** (top level for a movie, the appended `external_ids` block
  for a series). `TMDB.Mapper` reads through it too, so library ingestion and
  acquisition can never disagree about a title's IMDb id.
* `2026-09-06` — **`Plans.MatchCriteria` collapses five copies of one
  projection.** `RunPlan` and `Alternatives` each built `%Search.Criteria{}`
  from a plan by hand, in five places, which is how a newly carried identifier
  reaches some searches and not others. One projection now serves them all.
  (Note the vocabulary collision it navigates: `plan.criteria` is the quality
  snapshot, `Search.Criteria` is the match input — different ideas, similar
  names.)
* `2026-09-06` — **An id verdict settles identity, not scope.** A `tvdbId`
  names the *series*, so an id match replaces the title check only; season and
  episode still have to match, and a movie must still parse as a movie. Any one
  id matching outweighs another disagreeing (indexers mis-tag one field more
  often than they get all of them wrong).
* `2026-09-06` — Not adopting `limit` as a companion lever. Indexers advertise
  a `limitsMax` (100 typical) and Prowlarr pages upstream to satisfy a larger
  one, so raising it multiplies requests against rate-limiting indexers.
  Category scoping is the cheaper narrowing lever and already shipped.

## Next steps

### Phase 1 — verify identity by id — DONE 2026-09-06

1. ~~Capture the ids we already receive.~~ `SearchResult` carries `imdb_id` /
   `tmdb_id` / `tvdb_id`, normalized to strings, and three corpus columns
   round-trip them.
2. ~~Carry the identifiers on the want.~~ `imdb_id` / `tvdb_id` on
   `acquisition_plans`, `acquisition_pursuits` and `release_tracking_items`
   (the last self-heals on refresh); `tmdb_id` needed only projecting.
3. ~~Teach `TitleMatcher` to prefer the id.~~ `compare_external_ids/2` returns
   `:match` / `:mismatch` / `:unknown`; `matches?/2` and `coverage/2` both gate
   on it, and the ±1-year tolerance now applies only to `:unknown`.

**Known gap, deliberate:** a movie want inside a *tracked collection* plans by
its part's TMDB id, and we hold no IMDb id for a part — those plans fall back
to title matching. Closing it means carrying ids on `ReleaseTracking.Want`,
which is worth doing only if collection parts turn out to mismatch in practice.

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

Phase 1 (the committed scope) — **all met, 2026-09-06**:

* ✅ `SearchResult` carries the ids the indexer sends, and they survive the
  corpus round-trip.
* ✅ Plans and pursuits carry IMDb and TVDB ids where TMDB supplies them.
* ✅ `TitleMatcher` treats a matching id as a verdict and a mismatching id as a
  rejection; the ±1-year tolerance applies only to id-less results.
* ✅ No regression in what the matcher accepts for results that carry no id —
  the full suite is green and the live probe rejected nothing it used to
  accept.

Phase 2 is complete when it is either shipped against the criteria written at
the time, or **explicitly declined in this file with the reason** — an
undecided Phase 2 left dangling is exactly the drift ADR-042 warns about.

## Pointers

* `lib/media_centaur/search/prowlarr.ex` — the capability findings and the
  gotcha about silently ignored parameters live in its moduledoc.
* `lib/media_centaur/search/title_matcher.ex` — `compare_external_ids/2` and
  the ±1-year rule it now supersedes for id-carrying results.
* `lib/media_centaur/tmdb/identifiers.ex` — where a TMDB title's IMDb / TVDB
  spelling comes from.
* `lib/media_centaur/acquisition/plans/match_criteria.ex` — the one projection
  from a plan to the criteria every plan-side search matches against.
* `lib/media_centaur/search/search_result.ex` — where the discarded ids arrive.
* `lib/media_centaur/library/external_ids.ex` — where we already keep them.
* `GET /api/v1/indexer/<id>` — `searchParams` / `movieSearchParams` /
  `tvSearchParams` / `limitsMax` per indexer.
* `GET /{indexerId}/api?t=movie&imdbid=…&apikey=…` — the per-indexer Newznab
  route that actually honours ids. Phase 2 only.
