# TMDB fetch policy — one record per title, asked only when due

**Status:** design, awaiting owner review · **Campaign:** [`campaigns/tmdb-fetch-policy.md`](../../../campaigns/tmdb-fetch-policy.md) · **Research:** [`2026-09-19-tmdb-fetch-policy-research/`](2026-09-19-tmdb-fetch-policy-research/)

Written with the unify-design method: the core idea, the greenfield
shape, the diff against the code, every incoherence with its
disposition, and the honest cost. Nothing here is implemented.

## Glossary

Established terms first; the working terms were agreed with the owner
on 2026-09-20 and are used without qualification below.

| Term | Meaning |
|---|---|
| **Identity** | `(media_type, tmdb_id)`, `media_type ∈ :movie \| :tv_series`. Already the app's key for a title (`TMDB.Title.ref/1`, `MediaCentaurWeb.TitleRef`). Collections are not identities in this design (see *Out of scope*). |
| **Fetch** | A call into `MediaCentaur.TMDB.Client`. |
| **Request** | A fetch that reaches TMDB. A response-cache hit is not a request. |
| **Response cache** | `MediaCentaur.HttpClient.Cache`, the in-memory, per-URL, origin-freshness cache of [ADR-064](../../../decisions/architecture/2026-09-04-064-outbound-http-seam.md). |
| **Revalidation** | A conditional request carrying `If-None-Match`; a 304 answer means *unchanged*. |
| **Release facts** | The fields that change over a title's life: typed release dates, air dates, episode lists, season count, status, next episode to air. |
| **Settled title** | A title whose release facts can no longer change. Movie: release stage `:home`, or primary date more than 180 days past with no typed home date, or canceled. Series: ended or canceled with no future air date known. |
| **Next known event** | The earliest release fact still ahead of today: a series' next air date; a movie's next typed date, else its primary date. `nil` when nothing is known. |
| **Check** | A revalidation of a stored title against TMDB, made because the title is due or because a person asked. The only way a stored title changes. |
| **Due** | A check is due the day after the next known event, or 7 days after the last check, whichever is first. A settled title is never due. |
| **TMDB store** | The new durable record of TMDB's last answer per identity, with its fetch time and due time — `MediaCentaur.TMDB.Store`. Name provisional; see *Decisions for the owner*. |
| **Projection** | Anything the app derives from a stored title: the calendar rows, the render snapshot, the release window, the targeting universe, the library entity's TMDB fields. A projection is rebuilt when its title changes, never fetched on its own. |
| **First contact** | The fetch that creates a stored title the app has never held. The only fetch that is not a check. |
| **Reference** | A reason the app holds a title: a library entity, a title intent, a tracked item, a plan or pursuit, an activity. Decides retention and whether checks are scheduled. |

## 1. Core idea

**The app's knowledge of a TMDB title is one record per identity —
TMDB's last answer, when it was learned, and when the app is next due
to ask — and everything else the app shows or schedules about that
title is a projection of that record.**

Every finding in the audit is a consequence of not having this: seven
copies of a name because there was no record to point at; a refresher
that reloads everything because nothing carried a due time; seven
surfaces fetching on open because the facts they need had no home;
library metadata frozen at import because nothing could tell it it had
changed.

## 2. Greenfield shape

### 2.1 The record

`MediaCentaur.TMDB.Store` is a context owning two tables.

**`tmdb_titles`** — one row per identity.

