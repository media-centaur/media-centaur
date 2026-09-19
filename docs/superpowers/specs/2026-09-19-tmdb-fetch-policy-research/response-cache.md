# HTTP response cache mechanics for TMDB (2026-09-19)

Research input to [`campaigns/tmdb-fetch-policy.md`](../../../../campaigns/tmdb-fetch-policy.md).
A point-in-time read of the code on 2026-09-19; file:line references
drift.

## 1. Cache storage

- **Owner/process**: `MediaCentaur.HttpClient.Cache.Coordinator`, a GenServer that creates a `:named_table, :set, :protected, read_concurrency: true` ETS table named after itself (`lib/media_centaur/http_client/cache/coordinator.ex:107`). Writes go through the GenServer; reads are direct `:ets.lookup/2` from the calling process (`coordinator.ex:61-66`, called at `cache.ex:90`). Started only in dev/prod under `HttpClient.Supervisor` (`lib/media_centaur/http_client/supervisor.ex:34`); `http_client_children(:test) -> []` (`lib/media_centaur/application.ex:211`). When the table doesn't exist every request passes through as `:uncached` (`cache.ex:87,100-102`).
- **Entry shape** (`lib/media_centaur/http_client/cache/entry.ex:19-30`): `key`, `body` (raw wire binary, not decoded — `entry.ex:6-9`), `content_type` (default `"application/json"`, `entry.ex:53-54`), `etag` (first `etag` header, `entry.ex:38`), `fresh_until`, `max_age_ms`, `stored_at`. Times are `System.monotonic_time(:millisecond)`. **No** `Expires`, `Date`, `Age`, `Last-Modified`, `Vary`, status or other headers are stored.
- **Key** (`lib/media_centaur/http_client/cache/key.ex:15-23`): `{url.host, url.path || "/", sorted_query_pairs}` after `Map.drop(exclude_params)`. Method is **not** in the key (only GETs ever reach it, `cache.ex:84`), scheme and port are **not** in the key. TMDB passes `exclude_params: ["api_key"]` (`lib/media_centaur/tmdb/client.ex:86`), so `api_key` exclusion is confirmed; test at `test/media_centaur/http_client/cache_test.exs:85-96` asserts param order and `api_key` don't matter. The key is built from the *resolved* URL because the lookup step is appended after Req's `put_base_url`/`put_params` steps (`cache.ex:53`).
- **Size limits**: no per-entry byte cap anywhere. Count cap only: `max_entries` default `1_000` (`coordinator.ex:32`), enforced after every insert by evicting oldest-by-`stored_at` (`coordinator.ex:180-197`). Test: `cache_test.exs:369-383`.
- **Retention/sweep**: hard age cap `retention_ms` default 1 week (`coordinator.ex:33`), sweep every `sweep_interval_ms` default 1 hour (`coordinator.ex:34`, timer at `:117` and `:160-164`), dropping any entry with `stored_at <= now - retention_ms` regardless of freshness (`coordinator.ex:199-210`; test `cache_test.exs:385-395`). `Coordinator.sweep/1` forces it (`coordinator.ex:100`).
- **Persistence**: none. ETS only, dies with the process/app restart. (Contrast: the Traffic time series *is* snapshotted to `traffic.snapshot` beside the DB, `supervisor.ex:27-31,36-41`.)
- **Single-flight**: leader/follower election in the coordinator, leader monitored, followers get `{:done, response}` / `{:failed, exception}`; claim timeout 2 min (`coordinator.ex:35,75-80,122-141,149-158`).

## 2. Freshness algorithm

`lib/media_centaur/http_client/cache/freshness.ex` reads **only `Cache-Control`**:
- `no-store` → `nil` = do not store (`freshness.ex:28`).
- `no-cache` → `0` seconds = stored but immediately stale, so every use revalidates (`freshness.ex:29`).
- `max-age=N` (non-negative integer, exact parse) → `N` (`freshness.ex:34-45`).
- Anything else, **including no `Cache-Control` header at all** → `nil` = **not stored** (`freshness.ex:12,30`; test `cache_test.exs:155-164` asserts zero entries).
- `s-maxage`, `Expires`, `Age`, `Date`, `Last-Modified`, `must-revalidate`, `private`, `public` are all ignored (`freshness.ex:14-16`). `Age`/`Date` are not subtracted — `fresh_until = now + max_age` measured from *receipt* (`entry.ex:57`).

