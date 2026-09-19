# TMDB-derived persistent state inventory (2026-09-19)

Research input to [`campaigns/tmdb-fetch-policy.md`](../../../../campaigns/tmdb-fetch-policy.md).
A point-in-time read of the code on 2026-09-19; file:line references
drift.

## 1. Library entity schemas

**No entity in `lib/media_centaur/library/**` has a metadata-fetch timestamp.** Exhaustive grep for `fetched_at|refreshed_at|synced_at|last_fetched|metadata_updated|scraped_at|tmdb_updated|metadata_fetched` across `lib/` and `priv/repo/migrations/` returns zero hits on any library table. The only `timestamps()` are `inserted_at`/`updated_at`, which change on any write (file relink, image upsert), not only on a TMDB fetch. **Staleness of library metadata is unknowable from the data.**

### `Library.Movie` — table `library_movies` (`lib/media_centaur/library/movie.ex:40-107`)
TMDB-derived: `name`, `description`, `date_published`, `duration_seconds` (from `runtime` min), `director`, `content_rating` (US cert), `url`, `aggregate_rating_value` (`vote_average`), `vote_count`, `tagline`, `original_language`, `studio` (first production company), `country_code` (first production country), `genres`, `status` enum, `embeds_many :cast` / `:crew` (`Person`).
Not columns: tmdb_id / imdb_id → `ExternalId` rows (`movie.ex:13-18`).
Writer: `TMDB.Mapper.movie_attrs/3` (`lib/media_centaur/tmdb/mapper.ex:23-46`) → `Pipeline.Stages.FetchMetadata` (`fetch_metadata.ex:80,101`) → `Library.Inbound.ingest/1` (`inbound.ex:84`).
Refresh: manual only — `Maintenance.refresh_movie_credits/0` (`maintenance.ex:218-225`), and only for rows with **empty** cast *or* crew (`maintenance.ex:206-208`). No other field is ever refreshed after import.

### `Library.TVSeries` — `library_tv_series` (`tv_series.ex:23-40`)
Same surface plus `network`, `number_of_seasons`. Writer: `Mapper.tv_attrs/2` (`mapper.ex:56`). Credits refresh: `Maintenance.refresh_series_credits/0` (`maintenance.ex:245-255`), gated on `series_credits_refreshed?/1` (`maintenance.ex:259-261`) which also refetches when `total_episode_count` is nil throughout.

### `Library.Season` — `library_seasons` (`season.ex:20-35`)
TMDB-derived: `season_number`, `name`, `embeds_many :episode_list` (`EpisodeListEntry`: `episode_number`, `name`, `air_date` — `episode_list_entry.ex:26-30`). Episode *count* is `length(episode_list)`; the `number_of_episodes` column was dropped (`season.ex:10-13`).
Writer: `FetchMetadata` via `Client.get_season` (`fetch_metadata.ex:215`).
Refresh: `Maintenance.refresh_episode_lists/0` (`maintenance.ex:306-327`), **manual**, and skips `season_complete?` seasons (`maintenance.ex:333`).

### `Library.Episode` — `library_episodes` (`episode.ex:29-48`)
TMDB-derived: `episode_number`, `name`, `description`, `duration_seconds`, `date_published` (TMDB `air_date`), `cast_person_ids` (TMDB person ids, season regulars + guest stars).
Writer: `Mapper.episode_attrs/4` (`mapper.ex:102`). Refresh: `cast_person_ids` only, via `backfill_episode_cast_membership/2` (`maintenance.ex:271-278`), manual.

### `Library.MovieSeries` (collection) — `library_movie_series` (`movie_series.ex:26-49`)
Same field surface as TVSeries minus network/seasons; `status` enum `[:released, :ongoing, :ended]`. Moduledoc notes most fields "come back nil at ingest" (`movie_series.ex:9-12`). Writer: `Mapper.movie_series_attrs/2` (`mapper.ex:168`). **No refresh path at all** — no maintenance task covers MovieSeries metadata.

### `Library.Person` embed (`person.ex:37-47`)
`name`, `character`, `order`, `job`, `department`, `profile_path` (TMDB image path), `tmdb_person_id`, `total_episode_count` (from `aggregate_credits`).

### `Library.ExternalId` — `library_external_ids` (`external_id.ex:23-29`)
`source` ∈ `tmdb | imdb | tvdb | tmdb_collection` (`external_ids.ex:54`), `external_id` string, `(owner_type, owner_id)`. Unique on `(source, external_id, owner_type)`. Stable identity, never stale.