| Column | Meaning |
|---|---|
| `media_type`, `tmdb_id` | The identity. Unique together. |
| `payload` (map) | TMDB's detail answer as received (`movie/{id}` with `credits,release_dates,images`; `tv/{id}` with `aggregate_credits,external_ids,images`), except the `images` block, which is reduced to the three paths the app selects (poster, backdrop, logo). Stored as received so every existing `from_payload` constructor keeps working. *Amended 2026-09-20 after Phase 1 measured 26 KB / 245 KB / 485 KB for a movie, a series and one 38-episode season:* the credits blocks (`credits`, `aggregate_credits`, season `credits`, per-episode `guest_stars` and `crew`) are dropped too — they are read only at import, which in Phase 4 requests them once, separately, when it materialises a library entity. |
| `etag` | TMDB's validator for the payload. Owned here, not by the response cache. |
| `fetched_at` | When TMDB last answered — 200 or 304. |
| `changed_at` | When the payload last differed from what was stored. |
| `next_event_on` (date) | Derived from the payload; `nil` when nothing is known. |
| `next_check_at` (datetime) | Derived; `nil` when settled or unscheduled. |
| `settled_at` (datetime) | Set the first time the settled rule holds; cleared if a later check unsettles it (a revival). |
| ~~`scheduled` (boolean)~~ | *Amended 2026-09-20:* not a column. Whether a title is scheduled is a query over its references (§2.4), so it cannot drift from them — a stored flag would be a second representation of "who references this identity". `Store.due/1` selects due records that a reference predicate admits; the predicate widens phase by phase (tracked in Phase 2, listed in Phase 3, owned and planned in Phase 4). |

**`tmdb_seasons`** — one row per `(tmdb_id, season_number)` of a stored
series: `payload` (the `season/{n}` answer with `credits`), `etag`,
`fetched_at`, `changed_at`. A season has no schedule of its own; it is
checked with its series when it is *open* — it has an episode with no
air date or an air date ahead of today, or it is the series' latest
season — and never otherwise. A season a caller needs that is not stored
is a first contact.

### 2.2 The schedule — a pure function

`MediaCentaur.TMDB.Schedule.plan(media_type, payload, seasons, today, fetched_at)`
returns `%{next_event_on, next_check_at, settled?}`. No process, no
I/O. It encodes the two agreed rules:

* **Settled**: movie — `ReleaseWindow.from_payload(payload, today).stage == :home`,
  or primary date more than 180 days before `today` with no typed
  home date, or `status` canceled; series — `status ∈ {ended, canceled}`
  and no air date ahead of `today` in the payload or any stored season.
* **Due**: `min(next_event_on + 1 day, fetched_at + 7 days)`; `nil` when
  settled.

The 180 days and 7 days are module attributes, not settings.

### 2.3 Reads and writes

One module writes: `TMDB.Store`. Three entry points.

| Function | When | Effect |
|---|---|---|
| `Store.ensure(ref)` | a caller needs a title the app may not hold | returns the stored title; on a miss, first contact: fetch, store, derive schedule. Never a request when the title is stored. |
| `Store.season(ref, n)` | a caller needs one season | as above for `tmdb_seasons`. |
| `Store.check(ref)` | the title is due, or a person pressed *Refresh from TMDB* | revalidation with the stored ETag. 304: `fetched_at` moves, schedule re-derived (today moved). 200: payload and `etag` replaced, `changed_at` set, schedule re-derived, open seasons checked the same way, `{:tmdb_title_changed, ref}` published on a new `Topics.tmdb_titles/0`. |

Reads are plain functions: `Store.get(ref)`, `Store.seasons(ref)`,
`Store.due(now)`. Callers build what they need from the payload with
the constructors that already exist — `TMDB.Title.from_tmdb/2`,
`TMDB.TitleIdentity.from_payload/2`, `TMDB.Identifiers.from_payload/2`,
`TMDB.ReleaseWindow.from_payload/2`, `TMDB.Mapper.*_attrs`.

**No module but `TMDB.Store` calls a `TMDB.Client` detail function.**
Search and `configuration/1` stay callable from their present callers.
A Credo check (next free MC number) enforces this once the last caller
has moved.

### 2.4 Who is scheduled, and retention

A stored title is **scheduled** for checks while it has a reference
that means the user cares how it unfolds: a library entity, a title
intent at List or above, a tracked item, an open plan or pursuit. A
title held only through a friend's activity or a one-off open is
stored on first contact but never scheduled — otherwise the social
feed would drive unbounded checking. Scheduled-ness is a query over the
referencing tables at the moment the checker runs, never a stored flag
(amended 2026-09-20, see §2.1). An unscheduled title's record ages
until a person refreshes it or a reference schedules it; it is never
fetched on open.

A stored title with **no reference at all** is swept after 7 days,
together with its seasons and its artwork — the same lifetime
`TmdbArtwork` gives unreferenced art today. One module answers "who
references this identity" for both (§3, row R).