Other rules: only status 200 with a binary body is stored (`entry.ex:37,63`; test `cache_test.exs:176-186`). `max-age=0` with no ETag is dropped as pointless (`entry.ex:44-47`). There is **no default TTL, no minimum, no maximum clamp** — ADR-064 states "Freshness comes from the origin… No policy table" (`decisions/architecture/2026-09-04-064-outbound-http-seam.md:30-35`; plan `docs/plans/2026-09-04-http-client-cache-and-upstreams-panel.md:76`). Freshness check is strict `now < fresh_until` (`entry.ex:89`). **No `stale-while-revalidate` and no `stale-if-error`** exist anywhere in the module.

## 3. Revalidation

- Conditional header: **`If-None-Match` only**, from the stored ETag (`cache.ex:120,130-134`). `If-Modified-Since` is never sent (no `last_modified` is stored).
- A stale entry **with no ETag** is not revalidated; it is treated as a plain `:miss` and refetched (`cache.ex:97`).
- On **304**: `Entry.renew/3` sets `fresh_until = now + max_age_ms`, where `max_age_ms` is the 304's own `Cache-Control: max-age` if present, else the previously remembered span; `stored_at` is reset to now (`entry.ex:67-75`, called at `cache.ex:160-163`). So yes — a 304 extends freshness by the new `max-age`, and also resets the retention clock. The caller is handed a synthesized 200 carrying the stored body, not the 304 (`cache.ex:162`, `entry.ex:79-85`; test `cache_test.exs:201-239`).
- On **200 to a revalidation**: the stale entry is replaced wholesale (`cache.ex:165-167`; test `cache_test.exs:241-260`).
- **Rate limiter**: a revalidation/miss/reload *does* spend a slot — the limiter step is appended *after* the cache lookup step, and the lookup halts the pipeline on a hit (`lib/media_centaur/tmdb/rate_limiter.ex:19-28`, attached at `client.ex:88`; `cache.ex:53`). Followers that get `{:done, response}` also halt before the limiter, so they spend nothing.
- **Traffic accounting** (`lib/media_centaur/http_client/traffic.ex:163-197`): the only outcome treated as "not a request" is `cache == :hit`. `hit?` → `requests: 0, cached: 1`, no latency, and `last`/`last_success` are left untouched (`traffic.ex:170-176,193-196`; test `traffic_test.exs:67-75`). Every other outcome — `:miss`, `:revalidate`, `:reload`, `:uncached` — counts `requests: 1` plus `failed: 1` when `error != nil or status >= 400`. Note a 304 counts as a request and **not** as failed. Follower responses are graded `:hit` (`cache.ex:123`), so N coalesced callers record 1 request + (N-1) cached. Commit `4a461106` ("fix(status): a cache hit is not a request", 2026-09-04) made this change in the then-`HttpClient.Stats`; the logic now lives in `Traffic`. Revalidations and reloads are **not distinguishable in the time series** — the schema has only `requests/failed/cached/latency_sum_ms/latency_max_ms` (`traffic.ex:34-40`); per-outcome detail survives only in the 20-slot `recent` ring, which carries `cache:` per row (`traffic.ex:186`).
- One telemetry event is emitted **per attempt**, not per logical call: `Instrument` prepends its stop/error steps ahead of Req's `retry` step (`lib/media_centaur/http_client/instrument.ex:7-10,44-46`). Req's default `retry: :safe_transient` retries GET on 408/429/500/502/503/504 and on transport timeouts/econnrefused/closed (`deps/req/lib/req/steps.ex:1671-1678`), so one failing TMDB call can post several `requests`/`failed` counts. Stubs disable retry (`http_client.ex:77-85`).

## 4. Bypass (`reload: true`)

- Registered as a per-request Req option (`cache.ex:51`). In `lookup/1` it is the **first** cond branch, before the entry is even examined: `request.options[:reload] == true -> lead_or_follow(request, config, :reload, nil)` (`cache.ex:94`). The ETS lookup itself still runs (`cache.ex:90`) but its result is discarded.
- `stale_entry` is passed as `nil`, so **no `If-None-Match` is sent** even when an ETag is stored (`cache.ex:120,134`).
- It **still participates in single-flight** (concurrent identical callers can be parked as followers and get `:hit`) and it **still stores**: the leader path runs the store step and `Entry.from_response/3` overwrites the entry if the response is a cacheable 200 (`cache.ex:147-167`; test `cache_test.exs:263-285`). A reload that returns non-200 stores nothing and leaves the old entry in place.
- Outcome reported as `:reload`; counted as a request by Traffic and spends a rate-limit slot.

