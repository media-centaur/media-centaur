# TMDB Integration

The TMDB subsystem provides rate-limited access to [The Movie Database API v3](https://developer.themoviedb.org/docs) for searching titles, fetching metadata, and resolving artwork URLs.

> [Getting Started](getting-started.md) · [Configuration](configuration.md) · [Architecture](architecture.md) · [Watcher](watcher.md) · [Pipeline](pipeline.md) · **TMDB** · [Playback](playback.md) · [Library](library.md)

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
    Client[TMDB.Client] --> RL[RateLimiter]
    RL -->|"wait() then GET"| API[TMDB API v3]
    Client --> Mapper[Mapper]
    Search --> Confidence[Confidence]
```

## Key Concepts

**Rate limiting:** A sliding-window GenServer allows 30 requests per second. Callers block (sleep) until a slot opens — no mailbox buildup.

**Confidence scoring:** Search results are scored against parsed filenames using Jaro string distance plus contextual bonuses. Scores above the threshold (default 0.85) are auto-approved; below it, the file is queued for human review.

**Response mapping:** Raw TMDB JSON is mapped to schema.org attribute names (`title` → `name`, `overview` → `description`, `release_date` → `date_published`, etc.) before reaching the library domain.

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `tmdb.api_key` | `""` | TMDB API key ([get one here](https://www.themoviedb.org/settings/api)) |
| `pipeline.auto_approve_threshold` | `0.85` | Minimum confidence score for auto-approval |

See [configuration.md](configuration.md) for the full config reference.

## How It Works

### Client

HTTP client using `Req` with base URL `https://api.themoviedb.org/3`. Endpoints:

| Function | Endpoint | Purpose |
|----------|----------|---------|
| `search_movie/3` | `GET /search/movie` | Search movies by title + optional year |
| `search_tv/3` | `GET /search/tv` | Search TV series by title + optional year |
| `get_movie/2` | `GET /movie/{id}` | Movie details with credits, release dates, images |
| `get_tv/2` | `GET /tv/{id}` | TV series details with images |
| `get_season/3` | `GET /tv/{id}/season/{n}` | Season details with episode list |
| `get_collection/2` | `GET /collection/{id}` | Movie collection details with images |

Every request calls `RateLimiter.wait()` first and emits telemetry for wait duration and request latency.

### Confidence Scoring

```
score = min(base + year_bonus + position_bonus, 1.0)
```

| Component | Value | Condition |
|-----------|-------|-----------|
| Base | 0.0–1.0 | `String.jaro_distance/2` of normalized titles |
| Year bonus | +0.08 | Parsed year matches TMDB year |
| Position bonus | +0.05 | Result is first in search results |

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
| `MediaCentarr.TMDB.Client` | HTTP client, endpoint methods | `lib/media_centarr/tmdb/client.ex` |
| `MediaCentarr.TMDB.Confidence` | Jaro distance scoring | `lib/media_centarr/tmdb/confidence.ex` |
| `MediaCentarr.TMDB.Mapper` | JSON → domain attribute mapping | `lib/media_centarr/tmdb/mapper.ex` |
| `MediaCentarr.TMDB.RateLimiter` | Sliding window rate limiter | `lib/media_centarr/tmdb/rate_limiter.ex` |