### `Library.Image` — `library_images` (`image.ex:22-29`)
`role`, `content_url` (cache-relative filename), `extension`, `(owner_type, owner_id)`. Unique on `(owner_type, owner_id, role)`. **Stores no TMDB source path** — the TMDB `poster_path`/`backdrop_path` is consumed by the queue and discarded. Re-deriving a URL therefore requires a live fetch (`image_refresh.ex:93-96`, `image_repair.ex:207-228`).

### `Pipeline.ImageQueueEntry` — `pipeline_image_queue` (`image_queue_entry.ex:16-26`)
`source_url` (full TMDB CDN URL), `role`, `owner_id/type`, `status`, `retry_count`. Transient per-download record; the only place a TMDB CDN path is persisted for library entities, and only until the download completes.

### `Review.PendingFile` — `review_pending_files` (`review/pending_file.ex:16-43`)
TMDB-derived snapshot of a search result: `tmdb_id`, `tmdb_type`, `confidence`, `match_title`, `match_year`, `match_poster_path`, and `candidates` (array of maps with `title`, `year`, `score`, `poster_path`, `overview` — built at `pipeline/discovery.ex:200-210`). No timestamp beyond row `timestamps()`. Written by `Pipeline.Stages.Search` → Review; read by the review modal without re-fetching.

---

## 2. `TMDB.Title` / `TitleIdentity` / `TitleRef`

### `MediaCentaur.TMDB.Title` (`tmdb/title.ex`)
**Both.** It is an `embedded_schema` (`title.ex:41-50`) — an in-memory struct *and* a persisted snapshot wherever a row does `embeds_one :title`. Its own moduledoc calls it "a *render snapshot* cached at build time so any surface can paint the title without a TMDB call" (`title.ex:12-15`).

Fields: `tmdb_id`, `media_type`, `name`, `year`, `release_date`, `poster_path`, `backdrop_path`, `overview` (`title.ex:42-49`). `poster_path`/`backdrop_path` are TMDB paths, not URLs.

Persisted in exactly two tables:
- `title_intents.title` — `discovery/title_intent.ex:83`
- `activities.title` — `activities/activity.ex:85`

Keyed by `(tmdb_id, media_type)` — `Title.ref/1` (`title.ex:120`), spelled in URLs by `MediaCentaurWeb.TitleRef` (`title_ref.ex:15-24`).
**Staleness marker: none.** Neither table carries a snapshot-fetch timestamp; only row `inserted_at`/`updated_at`.
Writers: `Title.from_tmdb/2` (`title.ex:75-78`) from search hits or detail payloads; `Title.new!/1` (`title.ex:111`) for in-app builders.
Readers that use it instead of a live call: `title_detail_host.ex:266-267` (intent snapshot), `:275` (activity snapshot), `:281` (`Activities.get_row/1`); `live_helpers.ex:192-194` (`title_poster_url/1`).

### `MediaCentaur.TMDB.TitleIdentity` (`tmdb/title_identity.ex`)
Plain `defstruct`, **never persisted as a struct** (`title_identity.ex:49-58`). Fields `tmdb_type`, `tmdb_id`, `title`, `imdb_id`, `tvdb_id`, `original_title`, `year`, `origin_country`. It is *projected into columns* on `release_tracking_items` (see §3) and reconstructed from them by `Pursuit.identity/1` (`acquisition/pursuits/pursuit.ex:114-116`) and `ReleaseTracking.Identity` (`release_tracking/identity.ex`). Built from live payloads by `from_payload/2` (`title_identity.ex:107`).

### `MediaCentaurWeb.TitleRef` — pure URL codec, stores nothing (`title_ref.ex`).

---

## 3. `ReleaseTracking`

### `ReleaseTracking.Item` — `release_tracking_items` (`release_tracking/item.ex:37-70`)
TMDB-derived: `tmdb_id`, `media_type`, `name`, `origin_country`, `imdb_id`, `tvdb_id`, `original_title`, `year`, `season_sizes` (`%{"1" => 22}`, specials excluded — `item.ex:56-65`).
**Staleness marker: `last_refreshed_at` (`item.ex:43`)** — the only genuine TMDB-fetch timestamp in the whole app. Migration `priv/repo/migrations/20260404104919_create_release_tracking.exs:13`; `season_sizes` added `20260917190000_add_release_tracking_item_season_sizes.exs:19`.
Non-TMDB: `last_library_season`/`last_library_episode` (library-derived), `dismiss_released_before`, `library_container_type/id`.