Call sites in `lib/` passing `reload: true` (full `grep -rn "reload:" lib/` result, excluding Ecto `preload:` noise):
- `lib/media_centaur/tmdb/client.ex:99` — `configuration/1` always forces it (credential probe; also used by `TMDB.ProbeJob`, `lib/media_centaur/tmdb/probe_job.ex:53`).
- `lib/media_centaur/release_tracking/refresher.ex:257` (`get_tv`), `:279` (`get_collection`), `:289` (`get_movie`), with rationale at `:247-249` ("TMDB marks details fresh for about eight hours, longer than the refresh interval").
- Declarations only: `lib/media_centaur/tmdb/client.ex:62` (`@type opts`), `lib/media_centaur/http_client/cache.ex:17` (moduledoc).

No other `lib/` call site passes `reload:`.

## 5. Failure behaviour

- **Network/transport error**: the leader's error step calls `Coordinator.failed/3` (`cache.ex:171-178`, `coordinator.ex:139-141`), followers receive `{:failed, exception}` and are graded `:miss` with the exception propagated (`cache.ex:125-126`). The stale entry is **left in the table untouched** but is **not served** — the caller gets the error. No stale-if-error. Test: `cache_test.exs:327-365` (nothing stored, all callers error).
- **5xx / 4xx / 429**: the response reaches the store step, `Entry.from_response/3` returns `nil` (non-200), `Coordinator.done(name, key, response, nil)` stores nothing and hands the error response to followers (`cache.ex:147-167`, `coordinator.ex:134-137`). The previously stored stale entry survives (still usable for a later revalidation, until the retention sweep) but is not served now. Test for non-200 not cached: `cache_test.exs:176-186`.
- **TMDB Availability writer** (`lib/media_centaur/tmdb/availability.ex`), fed by `Client.get/3` after every call (`client.ex:227,232,237`):
  - `{:ok, :hit}` → `:unchanged` — a cache hit is not evidence (`availability.ex:37`, moduledoc `:11-14`).
  - `{:ok, :miss | :revalidate | :reload | :uncached}` → `report(:up)` (`availability.ex:38`). A 304 revalidation therefore closes an outage.
  - 401/403 → `{:down, :rejected}` (`:40-41`); **429 → `{:down, :rate_limited}`** (`:43`); ≥500 → `{:down, :unreachable}` (`:45-46`); other 4xx → `:unchanged` (`:48`); transport error → `{:down, :unreachable}` (`:49`). A down transition enqueues `ProbeJob` with a 5-minute cadence (`availability.ex:51-78`, `probe_job.ex:36-40`).
- **Holds vs. cached reads**: `TMDB.Client` itself never consults availability — every call proceeds and can be answered by the cache while TMDB is marked down. Holds live in the callers, and they hold the *whole call*, cache included:
  - `lib/media_centaur/release_tracking/refresher.ex:91` (whole refresh cycle held on `available?(:tmdb)`, rescheduled at the probe cadence, `:336`) and `:253` (`fetch_for_item` returns `{:held, item}` unless `up?(:tmdb)`). These calls pass `reload: true` anyway, so nothing would come from cache.
  - `lib/media_centaur/tmdb_artwork.ex:177` — the artwork warm is skipped unless `up?(:tmdb)`; whatever is already on disk is served.
  - No hold exists in the pipeline stages (`Pipeline.Stages.Search`, `FetchMetadata`) or in the LiveView search paths — those still call TMDB and so can still be served from the cache while TMDB is down.
  - `HttpClient.IncidentContext:16-27` documents the consequence: while held, TMDB traffic falls to ~3 requests per 15 min (the probe), so TMDB is graded by availability, not error share.

## 6. Observed TMDB freshness values

There is **no code, fixture or captured header** recording real TMDB `max-age` values; all test values are synthetic (`cache_test.exs:72,86,111,130,167,179,189,213,218,251,273,301,371,387`, `test/media_centaur/tmdb/client_test.exs:18` = `public, max-age=60`). Prose claims only:
- `docs/tmdb.md:74` — "about one hour for search and eight for details".
- `docs/plans/2026-09-04-http-client-cache-and-upstreams-panel.md:33-35` — "`Cache-Control: public, max-age=N`, roughly one hour for search and eight hours for details" and "weak ETags".
- `lib/media_centaur/tmdb/client.ex:28-31` — "TMDB marks details fresh for about eight hours, longer than its refresh interval".
- `lib/media_centaur/release_tracking/refresher.ex:247-249` — same claim.
- Nothing anywhere states a value for `/configuration` or for `image.tmdb.org` (the image client does not attach the cache at all; plan `:78-79`).

## 7. Traffic time-series read API

