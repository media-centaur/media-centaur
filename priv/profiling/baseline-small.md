# Media Centarr Profile Run

| key | value |
|-----|-------|
| run_id | `2026-05-10T20-22-14.635571Z` |
| timestamp | 2026-05-10T20:22:14.635579Z |
| scale | `small` |
| git sha | `fbf1217b` |
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


## Deltas vs `2026-05-10T18-05-42.017172Z` (sha `e8fbcb01`)

| classification | count |
|---|---:|
| REGRESSION (>+25.0%) | 5 |
| regression (>+10.0%) | 2 |
| stable | 10 |
| improvement (<-10.0%) | 16 |
| IMPROVEMENT (<-25.0%) | 4 |
| new (no baseline value) | 33 |
| **total** | **70** |

### Flagged metrics

| classification | metric | current | baseline | Δ |
|---|---|---:|---:|---:|
| improvement | Library.Views.ContinueWatching / cold-fallback / Library.list_in_progress/1 (limit: 30) (median_ns) | 3.19 ms | 3.67 ms | -13.2% |
| improvement | Library.Views.ContinueWatching / cold-fallback / Library.list_in_progress/1 (limit: 30) (p99_ns) | 4.98 ms | 5.59 ms | -10.9% |
| improvement | Library.Views.ContinueWatching / cold-fallback / Views.continue_watching/1 (limit: 30) (median_ns) | 3.26 ms | 3.72 ms | -12.2% |
| improvement | Library.Views.ContinueWatching / cold-fallback / Views.continue_watching/1 (limit: 30) (p99_ns) | 4.74 ms | 6.03 ms | -21.5% |
| improvement | Library.Views.ContinueWatching / warm-cache / Library.list_in_progress/1 (limit: 30) (median_ns) | 3.19 ms | 3.76 ms | -15.1% |
| improvement | Library.Views.ContinueWatching / warm-cache / Library.list_in_progress/1 (limit: 30) (p99_ns) | 4.66 ms | 6.14 ms | -24.1% |
| improvement | Library.Views.ContinueWatching / warm-cache / Views.continue_watching/1 (limit: 30) (p99_ns) | 6.32 µs | 7.94 µs | -20.4% |
| improvement | Library.Views.ContinueWatching.refresh_cache/0 / default / ContinueWatching.refresh_cache/0 (median_ns) | 3.47 ms | 3.88 ms | -10.4% |
| improvement | Library.Views.ContinueWatching.refresh_cache/0 / default / ContinueWatching.refresh_cache/0 (p99_ns) | 5.64 ms | 7.01 ms | -19.5% |
| improvement | Settings.Cache / cold-fallback / Settings.get_by_key/1 (existing key) (median_ns) | 135.54 µs | 159.71 µs | -15.1% |
| IMPROVEMENT | Settings.Cache / cold-fallback / Settings.get_by_key/1 (existing key) (p99_ns) | 287.64 µs | 441.57 µs | -34.9% |
| improvement | Settings.Cache / cold-fallback / Settings.get_by_key/1 (missing key) (median_ns) | 115.89 µs | 139.73 µs | -17.1% |
| IMPROVEMENT | Settings.Cache / cold-fallback / Settings.get_by_key/1 (missing key) (p99_ns) | 227.28 µs | 340.88 µs | -33.3% |
| REGRESSION | Settings.Cache / warm-cache / Settings.get_by_key/1 (existing key) (median_ns) | 140.0 ns | 110.0 ns | +27.3% |
| REGRESSION | Settings.Cache / warm-cache / Settings.get_by_key/1 (missing key) (median_ns) | 200.0 ns | 110.0 ns | +81.8% |
| regression | Settings.Cache / warm-cache / Settings.get_by_key/1 (missing key) (p99_ns) | 270.0 ns | 230.0 ns | +17.4% |
| improvement | mount `/library` (p95_us) | 19.28 ms | 21.55 ms | -10.5% |
| improvement | mount `/history` (p95_us) | 21.87 ms | 24.65 ms | -11.3% |
| improvement | mount `/review` (p50_us) | 20.07 ms | 26.11 ms | -23.1% |
| improvement | mount `/review` (p95_us) | 22.67 ms | 30.08 ms | -24.6% |
| IMPROVEMENT | mount `/download` (p50_us) | 17.9 ms | 24.36 ms | -26.5% |
| IMPROVEMENT | mount `/download` (p95_us) | 19.91 ms | 32.45 ms | -38.6% |
| regression | mount `/status` (p50_us) | 24.74 ms | 20.95 ms | +18.1% |
| REGRESSION | mount `/status` (p95_us) | 29.38 ms | 23.27 ms | +26.2% |
| REGRESSION | mount `/settings` (p50_us) | 25.98 ms | 20.67 ms | +25.7% |
| REGRESSION | mount `/settings` (p95_us) | 29.9 ms | 22.92 ms | +30.4% |
| improvement | mount `/console` (p95_us) | 20.66 ms | 24.71 ms | -16.4% |

## Microbenchmarks

### Library.Views.ContinueWatching

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Library.list_in_progress/1 (limit: 30) | 305.65 | 3.27 ms | 3.19 ms | 4.98 ms | 2.4 ms | 603.4 KB |
| cold-fallback | Views.continue_watching/1 (limit: 30) | 299.95 | 3.33 ms | 3.26 ms | 4.74 ms | 2.47 ms | 607.1 KB |
| warm-cache | Views.continue_watching/1 (limit: 30) | 335.35 K | 2.98 µs | 2.62 µs | 6.32 µs | 2.45 µs | 3.0 KB |
| warm-cache | Library.list_in_progress/1 (limit: 30) | 307.54 | 3.25 ms | 3.19 ms | 4.66 ms | 2.43 ms | 603.6 KB |

