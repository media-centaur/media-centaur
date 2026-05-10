# Media Centarr Profile Run

| key | value |
|-----|-------|
| run_id | `2026-05-10T18-05-42.017172Z` |
| timestamp | 2026-05-10T18:05:42.017182Z |
| scale | `small` |
| git sha | `e8fbcb01` |
| git branch | `HEAD` |
| dirty? | true |
| OTP | 28 |
| Elixir | 1.19.5 |


## Environment

| key | value |
|-----|-------|
| schedulers_online | 12 |
| total schedulers | 12 |
| database_path | `/home/shawn/src/media-centarr/media-centarr-app/priv/profile/media-centarr.db` |


## Microbenchmarks

### Library.Views.ContinueWatching

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Library.list_in_progress/1 (limit: 30) | 265.4 | 3.77 ms | 3.67 ms | 5.59 ms | 2.87 ms | 598.4 KB |
| cold-fallback | Views.continue_watching/1 (limit: 30) | 256.21 | 3.9 ms | 3.72 ms | 6.03 ms | 2.78 ms | 605.6 KB |
| warm-cache | Views.continue_watching/1 (limit: 30) | 276.74 K | 3.61 µs | 2.89 µs | 7.94 µs | 2.51 µs | 3.0 KB |
| warm-cache | Library.list_in_progress/1 (limit: 30) | 252.16 | 3.97 ms | 3.76 ms | 6.14 ms | 2.69 ms | 598.1 KB |

### Library.Views.ContinueWatching.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | ContinueWatching.refresh_cache/0 | 238.09 | 4.2 ms | 3.88 ms | 7.01 ms | 2.89 ms | 607.6 KB |

### Settings.Cache

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Settings.get_by_key/1 (missing key) | 6.73 K | 148.52 µs | 139.73 µs | 340.88 µs | 84.69 µs | 40.0 KB |
| cold-fallback | Settings.get_by_key/1 (existing key) | 5.81 K | 172.1 µs | 159.71 µs | 441.57 µs | 96.07 µs | 43.2 KB |
| warm-cache | Settings.get_by_key/1 (missing key) | 8.18 M | 122.18 ns | 110.0 ns | 230.0 ns | 90.0 ns | 24 B |
| warm-cache | Settings.get_by_key/1 (existing key) | 6.75 M | 148.12 ns | 110.0 ns | 250.0 ns | 100.0 ns | 24 B |

## Page Mount Timing (Phoenix.LiveViewTest)

| Route | Warm cache? | runs | min | p50 | p95 | max |
|---|---|---:|---:|---:|---:|---:|
| `/` | true | 30 | 16.15 ms | 17.64 ms | 21.78 ms | 23.97 ms |
| `/library` | false | 30 | 16.18 ms | 17.7 ms | 21.55 ms | 40.84 ms |
| `/upcoming` | false | 30 | 17.68 ms | 19.48 ms | 20.97 ms | 21.03 ms |
| `/history` | false | 30 | 17.51 ms | 20.42 ms | 24.65 ms | 25.2 ms |
| `/review` | false | 30 | 21.48 ms | 26.11 ms | 30.08 ms | 30.7 ms |
| `/download` | false | 30 | 20.51 ms | 24.36 ms | 32.45 ms | 56.26 ms |
| `/status` | false | 30 | 18.66 ms | 20.95 ms | 23.27 ms | 23.66 ms |
| `/settings` | false | 30 | 18.82 ms | 20.67 ms | 22.92 ms | 24.03 ms |
| `/console` | false | 30 | 18.35 ms | 20.57 ms | 24.71 ms | 27.44 ms |

## ETS Memory

| Table | Size (rows) | Memory (KB) |
|---|---:|---:|
| `:library_view_continue_watching` | 12 | 9.6 |

## Notes

  * No concurrent Pipeline / Watcher activity during the run.
  * Per-scenario warmup applied (Benchee `warmup: 2`s; mount
    harness 5× warmup + 30× timed).
  * Benchee memory metric measures the calling process and
    includes Benchee's own allocations; treat as relative-only.
  * Sample sizes are floors — bump in `Profile.Mounts.@runs`
    and `Profile.Bench.@benchee_opts[:time]` if results show
    bimodal distributions.
  * Protocol consolidation is disabled in `MIX_ENV=dev`; absolute
    timings are slightly inflated, ratios are unaffected.
  * See `decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md`
    for the design these measurements validate.