Writers:
- `Onboarding.do_onboard/3` sets `last_refreshed_at: DateTime.utc_now()` on create (`release_tracking/onboarding.ex:68`, `:92`).
- `Refresher.update_item_metadata/3` (`refresher.ex:311-330`) — rewrites `name`, `last_refreshed_at`, `season_sizes` unconditionally; `origin_country`/`imdb_id`/`tvdb_id`/`original_title`/`year` are `declared.x || item.x` self-heals.

Readers that could substitute for a live call: `Acquisition.Plans` / drop planner consume `season_sizes` as the fit denominator (`item.ex:61-64`); `ReleaseTracking.Identity` builds a `TitleIdentity` from the stored ids without touching TMDB.

Refresh trigger: `Refresher` GenServer timer every `release_tracking_refresh_interval_hours` (default 6 — `settings/config.ex:452`), `refresher.ex:96-104`. Held while TMDB is down (`refresher.ex:249`), resumed on the `:up` broadcast (`refresher.ex:107-112`). Loop drift corrected by `RefreshSchedule.next_delay_ms/4` reading `max(last_refreshed_at)` (`refresher.ex:379-384`).

### `ReleaseTracking.Release` — `release_tracking_releases` (`release_tracking/release.ex:17-30`)
TMDB-derived: `air_date`, `title`, `season_number`, `episode_number`, `release_type`, `part_tmdb_id`. `released` is **derived on read**, not stored (`release.ex:7-9`, `released?/2` at `release.ex:63-65`). `in_library`/`in_library_at` are library-derived.
Staleness marker: none on the row; the parent item's `last_refreshed_at` covers the whole set.

**`replace_releases!/3` invariant** (`release_tracking.ex:449-457`): inside one transaction, `delete_releases_for_item(item.id)` then `Enum.each(releases, persister)`. The calendar is **wholesale-replaced, never diffed**. Consequences: row ids and `inserted_at` change every refresh; anything keyed on a Release id is invalidated every 6 hours. Callers: `onboarding.ex:126`, `:133`; `refresher.ex:304`.

**What the Refresher compares against to detect change: nothing.** `commit_refresh/3` (`refresher.ex:296-300`) unconditionally replaces releases and rewrites item metadata regardless of whether the payload differs from what is stored. Change detection is delegated downstream: `mark_in_library_releases` + `sync_wants` (`refresher.ex:303-308`), and the `Want` ledger (below) is what actually survives a replace. Every fetch uses `reload: true` (`refresher.ex:257`, `:279`, `:289`) — deliberately bypassing the HTTP cache because "TMDB marks details fresh for about eight hours, longer than the refresh interval" (`refresher.ex:249-252`).

### `ReleaseTracking.Want` — `release_tracking_wants` (`release_tracking/want.ex:41-58`)
TMDB-derived: `title`, `air_date`, `season_number`, `episode_number`, `part_tmdb_id`. Explicitly the durable counterpart to the wholesale-replaced Release projection (`want.ex:5-9`). Staleness: none for TMDB facts; `last_searched_at` is a search clock, not a metadata clock.

### `MediaCentaur.TMDB.ReleaseWindow` (`tmdb/release_window.ex`)
**Pure, never persisted** — "Pure — the LiveView fetches the payload and assigns the built struct" (`release_window.ex:30`). Built by `from_payload/2` (`release_window.ex:59`) from a live `Client.get_movie` payload at `title_detail_host.ex:572-573`. `stage`/`theatrical`/`digital`/`physical`/`primary` exist only in socket assigns.

### `Acquisition.Cours` (`acquisition/cours.ex`)
Full-season air dates fetched live per call; "Recomputed on demand — nothing persisted" (`cours.ex:15`). Hits `Client.get_season` at `cours.ex:29`.

---

## 4. `Discovery.TitleIntent`

