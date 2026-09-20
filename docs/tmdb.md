# TMDB Integration

The TMDB subsystem provides rate-limited access to [The Movie Database API v3](https://developer.themoviedb.org/docs) for searching titles, fetching metadata, and resolving artwork URLs.

> [Architecture](architecture.md) · [Watcher](watcher.md) · [Pipeline](pipeline.md) · **TMDB** · [Playback](playback.md) · [Library](library.md) · [Input System](input-system.md)

- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Module Reference](#module-reference)

## Architecture

```mermaid
graph LR
    Search[Search Stage] --> Client
    Fetch[FetchMetadata Stage] --> Client
    Client[TMDB.Client] --> Seam[HttpClient.new]
    Seam --> Cache[HttpClient.Cache]
    Cache -->|"stale or missing"| RL[RateLimiter step]
    RL -->|GET| API[TMDB API v3]
    Client --> Mapper[Mapper]
    Search --> Confidence[Confidence]
```

## Key Concepts

**Rate limiting:** A sliding-window GenServer allows 30 requests per second. Callers block (sleep) until a slot opens — no mailbox buildup.

**Confidence scoring:** Search results are scored against parsed filenames using Jaro string distance plus contextual bonuses. Scores above the threshold (default 0.85) are auto-approved; below it, the file is queued for human review.

**Response mapping:** Raw TMDB JSON is mapped to the library schemas' field names (`title` → `name`, `overview` → `description`, `release_date` → `date_published`, etc.) before reaching the library domain.

## Configuration

Both values are **DB-managed** as of v0.14.0 / v0.15.0. They are edited in **Settings → TMDB** and persisted via `MediaCentaur.Settings.Entry`; the TOML file no longer carries them. `MediaCentaur.Config.get/1` reads the DB under the hood.

| Key (via `Config.get/1`) | Default | Description |
|--------------------------|---------|-------------|
| `:tmdb_api_key` | `nil` | TMDB API key ([get one here](https://www.themoviedb.org/settings/api)) |
| `:auto_approve_threshold` | `0.85` | Minimum confidence score for auto-approval |

See [configuration.md](configuration.md) for the full DB-managed config reference.

## Capability gating

UI surfaces that depend on TMDB — **Rematch** in the detail view, **Search TMDB** in Review, and **Track New Releases** under Release Tracking — only appear once `MediaCentaur.Capabilities.tmdb_ready?/0` returns `true`. That predicate is true when:

1. An API key is configured.
2. The most recently persisted **Test connection** result was `:ok`.

Saving any field in the TMDB section clears the stored test result, so the UI collapses back to the "please test" state until the user re-verifies. The test-connection button and its result storage live under `MediaCentaur.Capabilities.save_test_result/2` + `load_test_result/1`, with a broadcast on `capabilities:updates` so subscribed LiveViews refresh in place.

When adding a new TMDB-dependent feature, render its affordance behind `Capabilities.tmdb_ready?/0` rather than directly checking key presence — that's the only way to pick up the "configured but untested" state correctly.

TMDB is consumed by four paths: the Pipeline (Discovery + Import + Image downloads), `TMDB.CheckJob` (the scheduled checks of stored titles), `ReleaseTracking.Onboarding` (first contact when a title is followed), and `Review.Rematch`. Capability readiness applies to all of them.

## How It Works

### Client

HTTP client using `Req` with base URL `https://api.themoviedb.org/3`. Endpoints:

| Function | Endpoint | Purpose |
|----------|----------|---------|
| `search_movie/3` | `GET /search/movie` | Search movies by title + optional year |
| `search_tv/3` | `GET /search/tv` | Search TV series by title + optional year |
| `get_movie/2` | `GET /movie/{id}` | Movie details with credits, release dates, images |
| `get_tv/2` | `GET /tv/{id}` | TV series details with images |
| `get_season/3` | `GET /tv/{id}/season/{n}` | Season details with episode list + appended `credits` (per-episode cast membership) |
| `get_collection/2` | `GET /collection/{id}` | Movie collection details with images |

Every public function takes a trailing keyword list: `client:` substitutes a `Req` client, `reload: true` fetches past a fresh cache entry. The client comes from `MediaCentaur.HttpClient.new/2` ([ADR-064](../decisions/architecture/2026-09-04-064-outbound-http-seam.md)), which attaches the response cache (`api_key` excluded from the key) and the instrumentation; `RateLimiter.attach/1` adds the rate-limit step after the cache step, so a hit never spends a slot. TMDB states freshness on every response (`Cache-Control: max-age`, about one hour for search and eight for details) and the cache honours it, revalidating stale entries with `If-None-Match`. Only the `/configuration` credential probe passes `reload: true`. `detail/2` is the third path: with `if_none_match:` the request carries the store's own ETag, the response cache stands aside (`:conditional`), and a 304 comes back as `{:ok, :unchanged}`.

### The store

`MediaCentaur.TMDB.Store` holds one record per TMDB title the app knows — the detail payload as TMDB returned it (the `images` block reduced to the selected logo), its ETag, when it was fetched and last changed, and the schedule `MediaCentaur.TMDB.Schedule` derives on every write: the next known event, the next check due, and when the title settled ([ADR-071](../decisions/architecture/2026-09-20-071-tmdb-store-one-record-per-title.md)). Seasons are stored alongside. `Store.ensure/2` is first contact (a request only when the title has never been held), `Store.check/2` revalidates a stored title and its open seasons with their ETags and publishes `{:tmdb_title_changed, ref}` on `Topics.tmdb_titles/0` when a payload changed.

Who is asked and when: `MediaCentaur.TMDB.References` collects every context's references to a title (tracked, listed, pursued, in a friend's activity) and which of those schedule checks — tracked titles as of Phase 2 of `tmdb-fetch-policy`, the rest as their readers move onto the store. `MediaCentaur.TMDB.CheckJob` (Oban cron, `@reboot` and every quarter hour) first-contacts referenced titles the store lacks and checks the due ones; it holds while TMDB is unavailable. Release tracking rebuilds a tracked title's calendar from the store when `{:tmdb_title_changed, ref}` arrives (`ReleaseTracking.TmdbListener` → `title_changed/1`), and a tracked item carries no TMDB fact of its own — its name and season sizes are attached from the store on load. *Refresh from TMDB* on a title's Manage view or tracking card runs one check on demand (UIDR-044). The store still fills through a transitional write-through from `get_movie/2`, `get_tv/2` and `get_season/3` for the callers Phases 3 and 4 move onto it. A payload that is not the title's own answer (no matching `id`) is refused rather than stored.

### Confidence Scoring

```
quality = clamp(base + year_adjustment, 0.0, 1.0)
score   = quality + position_bonus
```

| Component | Value | Condition |
|-----------|-------|-----------|
| Base | 0.0–1.0 | `String.jaro_distance/2` of normalized titles |
| Year adjustment | +0.08 / −0.15 / 0 | Parsed year matches / contradicts / is unknown on either side |
| Position bonus | +0.05 | Result is first in search results (applied after the clamp, so a top result can score just above 1.0) |

**Normalization:** Lowercase, strip non-alphanumeric characters (except spaces), collapse whitespace.

Top 5 results are scored. The highest-scoring result is selected.

### Mapper

Maps TMDB JSON fields to domain attributes:

| TMDB Field | Domain Attribute |
|------------|------------------|
| `title` / `name` | `name` |
| `overview` | `description` |
| `release_date` / `first_air_date` | `date_published` |
| `genres[].name` | `genres` |
| `runtime` | `duration` (ISO 8601) |
| `vote_average` | `aggregate_rating_value` |
| `credits.crew[job=Director]` | `director` |
| `release_dates` (US cert) | `content_rating` |

Image extraction prefers English logos (`iso_639_1 == "en"`). Roles: `poster`, `backdrop`, `logo`.

Image CDN URL: `https://image.tmdb.org/t/p/original{path}`

### Rate Limiter

Sliding window using Erlang `:queue`:

1. On `wait()` call, GenServer checks if queue length < 30 (rate limit)
2. If under limit: record timestamp, return immediately
3. If at limit: calculate sleep duration from oldest timestamp, return `{:retry_after, ms}`
4. Caller sleeps and retries — GenServer never blocks

## Module Reference

| Module | Description | Path |
|--------|-------------|------|
| `MediaCentaur.TMDB.Client` | HTTP client, endpoint methods; `detail/2` is the store's conditional request path | `lib/media_centaur/tmdb/client.ex` |
| `MediaCentaur.TMDB.Store` | One record per TMDB title the app knows — payload, ETag, fetch time, due time — and its seasons; the only detail writer (ADR-071) | `lib/media_centaur/tmdb/store.ex` |
| `MediaCentaur.TMDB.Store.TitleRecord` | Schema for `tmdb_titles` | `lib/media_centaur/tmdb/store/title_record.ex` |
| `MediaCentaur.TMDB.Store.SeasonRecord` | Schema for `tmdb_seasons` | `lib/media_centaur/tmdb/store/season_record.ex` |
| `MediaCentaur.TMDB.Schedule` | Pure due-time rule: settled titles, next known event, open seasons | `lib/media_centaur/tmdb/schedule.ex` |
| `MediaCentaur.TMDB.Confidence` | Jaro distance scoring | `lib/media_centaur/tmdb/confidence.ex` |
| `MediaCentaur.TMDB.Mapper` | JSON → domain attribute mapping | `lib/media_centaur/tmdb/mapper.ex` |
| `MediaCentaur.TMDB.RateLimiter` | Sliding window rate limiter + its `Req` request step | `lib/media_centaur/tmdb/rate_limiter.ex` |
| `MediaCentaur.HttpClient` | The outbound seam: upstream tagging, instrumentation, response cache | `lib/media_centaur/http_client.ex` |
