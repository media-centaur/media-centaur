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
**Phases 1, 2 and 3 landed on main 2026-09-20** (unpushed). Phase 1: the
store, filled by write-through. Phase 2: `TMDB.CheckJob` checks what is
due (`@reboot` and every quarter hour), `TMDB.References` says who
holds a title and whose hold schedules a check, release tracking
rebuilds its calendar from the store on change, the tracked item
carries no TMDB fact of its own, the refresher and both interval
settings are gone, *Refresh from TMDB* is on the Manage toolbar and the
tracking card (UIDR-044), the wiki is rewritten (committed locally, not
pushed, with the code). Phase 3: every surface outside the pipeline
reads the store — the unowned preview, the plan board and plan door,
targeting, cours, the reconciliation spine, the artwork warm — the
title intent's embedded snapshot is dropped (the watchlist and the
detail host paint from the store), listed and planned titles schedule
checks, and the undersized-art mix task is retired. Phase 4 next.

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
* `2026-09-20` — **A settled title.** A movie is settled at release
  stage `:home`, or when its primary release date is more than 180 days
  past with no typed home date, or when canceled. A series is settled
  when ended or canceled with no future air date known. Owner; the
  180-day figure is provisional.
* `2026-09-20` — **A distant date does not need to be learned quickly.**
  When no next release is known, checking often is pointless: whatever
  date appears will be far enough out that learning it days later costs
  nothing. Check cadence follows the distance to the next known event,
  not a clock. Owner.
* `2026-09-20` — **The due-time rule.** Each unsettled title stores its
  next known event (next air date; next typed movie date, else the
  primary date). A check is due the day after that event or 7 days
  after the last check, whichever comes first. A settled title is never
  due; the Manage view's manual refresh is the only way to check one.
  The *Refresh interval (hours)* setting is removed, not repurposed.
  Owner.
* `2026-09-20` — **One TMDB title record per identity, payload-backed,
  movies and series only.** Every surface reads it; only checks write
  it. Extending the existing tables was declined; normalised columns
  were declined in favour of the stored payload so every `from_payload`
  constructor keeps working. Owner.
* `2026-09-20` — **Full coherence, not a bolt-on.** The owner asked for
  the whole application to be reconciled with the record, using the
  unify-design method. Design:
  [`2026-09-20-tmdb-fetch-policy-design.md`](../docs/superpowers/specs/2026-09-20-tmdb-fetch-policy-design.md).
* `2026-09-20` — **Design approved as written; the six §7 decisions
  stand.** The Phase 4 question — which library fields TMDB may
  overwrite on an owned entity — follows from the core idea: every
  field `TMDB.Mapper` produces is a projection. Owner (`/approve-and-execute`).
* `2026-09-20` — **Phase 1 implementation decisions.** A served
  response-cache entry carries the origin's ETag, so the store learns a
  validator without a request. A check decides *changed* by comparing
  payloads, never timestamps. A first-contact race (two processes, one
  new title) is retried once as an update. An id that is not a TMDB id
  is refused; a store write never fails the fetch that fed it. The
  `scheduled` column waits for Phase 2, which defines references.
  ([ADR-071](../decisions/architecture/2026-09-20-071-tmdb-store-one-record-per-title.md);
  plan
  [`2026-09-20-tmdb-fetch-policy-phase-1-plan.md`](../docs/superpowers/plans/2026-09-20-tmdb-fetch-policy-phase-1-plan.md))