### 2.5 The checker

`MediaCentaur.TMDB.CheckJob`, an Oban cron worker on the `:maintenance`
queue every 15 minutes (the cadence the pursuit watcher already uses),
unique while running. It reads `Store.due(now)`, checks each with
bounded concurrency through the existing `TMDB.RateLimiter`, and
stops. It holds like every metered job: when
`IntegrationAvailability.available?(:tmdb)` is false it does nothing
and the next tick tries again; nothing is lost because due-ness is a
stored fact, not a timer.

The check itself is one revalidation per due title (plus one per open
season). For a title that has not changed that is a 304 with an empty
body.

### 2.6 Projections

Each is rebuilt from the stored payload when `{:tmdb_title_changed, ref}`
arrives or when it is first needed. None fetches.

| Projection | Built from | Rebuilt when |
|---|---|---|
| Calendar rows (`ReleaseTracking.Release`) for a tracked title | title + season payloads | the title changes (not every cycle) |
| Render snapshot (`TMDB.Title`) | title payload | on read; no longer stored on intents |
| Release window, release stage | title payload | on read |
| Series targeting universe, cours, reconcile spine | title + season payloads | on read |
| Plan identity (`TitleIdentity`, external ids) | title payload | at plan creation |
| Library entity TMDB fields, `Season.episode_list` | title + season payloads | at import; and when the title changes |
| Artwork paths for download, refresh, repair | title payload | on demand |

### 2.7 The manual refresh

*Refresh from TMDB* on the title's Manage view calls `Store.check/1`
regardless of due-ness and settledness. It reports one of three
outcomes in place: *unchanged*, *updated* (with what changed, from the
diff of projections), or *TMDB unavailable*. For a tracked title the
user does not own, the same control sits with the tracking controls on
the title detail.

### 2.8 Observability

`Log.info(:tmdb, …)` already narrates fetch outcomes. The store adds
one line per check — `checked movie tmdb:N — unchanged, next check in
7d` / `— changed (release window), next check 2026-10-03` — and one per
first contact. The Connections chart needs nothing new. The TMDB Status
tile may show *N titles scheduled · next check HH:MM*; that is an
aggregate, not a rehash, and is droppable.

## 3. Diff against the code — the incoherence ledger

Every TMDB-derived representation the audit found, with its
disposition. **Fix now** means within this campaign, in the named
phase; **keep** is an explicit decision that the representation is a
different idea, not a duplicate.