Module `MediaCentaur.HttpClient.Traffic` (`lib/media_centaur/http_client/traffic.ex`). Upstream key for TMDB API is `:tmdb`; images are `:tmdb_images` (`lib/media_centaur/http_client/upstream.ex:26-34`).

- `Traffic.totals(upstream_atom, opts)` — `traffic.ex:104`. `opts`: `seconds:` (default 900), `now:` (unix seconds, default `System.os_time(:second)`), `store_table:` (default `:http_traffic`). Reads the `:"10s"` resolution, so max lookback is 1 h (`lib/media_centaur/time_series/resolution.ex:20`). Returns `%{requests, failed, cached, mean_ms, worst_ms}` (`traffic.ex:46-52,253-261`). Example: `MediaCentaur.HttpClient.Traffic.totals(:tmdb, seconds: 900)`.
- `Traffic.series(upstream_atom, window, opts)` — `traffic.ex:73`. `window` is a `MediaCentaur.TimeSeries.Window.t()`: one of `:"5m" | :"1h" | :"5h" | :"1d" | :"1w" | :"1mo"` (`lib/media_centaur/time_series/window.ex:22-30`). `opts`: `now:`, `utc_offset:`, `store_table:`. Returns `%{window, bar_seconds, starts, went_out, failed, cached, mean_ms, worst_ms, totals}` — note `went_out = requests - failed` per bar (`traffic.ex:86-96`). Example: `Traffic.series(:tmdb, :"1h")`.
- `Traffic.recent(opts)` — `traffic.ex:129`. 20 newest rows, newest first, each `%{at, upstream, method, path, status, error, duration_ms, cache, seq}` (`traffic.ex:178-187`). **This is the only place the per-request cache outcome (`:hit`/`:miss`/`:revalidate`/`:reload`/`:uncached`) is readable** — the aggregates collapse everything but hits.
- `Traffic.last(upstream, opts)` → `%{outcome: :ok | :failed, at: DateTime.t()} | nil` (`traffic.ex:146`); `Traffic.last_success_at(upstream, opts)` → `DateTime.t() | nil` (`traffic.ex:155`). Neither is moved by cache hits.
- `Cache.stats/1` → `%{entries: n}` for a request or coordinator name (`cache.ex:74-80`); `Coordinator.entry_count/1` (`coordinator.ex:52`).
- Retention of the series itself: 10 s buckets 1 h, 1 min 6 h, 10 min 2 d, 1 h 31 d (`resolution.ex:8-13,20`; `lib/media_centaur/http_client/retention_policies.ex:16-22`). Snapshotted to disk roughly once a minute (`lib/media_centaur/time_series/store.ex:133,155-158`), so counts survive a dev-node restart — unlike the cache.

## 8. Rate limiter

`MediaCentaur.TMDB.RateLimiter` (`lib/media_centaur/tmdb/rate_limiter.ex`): sliding window, `@default_rate 30` requests per `@default_interval 1_000` ms (`:12-13`), started with no options in `lib/media_centaur/application.ex:89`, so the defaults are live. `handle_call(:acquire, …)` drops timestamps older than `now - interval` and either admits or replies `{:retry_after, ms}`; the *caller* sleeps and retries (`:74-85,39-49`). `status/0` returns `%{available, total, used}` (`:54,91-97`). `reset/0` is test-only (`:64`).

Cache hits bypass it entirely: the limiter step is `append_request_steps` and so runs after `http_cache_lookup`, which halts the pipeline with a synthesized response on a hit or a follower `{:done, _}` (`rate_limiter.ex:19-28`, `cache.ex:53,107-127`; attach order `client.ex:82-88`; ADR `decisions/architecture/2026-09-04-064-outbound-http-seam.md:34-35`). Misses, revalidations and reloads all spend a slot. The wait is recorded as `:http_rate_limit_wait` on the request and rides the telemetry event as `rate_limit_wait` (`rate_limiter.ex:30-34`, `instrument.ex:27-28,78`) — note `Traffic` does not currently store that field.

## 9. Observed on the owner's instance, 2026-09-19

The Traffic store began with the strip-chart work the same day, so it
held under 24 hours. In that span: `:tmdb` 15 requests, 0 failed, 0
cache hits recorded; `:tmdb_images` 3 requests. The console ring
attributed them: the refresher's six reloads at 10:14 and again at
16:14 (four movies, one series, one season — the season revalidated the
second time), one series detail fetch with three artwork downloads at
12:02, and two searches for the same title at 21:16 that differed only
in capitalisation and so missed the cache twice.