Table `title_intents` (`discovery/title_intent.ex:82-92`).
TMDB-derived: `tmdb_id`, `media_type` (indexed columns, derived from the embed on write — `title_intent.ex:61-63`), and the full `embeds_one :title, Title` snapshot: name, year, release_date, poster_path, backdrop_path, overview.
Non-TMDB: `rung`, `source`, `note` (friend's review text), `activity_id`.
**Staleness marker: none.**
Writers: `create_changeset/3` `put_embed(:title, title)` (`title_intent.ex:108`); `rung_changeset/3` refreshes the embed only when a `Title` is passed (`title_intent.ex:117-124`, `maybe_refresh_title/2` at `:126-127`) — so a rung move with `nil` leaves an arbitrarily old snapshot in place.
Readers substituting for a live call: `title_detail_host.ex:266-267` opens the modal from the stored snapshot; `intent_note/1` at `:522-527`.
Artwork warm on write: `Discovery.ensure_artwork_async/1` (`discovery.ex:189-195`), skipped for `:ignored`.

Observed on the owner's instance: one watchlist snapshot carried
`release_date: nil`, `poster_path: nil`, `overview: nil` — a snapshot
built from a sparse source and never refreshed since.

---

## 5. `TmdbArtwork` and `Library.ImageCache`

### `MediaCentaur.TmdbArtwork` — on-disk, no DB rows (`tmdb_artwork.ex`)
Layout: `{data_dir}/images/tmdb/{media_type}-{tmdb_id}/{role}.jpg`, roles `poster | backdrop | logo` (`tmdb_artwork.ex:96-99`, `@subdir` at `:61`). Keyed by `(media_type, tmdb_id)` because TMDB movie/TV id spaces overlap (`tmdb_artwork.ex:13-18`). Always TMDB `original` size (`tmdb_artwork.ex:64-66`).
**TTL: 7 days** (`@ttl_days` at `tmdb_artwork.ex:62`), clock = **directory mtime**, bumped by `touch/2` on every `ensure/2` and every download (`tmdb_artwork.ex:207-212`). Swept daily only when *both* aged out and unreferenced by a `HoldProvider` (`sweep/0` at `tmdb_artwork.ex:257-274`).
Second, separate staleness notion: `stale_image?/1` — file missing or `< 50_000` bytes, i.e. a legacy `w300`/`w185` thumbnail (`tmdb_artwork.ex:71-73`, `:222-227`). Acted on by `refresh_if_stale/4` (`tmdb_artwork.ex:238-249`), called only from the `mix media_centaur.refresh_tracking_images` task (`lib/mix/tasks/media_centaur.refresh_tracking_images.ex:64-82`).
Re-fetch triggers: `ensure/2` (`tmdb_artwork.ex:169-186`) fires one detail fetch **only when a role file is missing**, and is a no-op while TMDB is unavailable. Call sites: `discovery.ex:192` (title listed), `activities.ex:539` (activity ingested, not render — `ensure_artwork_async/1` at `activities.ex:535-543`), `discovery_live.ex:376`, `incoming_live.ex:2416`, `:2794`. Read-only `urls/2` (disk-existence only, no network — `tmdb_artwork.ex:134-148`) is what render paths use: `title_detail_host.ex:465`, `release_tracking.ex:679`, `:727`, `pursuits.ex:780`, `incoming_live.ex:2612`, `:2789`.
Tracked-item downloads: `Helpers.download_images_sync/3` skips any role whose file already exists — "disk is the download ledger" (`release_tracking/helpers.ex:46-60`).

### `MediaCentaur.Library.ImageCache` — `{media_dir}/.media-centaur/images/{owner_id}/{role}.{ext}` (`library/image_cache.ex:17-26`)
Permanent tier, one file per `Library.Image` row, **no TTL and no expiry sweep**. Re-fetch is only by explicit user action: `Pipeline.ImageRefresh.enqueue_refresh/2` (Oban, `image_refresh.ex:37-47`) from the detail → manage view (`title_detail_host/library_events.ex:133`), or `Maintenance.refresh_image_cache/0` / `repair_missing_images` from Settings (`settings_live.ex:732-758`). Both re-fetch the whole TMDB detail payload because the source path was never stored (`image_refresh.ex:93-96`).

---

## 6. Activities / Social

### `Activities.Activity` — `activities` (`activities/activity.ex:81-99`)
Carries `embeds_one :title, Title` (`activity.ex:85`) — the full render snapshot — plus `tmdb_id`, `media_type` as columns, and `embeds_one :episode, Episode` (`season_number`, `episode_number`, `name` — `activity.ex:66-70`), where `name` is a TMDB episode name.
Provenance: the snapshot arrives inside the **signed Nostr event**, not from a local TMDB call — `Translation` decodes `{"v": 1, "title": <TMDB.Title fields>, …}` (`activities/translation.ex:6`). Identity is `(author_pubkey, kind, tmdb_id, media_type)`; a newer event **replaces the row wholesale, embed included** — "the snapshot in the newer event is the whole truth, never a field-wise merge" (`activity.ex:8-13`).
**Staleness marker: none** for TMDB facts. `acted_at`/`deleted_at` are domain times.
**Does not re-fetch on render.** The only network touch is `ensure_artwork_async/1` on ingest (`activities.ex:535-543`), and even that only downloads roles whose files are missing.
Readers substituting for a live call: `title_detail_host.ex:275` (`activity_snapshot/1`), `:281` (`Activities.get_row/1`), `:493` (`Activities.friend_activity_for/1`).

---

## 7. Settings entries for TMDB cadence

`lib/media_centaur/settings/config.ex`:
- `:tmdb_api_key` (`:56`, `:68` — secret-wrapped, `:440`)
- `:release_tracking_refresh_interval_hours` (`:85`), default **6** (`:452`) — read at `refresher.ex:361`
- `:release_tracking_sweep_interval_minutes` (`:86`), default **15** (`:453`) — read at `refresher.ex:366`; this is the want-ledger sweep, no TMDB requests

There is **no setting for library metadata refresh cadence**, no TMDB-cache TTL setting, and no artwork TTL setting (`@ttl_days` is a module attribute at `tmdb_artwork.ex:62`). Transient scheduling state `"release_tracking:last_swept_at"` lives in the Settings table (`refresher.ex:34`, `:386-390`).

---

## 8. Pipeline import path and `Reconciliation.Spine`

### What is written to the library at import
`Pipeline.Import.process_payload/1` (`pipeline/import.ex:82-95`): `Parser.parse` → `check_disk_space` → `Stages.FetchMetadata` → `Stages.Ingest`. There is **no check against existing library state inside Import** — `FetchMetadata` runs unconditionally on every payload that reaches the pipeline.

`FetchMetadata` (`stages/fetch_metadata.ex`) issues: `Client.get_movie` (`:80`), `Client.get_tv` (`:96`), `Client.get_collection` (`:125`), `Client.get_season` (`:215`). It emits `entity_attrs`, `images` (`%{role, url, extension}`), `identifier`, `season.episode_list`, `child_movie`, `extra` (`fetch_metadata.ex:11-26`). `Stages.Ingest` broadcasts `{:entity_published, …}`; `Library.Inbound.ingest/1` (`inbound.ex:84-107`) creates or links via `Writes.find_or_insert_by/3` (`library/writes.ex:44`) — note `find_or_insert_by` **does not write through on a hit** (contrast `upsert_by/3` at `writes.ex:76-80`), so re-import of an existing entity leaves its stored metadata untouched even though TMDB was just fetched.

### Re-scan / re-import of an existing entity
The short-circuit is **upstream in Discovery, not Import**: `Pipeline.Discovery.settled_reason/1` (`pipeline/discovery.ex:231-236`) skips any file where `Library.Files.linked?(file_path)` or `Review.dismissed?(file_path)`, logged as `"already linked"` / `"dismissed in review"` (`discovery.ex:132`, `:137`). The comment at `discovery.ex:227-229` states this is exactly what avoids "a parse and two TMDB searches on every scan and restart".

Net: a **rescan of an already-linked file costs zero TMDB requests**. A *new* file for an existing series/collection (a new episode) does go through Import and **re-fetches the series detail and the season detail** even though the library already holds both — and then discards the result for the parent because `find_or_insert_by` hits.

### `Reconciliation.Spine` (`reconciliation/spine.ex`)
**Always live, nothing stored.** `assemble/2` (`spine.ex:22-36`) issues one `get_tv` plus one `get_season` per season (`spine.ex:39`). Its moduledoc is explicit that the spine "is always TMDB's ordered episodes (never the library's possibly-incomplete season rows)" (`spine.ex:4-6`) — a deliberate refusal to read `Season.episode_list`, which holds the same data (§1). Degrades to `[]` on error.

---

## 9. Showcase / seed

`lib/media_centaur/showcase.ex` **hits the real TMDB API**. Live calls: `search_movie` (`:572`), `search_tv` (`:587`), `get_movie` (`:168`), `get_tv` (`:223`), `get_season` (`:279`). Moduledoc: "seeded with real TMDB metadata and downloaded poster+backdrop images" (`showcase.ex:68`). Hard-fails without a key (`showcase.ex:201-203`, `:271-273`). The stub is test-only, at the `Client` layer via persistent_term (`showcase.ex:75-76`).

---

## TMDB facts stored NOWHERE (always live)

| Fact | Only source | Site |
|---|---|---|
| Typed US release dates (theatrical / digital / physical) and release *stage* | `ReleaseWindow.from_payload/2` | `release_window.ex:59`; assigned at `title_detail_host.ex:572` |
| Cour / broadcast-run segmentation of a season | `Acquisition.Cours.runs_for_season/2` | `cours.ex:29` ("nothing persisted", `:15`) |
| Full canonical episode spine for reconciliation | `Reconciliation.Spine.assemble/2` | `spine.ex:23,39` |
| TMDB image **source paths** for library entities (`poster_path`/`backdrop_path`/`still_path`/`logo_path`) | discarded after the queue row completes | `image_queue_entry.ex:21`; forces refetch at `image_refresh.ex:93-96`, `image_repair.ex:207-228` |
| `next_episode_to_air`, `number_of_episodes` per season as TMDB reports it, `belongs_to_collection`, `vote_average` for collections, keywords, videos, watch providers, similar/recommended | never mapped | `mapper.ex` maps no such fields |
| Full `search` result sets | `TMDB.TitleSearch` | `title_search.ex:41,50-51` — only a review's `candidates` array persists a trimmed copy |
| Anything for a title that is neither in the library, on a title-intent, tracked, nor in an activity | — | `title_detail_host.ex:553-561` must fetch to open it |

## TMDB facts stored in MORE THAN ONE place

| Fact | Copies | Inconsistency risk |
|---|---|---|
| **Title name** | `library_movies.name` / `library_tv_series.name` / `library_movie_series.name`; `release_tracking_items.name`; `title_intents.title.name`; `activities.title.name`; `release_tracking_wants.title`; `review_pending_files.match_title` | 7 copies, 1 refreshed (`refresher.ex:315`), 1 wholesale-replaced from the wire (`activity.ex:8-13`), 5 never refreshed |
| **Release / air date** | `library_movies.date_published`, `library_episodes.date_published`, `seasons.episode_list[].air_date`, `release_tracking_releases.air_date`, `release_tracking_wants.air_date`, `title_intents.title.release_date`, `activities.title.release_date` | Releases are replaced every 6h; the library copies are frozen at import. A date TMDB revises diverges between the calendar and the detail page |
| **Season / episode counts** | `seasons.episode_list` (length), `library_tv_series.number_of_seasons`, `release_tracking_items.season_sizes` | `season_sizes` rewritten every refresh (`refresher.ex:319`); `episode_list` only on manual maintenance and only for incomplete seasons (`maintenance.ex:333`); `number_of_seasons` never |
| **imdb_id / tvdb_id** | `library_external_ids` rows; `release_tracking_items.imdb_id` / `.tvdb_id` (`item.ex:48-49`) | Two id stores with different write paths and different refresh policies |
| **tmdb_id** | `library_external_ids.external_id`; `release_tracking_items.tmdb_id`; `title_intents.tmdb_id`; `activities.tmdb_id`; `review_pending_files.tmdb_id`; `release_tracking_releases.part_tmdb_id`; `release_tracking_wants.part_tmdb_id` | Immutable, so low risk — but it means "does the app already know this title" requires querying 5 tables |
| **Poster / backdrop bytes** | `{media_dir}/.media-centaur/images/` (library tier, permanent, no TTL) *and* `{data_dir}/images/tmdb/{type}-{id}/` (referenced tier, 7-day TTL) | Same title can hold two copies at different resolutions/vintages under different keys (entity uuid vs `(media_type, tmdb_id)`); `live_helpers.ex:192-194` falls back between them |
| **Overview / description** | `library_*.description`; `title_intents.title.overview`; `activities.title.overview`; `review_pending_files.candidates[].overview` | 4 copies, none refreshed |
| **Year** | `library_*.date_published` (derived), `release_tracking_items.year`, `title_intents.title.year`, `activities.title.year`, `review_pending_files.match_year` | `item.year` self-heals on refresh; the rest never |