| | Representation today | Why it is incoherent with §2 | Disposition |
|---|---|---|---|
| A | Response cache holds detail payloads and ETags per URL, in memory | Two holders of "TMDB's last answer" and two ETags. | **Fix now, Phase 1.** Detail requests from `Store.check/1` carry their own `If-None-Match`; `HttpClient.Cache` passes through any request the caller made conditional (no lookup, no store). The response cache keeps ADR-064's role for search, `configuration`, and every other upstream. ADR-064 gets a dated amendment. |
| B | `TMDB.Client` detail functions called from ~20 modules | No single writer; no place a policy can live. | **Fix now, Phases 1–4**, one caller group per phase; Credo check enabled in Phase 5. |
| C | `ReleaseTracking.Refresher` GenServer: two timers, `reload: true`, every item every cycle | The schedule is a clock, not a fact about the title; the check is a reload, not a revalidation. | **Fix now, Phase 2.** Retired. `TMDB.CheckJob` schedules; `ReleaseTracking` reacts to change events. The want-ledger sweep (no TMDB) becomes its own small worker on the same cron pattern. |
| D | `ReleaseTracking.Item` columns `name`, `year`, `imdb_id`, `tvdb_id`, `original_title`, `origin_country`, `season_sizes`, `last_refreshed_at` | Copies of the payload; a second fetch clock. | **Fix now, Phase 2.** Columns dropped (paired migration). `Item` keeps identity, library link, `dismiss_released_before`, `last_library_season/episode`. Readers build `TitleIdentity` and season sizes from the store. |
| E | `ReleaseTracking.Release` rows replaced wholesale every cycle | Churn without change; ids unstable. | **Fix now, Phase 2.** Rebuilt only on `{:tmdb_title_changed, ref}` via the existing `replace_releases!/3` invariant. |
| F | Setting `release_tracking_refresh_interval_hours` | Describes nothing once the schedule is per title. | **Fix now, Phase 2.** Removed (settings row deleted by migration; wiki updated). |
| G | `Discovery.TitleIntent.title` embed (render snapshot, no fetch time) | A second representation of the title, silently ageing. | **Fix now, Phase 3.** Embed dropped (migration); the watchlist and the detail host read the store. The intent is `(identity, rung, source, note, activity_id)`. *Landed 2026-09-20 (Phase 3).* |
| H | `Activities.Activity.title` embed | *Different idea*: what the friend published, signed into the event. | **Keep.** Its artwork warm reads the store (first contact if unknown). |
| I | Detail-preview fetch on open (`TitleDetailHost.load_preview/2`) | Fetch on open, the owner's named anti-pattern. | **Fix now, Phase 3.** Reads `Store.ensure/1`; a title the app has never held costs one first contact, then never again. *Landed 2026-09-20 (Phase 3).* |
| J | Plan board release window fetched live ("must read as TMDB says it today") | The reader enforcing freshness instead of the store's policy. | **Fix now, Phase 3.** Reads the store; the comment is rewritten to say why that is now correct. *Landed 2026-09-20 (Phase 3).* |
| K | `Acquisition.Targeting` universe: `tv` + one `season` per season, every open | Fetch on open, multiplied by seasons. | **Fix now, Phase 3.** Reads title + seasons from the store. *Landed 2026-09-20 (Phase 3).* |
| L | `Acquisition.Cours` recomputed live on every pursuit tick | Fetch on a 15-minute cron for a fact that changes weekly at most. | **Fix now, Phase 3.** Reads stored seasons. *Landed 2026-09-20 (Phase 3).* |
| M | `Reconciliation.Spine` live, refusing `Season.episode_list` | The refusal was right — the library's list can be incomplete — but the store's season payload is complete. | **Fix now, Phase 3.** Reads stored seasons. *Landed 2026-09-20 (Phase 3).* |
| N | `Plans.movie_plan_attrs/1` fetches ids | Payload already stored for any planned title. | **Fix now, Phase 3.** *Landed 2026-09-20 (Phase 3).* |
| O | `TmdbArtwork.ensure/2` fetches the detail for image paths | Paths are in the stored payload. | **Fix now, Phase 3.** *Landed 2026-09-20 (Phase 3).* |
| P | `Pipeline.Stages.FetchMetadata` fetches on every payload; a new episode refetches its series and season and discards the series | Import is first contact when the title is unknown and a projection otherwise. | **Fix now, Phase 4.** `Store.ensure/1` for the title; for the season, `Store.season/2`, and a check when the file names an episode the stored season lacks (the file is evidence the season changed). `Library.Inbound` unchanged. *Landed 2026-09-20 (Phase 4):* the import asks the library whether it owns the title — the stored copy for one it does, `Store.fetch_full/2` (credits kept by the import, the record refreshed) for one it does not; a new episode's season is fetched whole for its guest stars, a held episode reads the stored season. |
| Q | Library entity TMDB fields, `Season.episode_list`, `TVSeries.status` frozen at import; three Maintenance buttons backfill by hand | The library's copy is a projection with no rebuild trigger. | **Fix now, Phase 4.** A `Library.TmdbProjection` (name provisional) re-applies `Mapper` output to the entity on `{:tmdb_title_changed, ref}` for the fields that are TMDB's to change. *Refresh movie credits*, *Refresh series credits* and *Refresh episode lists* collapse into one *Re-apply TMDB metadata* action that runs the same projection over the library, or are removed if the projection makes them redundant — decided in the Phase 4 plan after measuring what the buttons still fix. *Landed 2026-09-20 (Phase 4)* as `Pipeline.TmdbProjection` — in the pipeline, since `Library` depends on nothing TMDB-shaped; every mapped field but the credits and the collection facts, plus season lists and episode details. The three buttons were removed (owner decision; on the owner's instance none repaired anything). |
| R | `TmdbArtwork` retention: four `HoldProvider`s + mtime TTL; `Library.Image` never stores source paths; `ImageRefresh`/`ImageRepair` refetch the detail | "Who references this identity" answered once for art and not at all for titles; a second fetch for paths the payload holds. | **Fix now, Phase 5.** One `TMDB.References` module (the four hold providers plus the library) answers for both the store sweep and the artwork sweep; `ImageRefresh`/`ImageRepair` read paths from the store. `TmdbArtwork`'s disk layout and `urls/2` are unchanged. *Landed: the detail reads 2026-09-20 (Phase 4) — `ImageRefresh` / `ImageRepair` read the store; the store sweep 2026-09-20 (Phase 5) — `TMDB.RetentionPolicies` beside the artwork policy, both asking `TMDB.References.all/0`, each measuring age its own way (last fetch, last use).* |
| S | `Review.PendingFile.candidates` | *Different idea*: identity candidates for a match, from search. | **Keep.** |
| T | Search cache key case- and whitespace-sensitive | Same question, two requests. | **Fix now, Phase 1.** `TMDB.Client` normalises the query (trim, collapse whitespace, case-fold) before the request; the key follows. |
| U | `TMDB.Identifiers.fetch/3` — public, TMDB-hitting, no caller | Dead. | **Fix now, Phase 1.** Deleted. |
| V | `mix media_centaur.refresh_tracking_images` | A one-off for undersized legacy art; fetches the detail for paths. | **Fix now, Phase 3.** Reads the store, or is retired if no undersized art remains on the owner's instance — checked in Phase 3. *Retired 2026-09-20 (Phase 3): the store's first contact carries the paths, and the artwork warm reads them; no separate pass remains.* |
| W | `Showcase` seeder fetches live | A seed tool for a separate database. | **Keep**, routed through `Store.ensure/1` so the showcase DB also holds records — no policy change. *Landed 2026-09-20 (Phase 4) through `Store.fetch_full/2` — the seeder keeps the credits, like the import.* |
| X | Collections: `Refresher`'s `collection/{id}` branch, `MovieSeries` metadata never refreshed | A collection is not an identity in this design. | **Scheduled convergence**: stays on today's path until [`collection-identity`](../../../campaigns/collection-identity.md) decides what a collection is; that campaign then gives it a store row or deletes the path. Recorded there. |
| Y | Wiki: 6-hour vs 24-hour refresh interval | Stale prose. | **Fix now, Phase 2**, with the cadence change. |
| Z | Response cache: no stale-if-error, not persisted | With the store above it, detail reads never depend on it; search tolerates a cold start. | **Declined.** Recorded in the campaign. |

## 4. The honest cost

This is a five-phase, multi-session campaign, not a fix.

| | |
|---|---|
| Modules touched | about 50 (every `TMDB.Client` caller, the refresher and its helpers, four LiveView hosts, the pipeline's metadata stage, the maintenance section, two Credo checks) |
| Migrations | three, each paired and idempotent per house rule: create `tmdb_titles` + `tmdb_seasons`; drop the eight `Item` copy columns and the interval setting; drop the intent embed |
| Retired | `ReleaseTracking.Refresher`, its `RefreshSchedule`, the interval setting, `Identifiers.fetch/3`, possibly a mix task and three maintenance buttons |
| New | `TMDB.Store` (+ two schemas), `TMDB.Schedule`, `TMDB.CheckJob`, `TMDB.References`, `Library.TmdbProjection`, one PubSub topic, one Credo check, one ADR, one UIDR (the Manage-view control) |
| One-time | a backfill that gives every known title a record: bounded, rate-limited, held while TMDB is down. Its size is the library plus the watchlist plus tracked items; on the owner's instance about 40 titles and 50 seasons. |
| Risk | Phase 4 (pipeline + library projection) is the delicate one: Broadway stages, TMDB stubs, and the rule for which library fields TMDB may overwrite. |

The bolt-on the owner declined — due times on `Item`, a fetch time on
the intent embed — would have been two sessions and would have left
rows D, G, I–O and Q as they are.

## 5. Phases

Each phase leaves a working, shippable product; nothing is dark for
more than one release.

1. **The store, filled organically.** Schema and migration; `TMDB.Store`
   with `ensure`/`season`/`check`/`get`/`due`; `TMDB.Schedule`; the
   `HttpClient.Cache` pass-through for caller-conditional requests;
   `TMDB.Client` writes every detail payload it fetches into the store
   (write-through), so existing callers fill it without changing.
   Search-key normalisation. `Identifiers.fetch/3` deleted. ADR written;
   ADR-064 amended. Glossary rows added. No behaviour change visible.
2. **Checks replace the refresher.** `TMDB.CheckJob`; `ReleaseTracking`
   rebuilds releases on change; `Item` shrinks; the refresher and the
   interval setting go; *Refresh from TMDB* on the Manage view and on the
   tracking controls (UIDR); the one-time backfill; wiki pages
   Release-Tracking, Settings-Reference, Troubleshooting, TMDB-API-Key.
   Measured on the dev node: a settled title costs zero requests per
   cycle; an unsettled one costs one revalidation per due check.
3. **Surfaces read the store.** Preview panel, plan board, plan preview,
   targeting, cours, spine, plan identity, `TmdbArtwork.ensure`; the
   intent embed dropped; the mix task read or retired. After this phase
   no LiveView, job or context outside the pipeline calls a detail
   endpoint.
4. **Import and the library are projections.** `FetchMetadata` through
   the store; `Library.TmdbProjection` on change; maintenance actions
   consolidated or removed; the pipeline is the last detail caller to
   move.
5. **Retention and the gate.** `TMDB.References` for both sweeps;
   `ImageRefresh`/`ImageRepair` from the store; Credo check enabled;
   Status tile aggregate if kept; glossary elevated; campaign closed by
   destination.

## 6. Testing

* `TMDB.Schedule` is pure: table tests over payload fixtures × today —
  every settled rule, every due rule, the revival case.
* `TMDB.Store` against the existing TMDB stub: first contact stores;
  `check` sends the stored ETag; 304 moves `fetched_at` and re-derives;
  200 replaces and publishes; a stored title is never a request.
* `TMDB.CheckJob`: due rows only; held when unavailable; bounded.
* Projections: each rebuild is a unit test from a fixture payload;
  `ReleaseTracking` releases rebuilt only on change (ids stable across a
  304).
* LiveView tests for the preview, plan board and Manage control assert
  zero requests to the stub when the title is stored.
* Pipeline: import of a new episode for a stored series makes exactly
  one season check and no series request.
* The Credo check has a fixture that fails on a stray `Client.get_movie`.
* No network in tests; no real titles in fixtures.

## 7. Decisions for the owner

Made in this design and open to veto before the plan is written:

1. **The name.** `MediaCentaur.TMDB.Store`, tables `tmdb_titles` /
   `tmdb_seasons`, glossary term *TMDB store*. It is, honestly, a
   durable identity-keyed cache with a policy; "store" is the codebase's
   word for durable stores (`TimeSeries.Store`) and avoids colliding with
   the response cache.
2. **What is scheduled** (§2.4): owned, listed, tracked, planned. Not
   activity-only titles, not one-off opens.
3. **The refresher becomes an Oban cron job** rather than a GenServer
   with timers — uniqueness, holds and visibility come free, and
   due-ness is stored, so a restart loses nothing.
4. **The intent embed goes** (row G). The watchlist joins the store.
5. **Library fields are re-projected on change** (row Q), which is what
   makes *Refresh episode lists* unnecessary. Which fields TMDB may
   overwrite on an owned entity is decided in the Phase 4 plan.
6. **The payload is stored as received** minus the `images` block. Size
   is measured in Phase 1 on the owner's instance before Phase 2 widens
   the population.

## Out of scope

Collections (row X); the response cache's persistence and stale-if-error
(row Z); TMDB's `/changes` endpoints — a per-title `/movie/{id}/changes`
costs the same request as a revalidation and answers less, and the
global change lists are thousands of ids a day; the image CDN, which
never carried a policy problem.
