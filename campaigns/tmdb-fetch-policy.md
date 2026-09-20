---
status: planning
started: 2026-09-19
last_updated: 2026-09-20
---
# Ask TMDB only to learn something new

## Glossary

Working terms for this campaign. Established terms first; the three
marked *working* are named provisionally and settle with the owner
before code.

| Term | Meaning |
|---|---|
| **Fetch** | A call into `MediaCentaur.TMDB.Client`. It may be answered by the response cache or reach TMDB. |
| **Request** | A fetch that reaches TMDB: a miss, a revalidation, or a reload. A cache hit is not a request — the Connections tile's convention (commit `4a461106`). |
| **Response cache** | `MediaCentaur.HttpClient.Cache`: in-memory, keyed by URL with the API key excluded, fresh for exactly the `max-age` TMDB states (about an hour for search, eight for details), revalidated by ETag when stale. Dies with the process; 1 000 entries; one-week hard cap. |
| **Revalidation** | A conditional request (`If-None-Match`) on a stale entry. A 304 means unchanged and costs one small request; it renews freshness. |
| **Reload** | `reload: true`: a fetch past a fresh entry that sends no conditional header and overwrites the entry. Used by the release-tracking refresher's three detail calls and by the `/configuration` probe. |
| **Stored metadata** | TMDB-derived fields persisted in the app's own records: library entities, tracked items and their releases, title snapshots, artwork on disk. |
| **Title snapshot** | `MediaCentaur.TMDB.Title` — name, year, release date, poster and backdrop paths, overview — embedded on `title_intents` and `activities` so a surface can paint a title without a fetch. Carries no fetch time. |
| **Check** *(working)* | A fetch whose purpose is to learn whether stored metadata has changed since the app last asked. |
| **Release facts** *(working)* | The TMDB fields that change over a title's life: typed release dates, air dates, episode lists, season count, status, next episode to air. Everything else — identity, description, cast, artwork paths — is treated as fixed once known. |
| **Settled title** *(working)* | A title whose release facts can no longer change: a released movie past its last typed date, a series that has ended or been cancelled with every episode aired. |

## Goal

Every TMDB request should be justified by a question the app cannot
answer from what it already stores. Today the app has one cache — the
HTTP response cache, transparent and hours-long — and no policy above
it: the release-tracking refresher reloads every tracked title every
six hours whether or not anything about it can still change, several
surfaces read release facts live on every open because nothing stores
them, and library metadata is frozen at import with no record of when
TMDB was last asked. The owner's rule (2026-09-14): TMDB is consulted
when the app is *seeking new information*, such as whether a release
date has been announced, never on open for its own sake.

Waste scales with the library, the watchlist and the tracked set, and
no current fetch site costs less as a title settles. The one day
measured on the owner's instance (15 API requests, 12 of them the
refresher re-reading five tracked titles twice) is a quiet-day sample,
not a ceiling: the model must not be wasteful at any size. Coherence is
the second driver — seven stored copies of a title's name, dates that
diverge between the calendar and the detail view — with the latency of
render-time fetches and the empty cache after every restart on top.

## Status

Planning. Audit complete 2026-09-19 (three inventories under
[`docs/superpowers/specs/2026-09-19-tmdb-fetch-policy-research/`](../docs/superpowers/specs/2026-09-19-tmdb-fetch-policy-research/)).
Definition agreed 2026-09-20 (Decisions); settled-title rule and
check schedule open; no design, no code.

## Audit — every TMDB fetch, by what it asks

Thirty fetch sites. Grouped by the question asked and whether a
stored copy could answer it. Endpoint shorthand: `movie`, `tv`,
`season`, `collection`, `search`, `configuration`. Full table with
file:line in `research/call-sites.md`.

### A. Identity resolution — nothing stored can answer a fresh query

| # | Use case | Trigger | Endpoints |
|---|---|---|---|
| 10 | Omnibox search on Incoming | user types (debounced) | `search/multi`, or `search/movie` + `search/tv` with a year |
| 11 | Match-picker search on Review | user submits | `search/movie` or `search/tv` |
| 12 | Discovery pipeline identifies a new file | Broadway processor | `search/movie` and/or `search/tv` |

Justified. Repeated queries are answered by the response cache for an
hour, but the key is case- and whitespace-sensitive: the same title
typed twice with different capitalisation is two requests.

### B. Creating the stored copy — first contact with a title

| # | Use case | Trigger | Endpoints | Stored copy consulted first? |
|---|---|---|---|---|
| 13 | Import pipeline fetches metadata | Broadway processor | `movie` (+`collection`), `tv` (+`season`) | No — runs on every payload. A new episode of a known series refetches the series and season, then discards the series on the `find_or_insert_by` hit. |
| 5, 6 | Follow a title (rung to Follow or above) | user click | `tv` + `season` per fetched season, or `movie` | Creates the tracked item; the clicked title snapshot already holds name/year/poster/overview. |
| 7 | Open a title no record knows (deep link) | page param | `movie` or `tv` | Yes — intent snapshot, library entity, activity snapshot, page snapshot are all tried first. |