### Library.Views.ContinueWatching.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | ContinueWatching.refresh_cache/0 | 279.52 | 3.58 ms | 3.47 ms | 5.64 ms | 2.51 ms | 607.8 KB |

### Library.Views.HeroCandidates

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Views.hero_candidates/1 (limit: 12) | 671.17 | 1.49 ms | 1.42 ms | 2.6 ms | 1.11 ms | 281.0 KB |
| cold-fallback | Library.list_hero_candidates/1 (limit: 12) | 640.87 | 1.56 ms | 1.47 ms | 2.95 ms | 1.12 ms | 283.1 KB |
| warm-cache | Views.hero_candidates/1 (limit: 12) | 1.71 M | 586.42 ns | 490.0 ns | 970.0 ns | 420.0 ns | 48 B |
| warm-cache | Library.list_hero_candidates/1 (limit: 12) | 671.42 | 1.49 ms | 1.34 ms | 3.66 ms | 1.12 ms | 283.1 KB |

### Library.Views.HeroCandidates.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | HeroCandidates.refresh_cache/0 | 641.3 | 1.56 ms | 1.48 ms | 2.71 ms | 1.16 ms | 282.4 KB |

### Library.Views.RecentlyAdded

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Views.recently_added/1 (limit: 30) | 379.63 | 2.63 ms | 2.53 ms | 4.21 ms | 2.06 ms | 809.9 KB |
| cold-fallback | Library.list_recently_added/1 (limit: 30) | 355.73 | 2.81 ms | 2.71 ms | 4.73 ms | 2.07 ms | 805.6 KB |
| warm-cache | Views.recently_added/1 (limit: 30) | 131.36 K | 7.61 µs | 6.79 µs | 17.45 µs | 5.8 µs | 7.8 KB |
| warm-cache | Library.list_recently_added/1 (limit: 30) | 385.53 | 2.59 ms | 2.53 ms | 3.59 ms | 2.06 ms | 805.7 KB |

### Library.Views.RecentlyAdded.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | RecentlyAdded.refresh_cache/0 | 280.18 | 3.57 ms | 3.48 ms | 5.3 ms | 2.61 ms | 1.26 MB |

### ReleaseTracking.Views.ComingUp

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | ReleaseTracking.list_releases_between/3 (limit: 30) | 3.41 K | 292.91 µs | 274.08 µs | 546.21 µs | 198.34 µs | 51.1 KB |
| cold-fallback | Views.coming_up/3 (limit: 30) | 3.4 K | 293.91 µs | 273.22 µs | 561.8 µs | 196.72 µs | 51.1 KB |
| warm-cache | Views.coming_up/3 (limit: 30) | 1.38 M | 727.0 ns | 700.0 ns | 1.14 µs | 440.0 ns | 80 B |
| warm-cache | ReleaseTracking.list_releases_between/3 (limit: 30) | 2.96 K | 337.39 µs | 307.33 µs | 690.81 µs | 196.08 µs | 51.1 KB |

### ReleaseTracking.Views.ComingUp.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | ComingUp.refresh_cache/0 | 3.2 K | 312.49 µs | 287.64 µs | 641.48 µs | 202.65 µs | 53.0 KB |

### Settings.Cache

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Settings.get_by_key/1 (missing key) | 8.09 K | 123.63 µs | 115.89 µs | 227.28 µs | 80.7 µs | 39.9 KB |
| cold-fallback | Settings.get_by_key/1 (existing key) | 6.88 K | 145.44 µs | 135.54 µs | 287.64 µs | 88.24 µs | 43.2 KB |
| warm-cache | Settings.get_by_key/1 (existing key) | 6.28 M | 159.16 ns | 140.0 ns | 260.0 ns | 90.0 ns | 24 B |
| warm-cache | Settings.get_by_key/1 (missing key) | 4.26 M | 234.5 ns | 200.0 ns | 270.0 ns | 90.0 ns | 24 B |

## Page Mount Timing (Phoenix.LiveViewTest)

| Route | Warm cache? | runs | min | p50 | p95 | max |
|---|---|---:|---:|---:|---:|---:|
| `/` | true | 30 | 15.97 ms | 17.69 ms | 21.56 ms | 23.22 ms |
| `/library` | false | 30 | 15.58 ms | 17.49 ms | 19.28 ms | 23.74 ms |
| `/upcoming` | false | 30 | 17.26 ms | 19.05 ms | 21.7 ms | 25.16 ms |
| `/history` | false | 30 | 16.89 ms | 19.05 ms | 21.87 ms | 22.17 ms |
| `/review` | false | 30 | 17.49 ms | 20.07 ms | 22.67 ms | 24.57 ms |
| `/download` | false | 30 | 16.11 ms | 17.9 ms | 19.91 ms | 21.07 ms |
| `/status` | false | 30 | 20.43 ms | 24.74 ms | 29.38 ms | 30.18 ms |
| `/settings` | false | 30 | 19.59 ms | 25.98 ms | 29.9 ms | 30.02 ms |
| `/console` | false | 30 | 17.0 ms | 18.83 ms | 20.66 ms | 25.0 ms |

## ETS Memory

| Table | Size (rows) | Memory (KB) |
|---|---:|---:|
| `:library_view_continue_watching` | 12 | 9.6 |
| `:library_view_hero_candidates` | 0 | 2.0 |
| `:library_view_recently_added` | 60 | 17.4 |
| `:release_tracking_view_coming_up` | 0 | 2.0 |

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