* `2026-09-20` — **The stored payload drops the credits blocks** (a
  title's `credits`/`aggregate_credits`, a season's `credits`, an
  episode's `guest_stars`/`crew`); Phase 4's import requests credits
  once, separately. Owner, on the Phase 1 measurement (26 KB / 245 KB /
  485 KB). Design §2.1 amended.
* `2026-09-20` — **Scheduled-ness is a query, not a column.** Whether a
  stored title is checked is decided by a reference predicate at the
  moment the checker runs (tracked in Phase 2; listed, owned and planned
  as later phases move those readers onto the store). A stored flag
  would be a second representation of "who references this identity".
  Design §2.1/§2.4 amended.
* `2026-09-20` — **Phase 2 landed.** Decisions made inside it:
  `TMDB.References` (the design's Phase 5 unification of the artwork
  hold providers) pulled forward, because scheduling needs "who
  references this identity"; scheduling scope in Phase 2 is tracked
  titles only — Discovery and Acquisition providers answer
  `schedules_checks?/0` false until Phase 3 gives them readers,
  Activities never; the refresher's collection branch deleted with it
  (no such item exists; noted in `collection-identity`); the sweep
  interval setting removed with the refresher; no record sweep yet
  (Phase 5). Two defects found by the suite: the store refuses a payload
  that is not the title's own answer, and a dateless theatrical release
  is unscheduled rather than a crash in the upcoming feed. Plan:
  [`2026-09-20-tmdb-fetch-policy-phase-2-plan.md`](../docs/superpowers/plans/2026-09-20-tmdb-fetch-policy-phase-2-plan.md);
  [UIDR-044](../decisions/user-interface/2026-09-20-044-refresh-from-tmdb.md).
* `2026-09-20` — **The stored payload keeps a top-10 cast** (by TMDB
  `order`) and the Directing crew of a title; the rest of the credits
  decision stands. Owner, on the Phase 3 question of what the unowned
  preview shows: the preview's cast row is a render of stored data, not
  a reason to fetch.
* `2026-09-20` — **Phase 3 landed.** Decisions made inside it: a title
  intent's snapshot is the store's, attached on read
  (`Discovery.Titles`), and a listed title the store has not
  first-contacted carries a *bare identity* (a `TMDB.Title` with only
  its identity set) rather than nil, so rows render without guards
  until the record lands; `Discovery.put_rung/3` announces the title
  the person acted on (always named, so a listing from Ignored can
  still be shared) and `forget/2` the store's snapshot; the detail host
  opens from `Store.snapshot/1`; Discovery and Acquisition providers
  schedule checks; `mix media_centaur.refresh_tracking_images` retired
  (design row V). The transitional write-through stays for Phase 4's
  callers, import and rematch. Plan:
  [`2026-09-20-tmdb-fetch-policy-phase-3-plan.md`](../docs/superpowers/plans/2026-09-20-tmdb-fetch-policy-phase-3-plan.md).
* `2026-09-20` — **Phase 3 verified on the dev node** after a service
  restart: the migration ran at boot (`title_intents.title` gone); the
  `@reboot` tick completed in 5 ms with nothing to first-contact — all
  eight referenced titles (eight listed, five of them tracked) were
  already held, the three listed-only ones by the transitional
  write-through before Phase 3 (the tick first-contacts *scheduled*
  references only; corrected 2026-09-20 while planning Phase 4);
  opening an unheld title's detail from the
  watchlist URL made exactly one request (`/3/movie/{id}`, response
  cache miss, record stored and settled), and opening it again made
  none. The traffic ring showed no other TMDB request in the two hours
  around the restart. The probe record was deleted afterwards; Phase 5's
  retention sweep is what removes such unreferenced records in general.
* `2026-09-20` — **Phase 2 verified on the dev node** after a service
  restart: the migration ran at boot; the `@reboot` tick first-contacted
  the three tracked titles the store lacked (0.5 s, three requests) and
  the store holds all five; two titles forced due were checked and their
  calendars rebuilt through the listener (the series' ten releases and
  its season sizes re-derived from the store); a first-contact payload
  now weighs 2–15 KB for a movie and 7 KB for a series with the credits
  dropped. Cost per tracked title: **before** 4 reloads a day (28 a
  week, forever); **after** one revalidation a week while unsettled, one
  more the day after its next date, zero once settled. The `@reboot`
  tick fires on the first minute boundary after boot and can race the
  capability cache on an unlucky second — it then holds, and the
  quarter-hour tick catches up; accepted.

## Open questions for the owner

None. The payload-size question was decided 2026-09-20 (Decisions).

## Next steps

1. Phase 4 plan: import and the library are projections —
   `Pipeline.Stages.FetchMetadata` through `Store.ensure/2` and the
   stored season (a check when a file names an episode the stored
   season lacks), credits requested once at materialisation (design
   §2.1 amendment), `Library.TmdbProjection` re-applying `Mapper` output
   on `{:tmdb_title_changed, ref}`, the three Maintenance refresh
   buttons consolidated or removed after measuring what they still fix,
   `Review.Rematch` and the showcase seeder through the store, the
   transitional write-through removed with the last detail caller.
2. At the next release, the CHANGELOG's *Migration safety* lines:
   `20260920100000_create_tmdb_store` (two additive tables),
   `20260920130000_release_tracking_items_read_the_store` (eight
   columns dropped, three settings rows deleted; the store refills from
   TMDB at boot) and `20260920150000_title_intents_read_the_store` (one
   column dropped; the watchlist paints from the store once the boot
   tick has first-contacted listed titles), plus the user-visible
   change: the refresh-interval setting is gone and *Refresh from TMDB*
   is new.

## Completion criteria

* Every fetch site is one of: first contact; a check; identity
  resolution for a query; a probe. No module but `TMDB.Store` calls a
  `TMDB.Client` detail function, enforced by a Credo check.
* No render path requests TMDB for a fact the app stores; every
  projection in the design's §2.6 is rebuilt from the store, never
  fetched.
* `ReleaseTracking.Refresher`, the interval setting, the intent embed
  and the `Item` copy columns are gone; collections are recorded as the
  `collection-identity` campaign's convergence point.
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