Justified in purpose. #13's refetch of a known parent is the exception.

### C. Scheduled checks — seeking new information by design

| # | Use case | Trigger | Endpoints | Reload? |
|---|---|---|---|---|
| 1 | Refresher: TV item | timer, `release_tracking_refresh_interval_hours` (default 6) | `tv`, then `season` for the last library season and the next-to-air season | `tv` yes; `season` **no** |
| 2 | Refresher: collection item | same | `collection` | yes |
| 3 | Refresher: movie item | same | `movie` | yes |
| 4 | Refresher: artwork backfill | same tick, phase 3 | CDN only, roles missing on disk | n/a |

Justified in purpose; wrong in three ways. Every item is re-read every
cycle: no per-item due time, no notion of a settled title, no skip
when the last check found nothing. The detail calls reload past a
fresh entry because the 8-hour `max-age` outlasts the 6-hour interval,
where a revalidation would return 304 for the unchanged majority. The
commit replaces every release row wholesale even when the payload is
identical, so row ids churn every cycle. `last_refreshed_at` — the only
fetch timestamp in the app — is written every cycle and read only to
compute the first delay after boot.

### D. Render-time reads of release facts the app could store

| # | Use case | Trigger | Endpoints | Why live |
|---|---|---|---|---|
| 8 | Preview panel on an unowned title detail | modal open | `movie` or `tv` | Cast, runtime, genres, seasons, and the movie's release window are never persisted. |
| 14 | Series targeting universe (plan picker) | plan modal open; "download missing episode"; TV plan creation | `tv` **plus one `season` per season** | Per-episode aired-or-not; `Library.Season.episode_list` and `Item.season_sizes` hold overlapping facts, not consulted. |
| 15 | Movie plan door fills external ids | plan creation | `movie` | `Item.imdb_id` / `original_title` already stored for tracked titles, not consulted. |
| 16 | Movie plan board release window | board open or re-read | `movie` | Deliberately not stored: "a draft can sit for days… must read as TMDB says it today". |
| 17 | Movie plan targeting preview | plan modal open | `movie` | Not stored. |
| 18 | Cour detection for a TV search | `PursueTarget` job on the 15-minute pursuit cron; `RunPlan`; forced re-search | `season` per distinct season | "Recomputed on demand — nothing persisted." |
| 19 | Reconciliation spine | show selected on `/reconcile` | `tv` **plus one `season` per season** | Chooses TMDB over `episode_list` by design ("never the library's possibly-incomplete season rows"). |

All answered by the response cache for eight hours, then a request
each, and all cold after a restart. Each asks a release-facts question
whose answer changes only while the title is unsettled.

### E. Artwork — disk is the ledger

| # | Use case | Trigger | Endpoints |
|---|---|---|---|
| 9 | Detail artwork for an unowned title | render | none (disk) |
| 20 | Artwork warm for a referenced identity | rung raised; activity stored; Discovery mount; pursuit/plan board open | `movie`/`tv` for image paths, then CDN — only when a role is missing |
| 26, 27 | Maintenance: repair missing images / refetch backdrops | Settings | detail endpoints per entity, rebuild branch only |
| 28 | Manage → refresh this title's artwork | user click | `movie`/`tv`/`collection` |
| 29 | Mix task: re-download undersized tracking art | manual | `tv`, `collection`, `movie` |

Sound. The detail fetch exists only because image source paths are
discarded after download (`pipeline_image_queue` is the sole, transient
holder), so any repair must refetch the whole payload.

### F. Probes and maintenance

| # | Use case | Trigger | Endpoints |
|---|---|---|---|
| 21 | Test connection (Settings, Setup) | user click | `configuration`, always reload |
| 22 | Availability probe while down | Oban, every 300 s while down | `configuration`, always reload |
| 23, 24, 25 | Maintenance: refresh movie credits / series credits / episode lists | Settings | detail endpoints; skip rows already complete |
| 30 | `mix seed.showcase` | manual | search + detail |

Sound; out of scope.

## Findings

1. **No policy layer exists.** The response cache decides by TMDB's
   headers alone; every caller decides for itself whether to reload,
   and only the refresher and probe do. Nothing expresses *why* a
   fetch is being made.
2. **The refresher is the one place that seeks new information on
   purpose, and it does so without looking at what it stored.** Every
   item, every cycle, full reload, wholesale replace. A settled title
   costs the same as one airing tonight.
3. **Release facts are stored in the wrong places or not at all.**
   Typed release dates (the release window), cours, the season spine and
   the targeting universe are rebuilt live on every open. Air dates
   live in five tables; the calendar's copy is replaced every six hours
   while the library's is frozen at import.
