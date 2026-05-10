# Media Centarr Profile Run

| key | value |
|-----|-------|
| run_id | `2026-05-10T17-37-54.576269Z` |
| timestamp | 2026-05-10T17:37:54.576278Z |
| scale | `small` |
| git sha | `011a9018` |
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
| cold-fallback | Library.list_in_progress/1 (limit: 30) | 204.65 | 4.89 ms | 4.53 ms | 8.26 ms | 3.54 ms | 605.0 KB |
| cold-fallback | Views.continue_watching/1 (limit: 30) | 204.47 | 4.89 ms | 4.49 ms | 9.57 ms | 3.06 ms | 608.2 KB |
| warm-cache | Views.continue_watching/1 (limit: 30) | 241.13 K | 4.15 µs | 3.07 µs | 10.85 µs | 2.66 µs | 3.0 KB |
| warm-cache | Library.list_in_progress/1 (limit: 30) | 203.37 | 4.92 ms | 4.6 ms | 8.79 ms | 3.35 ms | 605.1 KB |

### Library.Views.ContinueWatching.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | ContinueWatching.refresh_cache/0 | 216.74 | 4.61 ms | 4.36 ms | 8.96 ms | 3.18 ms | 610.2 KB |

### Settings.Cache

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Settings.get_by_key/1 (missing key) | 5.42 K | 184.35 µs | 169.36 µs | 458.19 µs | 96.81 µs | 40.0 KB |
| cold-fallback | Settings.get_by_key/1 (existing key) | 5.05 K | 198.12 µs | 184.16 µs | 455.76 µs | 102.81 µs | 43.2 KB |
| warm-cache | Settings.get_by_key/1 (missing key) | 7.52 M | 133.05 ns | 110.0 ns | 240.0 ns | 90.0 ns | 24 B |
| warm-cache | Settings.get_by_key/1 (existing key) | 6.81 M | 146.84 ns | 120.0 ns | 250.0 ns | 100.0 ns | 24 B |

## Page Mount Timing (Phoenix.LiveViewTest)

| Route | Warm cache? | runs | min | p50 | p95 | max |
|---|---|---:|---:|---:|---:|---:|
| `/` | true | 30 | 20.08 ms | 22.07 ms | 24.71 ms | 27.08 ms |
| `/library` | false | 30 | 22.42 ms | 28.05 ms | 38.83 ms | 41.03 ms |
| `/upcoming` | false | 30 | 24.48 ms | 30.93 ms | 41.6 ms | 71.96 ms |
| `/history` | false | 30 | 21.21 ms | 23.49 ms | 31.01 ms | 31.01 ms |
| `/review` | false | 30 | 22.2 ms | 23.77 ms | 26.22 ms | 29.75 ms |
| `/download` | false | 30 | 20.53 ms | 23.0 ms | 27.29 ms | 32.36 ms |
| `/status` | false | 30 | 21.2 ms | 25.04 ms | 29.07 ms | 29.53 ms |
| `/settings` | false | 30 | 23.14 ms | 25.46 ms | 29.02 ms | 29.23 ms |
| `/console` | false | 30 | 19.91 ms | 24.88 ms | 30.02 ms | 40.22 ms |

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
  * See `decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md`
    for the design these measurements validate.