4. **Only tracked items know when TMDB was last asked.** Library
   entities, title snapshots and activities carry no fetch time, so
   "is this stale" cannot be answered for them.
5. **Import refetches known parents.** A new episode file fetches the
   series and season details again and discards the series result.
6. **Artwork refresh refetches the detail payload** because source
   paths were never stored.
7. **Search cache keys are not normalised** — capitalisation and
   whitespace make distinct requests.
8. **The response cache has no stale-if-error path** — a stale copy is
   not served when TMDB fails — and is not persisted, so every restart
   starts cold. Each is weighed on its own merits.
9. **The wiki disagrees with itself**: Release-Tracking.md says the
   refresh interval defaults to 6 hours, Troubleshooting.md says 24.

## Decisions made

Append-only.

* `2026-09-14` — **TMDB is consulted only when seeking new
  information.** Owner, closing the title-detail-unification review;
  recorded in memory, campaign opened 2026-09-19.
* `2026-09-20` — **Seeking new information means a check on the
  release facts of an unsettled title.** Everything else — description,
  cast, artwork, and any fact of a settled title — renders from stored
  metadata with no fetch, including on open. Owner.
* `2026-09-20` — **The title's Manage view carries a manual refresh
  control**, so a check can be forced for any title regardless of the
  policy. Owner.
* `2026-09-20` — **A one-day traffic sample is not a basis for the
  design.** The model must not be wasteful at any library size. Owner.

## Open questions for the owner

In order; each answer shapes the next.

1. **What a settled title is**, in the code's own terms: a movie's
   `ReleaseWindow` stage (`:unreleased | :theatrical | :home | :unknown`)
   and `status`; a series' `status` (`:returning | :ended | :canceled |
   :in_production | :planned`) and `next_episode_to_air`. Where the rule
   lives.
2. **Where the check schedule lives.** One global interval (today), or
   a due time per title derived from its stored release facts — next
   episode to air, announced release date, none announced.
3. **Which surfaces move to stored reads, and what gets stored where.**
   The release window and season air dates have no home; the title
   snapshot has no fetch time; a title-level record would touch
   `collection-identity`'s territory.
4. **Checks revalidate rather than reload**, and skip the write when
   the answer is 304.
5. **Response cache changes**: normalise the search key; stale-if-error;
   persistence. Each weighed on its own merits.
6. **The manual refresh control**: on the Manage view of owned titles
   (decided); whether tracked-but-unowned titles get the same control,
   and where.

## Next steps

1. Settle questions 1–2 with the owner in this session. Restate the
   working terms as the app's own controls before asking.
2. Write the design at
   `docs/superpowers/specs/2026-09-19-tmdb-fetch-policy-design.md`;
   elevate the agreed glossary to `docs/GLOSSARY.md` at completion.
3. Fix the wiki cadence contradiction with whatever cadence the design
   lands on.

## Completion criteria

* Every fetch site is one of: creates a stored copy that did not exist;
  a check on an unsettled title; identity resolution for a query; a
  probe. A Credo check or a client-level contract enforces the
  classification.
* No render path requests TMDB for a fact the app stores.
* A settled title costs zero requests per cycle; an unsettled one costs
  one revalidation per due check, measured on the dev node through
  `HttpClient.Traffic`.
* The wiki's Release-Tracking, Troubleshooting and TMDB-API-Key pages
  describe the shipped cadence and agree with each other.

## Pointers

* Research inventories:
  [`call-sites.md`](../docs/superpowers/specs/2026-09-19-tmdb-fetch-policy-research/call-sites.md),
  [`response-cache.md`](../docs/superpowers/specs/2026-09-19-tmdb-fetch-policy-research/response-cache.md),
  [`stored-metadata.md`](../docs/superpowers/specs/2026-09-19-tmdb-fetch-policy-research/stored-metadata.md).
* [ADR-064](../decisions/architecture/2026-09-04-064-outbound-http-seam.md) —
  the outbound HTTP seam and origin-freshness cache.
* Recurring-traffic audit (closed 2026-09-18, README *Complete*) — left
  "how often the refresher re-reads a healthy TMDB" to this campaign.
* `collection-identity.md` — a collection has a TMDB id but is not a
  title; any title-level store must not pre-empt it.
* Key modules: `MediaCentaur.ReleaseTracking.Refresher`,
  `MediaCentaur.HttpClient.Cache`, `MediaCentaur.TMDB.Client`,
  `MediaCentaur.TMDB.Title`, `MediaCentaur.TMDB.ReleaseWindow`,
  `MediaCentaur.Acquisition.Targeting`, `MediaCentaur.Acquisition.Cours`,
  `MediaCentaur.Reconciliation.Spine`, `MediaCentaurWeb.TitleDetailHost`.
