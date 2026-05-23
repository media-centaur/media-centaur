# Media Centaur Profile Run

| key | value |
|-----|-------|
| run_id | `2026-05-20T21-43-56.330368Z` |
| timestamp | 2026-05-20T21:43:56.330376Z |
| scale | `small` |
| git sha | `a3786e75` |
| git branch | `HEAD` |
| dirty? | false |
| OTP | 28 |
| Elixir | 1.19.5 |


## Environment

| key | value |
|-----|-------|
| schedulers_online | 12 |
| total schedulers | 12 |
| database_path | `/home/shawn/src/media-centaur/media-centaur-app/priv/profile/media-centaur.db` |


## Deltas vs `2026-05-10T20-22-14.635571Z` (sha `fbf1217b`)

| classification | count |
|---|---:|
| REGRESSION (>+25.0%) | 3 |
| regression (>+10.0%) | 1 |
| stable | 22 |
| improvement (<-10.0%) | 23 |
| IMPROVEMENT (<-25.0%) | 21 |
| new (no baseline value) | 14 |
| **total** | **84** |

### Flagged metrics

| classification | metric | current | baseline | Δ |
|---|---|---:|---:|---:|
| REGRESSION | Library.Views.ContinueWatching / cold-fallback / Library.list_in_progress/1 (limit: 30) (median_ns) | 4.15 ms | 3.19 ms | +30.2% |
| REGRESSION | Library.Views.ContinueWatching / cold-fallback / Views.continue_watching/1 (limit: 30) (median_ns) | 4.1 ms | 3.26 ms | +25.6% |
| REGRESSION | Library.Views.ContinueWatching / warm-cache / Library.list_in_progress/1 (limit: 30) (median_ns) | 4.16 ms | 3.19 ms | +30.3% |
| regression | Library.Views.ContinueWatching.refresh_cache/0 / default / ContinueWatching.refresh_cache/0 (median_ns) | 4.17 ms | 3.47 ms | +20.0% |
| improvement | Library.Views.HeroCandidates / cold-fallback / Library.list_hero_candidates/1 (limit: 12) (median_ns) | 1.31 ms | 1.47 ms | -10.9% |
| IMPROVEMENT | Library.Views.HeroCandidates / cold-fallback / Library.list_hero_candidates/1 (limit: 12) (p99_ns) | 1.85 ms | 2.95 ms | -37.3% |
| improvement | Library.Views.HeroCandidates / cold-fallback / Views.hero_candidates/1 (limit: 12) (p99_ns) | 1.96 ms | 2.6 ms | -24.8% |
| IMPROVEMENT | Library.Views.HeroCandidates / warm-cache / Library.list_hero_candidates/1 (limit: 12) (p99_ns) | 1.92 ms | 3.66 ms | -47.6% |
| improvement | Library.Views.HeroCandidates / warm-cache / Views.hero_candidates/1 (limit: 12) (median_ns) | 440.0 ns | 490.0 ns | -10.2% |
| IMPROVEMENT | Library.Views.HeroCandidates / warm-cache / Views.hero_candidates/1 (limit: 12) (p99_ns) | 680.0 ns | 970.0 ns | -29.9% |
| improvement | Library.Views.HeroCandidates.refresh_cache/0 / default / HeroCandidates.refresh_cache/0 (median_ns) | 1.32 ms | 1.48 ms | -10.9% |
| IMPROVEMENT | Library.Views.HeroCandidates.refresh_cache/0 / default / HeroCandidates.refresh_cache/0 (p99_ns) | 1.86 ms | 2.71 ms | -31.2% |
| improvement | Library.Views.RecentlyAdded / cold-fallback / Library.list_recently_added/1 (limit: 30) (median_ns) | 2.24 ms | 2.71 ms | -17.4% |
| IMPROVEMENT | Library.Views.RecentlyAdded / cold-fallback / Library.list_recently_added/1 (limit: 30) (p99_ns) | 3.01 ms | 4.73 ms | -36.3% |
| improvement | Library.Views.RecentlyAdded / cold-fallback / Views.recently_added/1 (limit: 30) (median_ns) | 2.25 ms | 2.53 ms | -11.0% |
| IMPROVEMENT | Library.Views.RecentlyAdded / cold-fallback / Views.recently_added/1 (limit: 30) (p99_ns) | 3.05 ms | 4.21 ms | -27.5% |
| improvement | Library.Views.RecentlyAdded / warm-cache / Views.recently_added/1 (limit: 30) (p99_ns) | 13.09 µs | 17.45 µs | -25.0% |
| improvement | Library.Views.RecentlyAdded.refresh_cache/0 / default / RecentlyAdded.refresh_cache/0 (median_ns) | 2.75 ms | 3.48 ms | -20.8% |
| IMPROVEMENT | Library.Views.RecentlyAdded.refresh_cache/0 / default / RecentlyAdded.refresh_cache/0 (p99_ns) | 3.69 ms | 5.3 ms | -30.3% |
| IMPROVEMENT | ReleaseTracking.Views.ComingUp / cold-fallback / ReleaseTracking.list_releases_between/3 (limit: 30) (p99_ns) | 396.36 µs | 546.21 µs | -27.4% |
| IMPROVEMENT | ReleaseTracking.Views.ComingUp / cold-fallback / Views.coming_up/3 (limit: 30) (p99_ns) | 392.66 µs | 561.8 µs | -30.1% |
| improvement | ReleaseTracking.Views.ComingUp / warm-cache / ReleaseTracking.list_releases_between/3 (limit: 30) (median_ns) | 251.6 µs | 307.33 µs | -18.1% |
| IMPROVEMENT | ReleaseTracking.Views.ComingUp / warm-cache / ReleaseTracking.list_releases_between/3 (limit: 30) (p99_ns) | 400.86 µs | 690.81 µs | -42.0% |
| IMPROVEMENT | ReleaseTracking.Views.ComingUp / warm-cache / Views.coming_up/3 (limit: 30) (median_ns) | 430.0 ns | 700.0 ns | -38.6% |
| IMPROVEMENT | ReleaseTracking.Views.ComingUp / warm-cache / Views.coming_up/3 (limit: 30) (p99_ns) | 680.0 ns | 1.14 µs | -40.4% |
| improvement | ReleaseTracking.Views.ComingUp.refresh_cache/0 / default / ComingUp.refresh_cache/0 (median_ns) | 254.46 µs | 287.64 µs | -11.5% |
| IMPROVEMENT | ReleaseTracking.Views.ComingUp.refresh_cache/0 / default / ComingUp.refresh_cache/0 (p99_ns) | 386.94 µs | 641.48 µs | -39.7% |
| improvement | Settings.Cache / cold-fallback / Settings.get_by_key/1 (existing key) (median_ns) | 112.56 µs | 135.54 µs | -17.0% |
| IMPROVEMENT | Settings.Cache / cold-fallback / Settings.get_by_key/1 (existing key) (p99_ns) | 199.67 µs | 287.64 µs | -30.6% |
| improvement | Settings.Cache / cold-fallback / Settings.get_by_key/1 (missing key) (median_ns) | 101.81 µs | 115.89 µs | -12.1% |
| improvement | Settings.Cache / cold-fallback / Settings.get_by_key/1 (missing key) (p99_ns) | 182.42 µs | 227.28 µs | -19.7% |
| IMPROVEMENT | Settings.Cache / warm-cache / Settings.get_by_key/1 (existing key) (median_ns) | 100.0 ns | 140.0 ns | -28.6% |
| improvement | Settings.Cache / warm-cache / Settings.get_by_key/1 (existing key) (p99_ns) | 200.0 ns | 260.0 ns | -23.1% |
| IMPROVEMENT | Settings.Cache / warm-cache / Settings.get_by_key/1 (missing key) (median_ns) | 90.0 ns | 200.0 ns | -55.0% |
| IMPROVEMENT | Settings.Cache / warm-cache / Settings.get_by_key/1 (missing key) (p99_ns) | 160.0 ns | 270.0 ns | -40.7% |
| improvement | mount `/` (p50_us) | 14.98 ms | 17.69 ms | -15.3% |
| improvement | mount `/` (p95_us) | 16.33 ms | 21.56 ms | -24.2% |
| improvement | mount `/library` (p50_us) | 15.01 ms | 17.49 ms | -14.2% |
| improvement | mount `/upcoming` (p50_us) | 16.82 ms | 19.05 ms | -11.7% |
| improvement | mount `/upcoming` (p95_us) | 18.28 ms | 21.7 ms | -15.7% |
| improvement | mount `/review` (p50_us) | 17.03 ms | 20.07 ms | -15.1% |
| improvement | mount `/review` (p95_us) | 18.28 ms | 22.67 ms | -19.4% |
| IMPROVEMENT | mount `/status` (p50_us) | 17.47 ms | 24.74 ms | -29.4% |
| IMPROVEMENT | mount `/status` (p95_us) | 18.94 ms | 29.38 ms | -35.5% |
| IMPROVEMENT | mount `/settings` (p50_us) | 18.56 ms | 25.98 ms | -28.6% |
| IMPROVEMENT | mount `/settings` (p95_us) | 20.61 ms | 29.9 ms | -31.1% |
| improvement | mount `/console` (p50_us) | 16.65 ms | 18.83 ms | -11.6% |
| improvement | mount `/console` (p95_us) | 18.4 ms | 20.66 ms | -11.0% |

## Microbenchmarks

### Library.Views.ContinueWatching

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Views.continue_watching/1 (limit: 30) | 240.95 | 4.15 ms | 4.1 ms | 5.08 ms | 3.6 ms | 743.6 KB |
| cold-fallback | Library.list_in_progress/1 (limit: 30) | 237.26 | 4.21 ms | 4.15 ms | 5.39 ms | 3.56 ms | 755.5 KB |
| warm-cache | Views.continue_watching/1 (limit: 30) | 350.8 K | 2.85 µs | 2.6 µs | 6.1 µs | 2.49 µs | 3.0 KB |
| warm-cache | Library.list_in_progress/1 (limit: 30) | 238.17 | 4.2 ms | 4.16 ms | 5.05 ms | 3.6 ms | 755.5 KB |

### Library.Views.ContinueWatching.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | ContinueWatching.refresh_cache/0 | 236.74 | 4.22 ms | 4.17 ms | 5.29 ms | 3.63 ms | 746.9 KB |

### Library.Views.HeroCandidates

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Views.hero_candidates/1 (limit: 12) | 742.22 | 1.35 ms | 1.3 ms | 1.96 ms | 1.17 ms | 278.7 KB |
| cold-fallback | Library.list_hero_candidates/1 (limit: 12) | 737.87 | 1.36 ms | 1.31 ms | 1.85 ms | 1.17 ms | 298.4 KB |
| warm-cache | Views.hero_candidates/1 (limit: 12) | 2.17 M | 461.21 ns | 440.0 ns | 680.0 ns | 410.0 ns | 48 B |
| warm-cache | Library.list_hero_candidates/1 (limit: 12) | 732.41 | 1.37 ms | 1.32 ms | 1.92 ms | 1.17 ms | 298.4 KB |

### Library.Views.HeroCandidates.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | HeroCandidates.refresh_cache/0 | 735.66 | 1.36 ms | 1.32 ms | 1.86 ms | 1.18 ms | 280.1 KB |

### Library.Views.RecentlyAdded

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Library.list_recently_added/1 (limit: 30) | 436.94 | 2.29 ms | 2.24 ms | 3.01 ms | 2.05 ms | 751.9 KB |
| cold-fallback | Views.recently_added/1 (limit: 30) | 434.35 | 2.3 ms | 2.25 ms | 3.05 ms | 2.06 ms | 756.9 KB |
| warm-cache | Views.recently_added/1 (limit: 30) | 142.04 K | 7.04 µs | 6.69 µs | 13.09 µs | 5.83 µs | 7.8 KB |
| warm-cache | Library.list_recently_added/1 (limit: 30) | 420.9 | 2.38 ms | 2.31 ms | 3.49 ms | 2.07 ms | 751.9 KB |

### Library.Views.RecentlyAdded.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | RecentlyAdded.refresh_cache/0 | 355.28 | 2.81 ms | 2.75 ms | 3.69 ms | 2.46 ms | 1.15 MB |

### ReleaseTracking.Views.ComingUp

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | ReleaseTracking.list_releases_between/3 (limit: 30) | 3.84 K | 260.64 µs | 251.89 µs | 396.36 µs | 201.78 µs | 51.2 KB |
| cold-fallback | Views.coming_up/3 (limit: 30) | 3.83 K | 261.08 µs | 251.84 µs | 392.66 µs | 201.37 µs | 51.3 KB |
| warm-cache | Views.coming_up/3 (limit: 30) | 2.23 M | 447.6 ns | 430.0 ns | 680.0 ns | 400.0 ns | 80 B |
| warm-cache | ReleaseTracking.list_releases_between/3 (limit: 30) | 3.82 K | 261.84 µs | 251.6 µs | 400.86 µs | 201.66 µs | 51.2 KB |

### ReleaseTracking.Views.ComingUp.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | ComingUp.refresh_cache/0 | 3.79 K | 264.08 µs | 254.46 µs | 386.94 µs | 210.36 µs | 53.1 KB |

### Settings.Cache

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Settings.get_by_key/1 (missing key) | 9.29 K | 107.67 µs | 101.81 µs | 182.42 µs | 77.54 µs | 39.9 KB |
| cold-fallback | Settings.get_by_key/1 (existing key) | 8.43 K | 118.59 µs | 112.56 µs | 199.67 µs | 85.82 µs | 43.2 KB |
| warm-cache | Settings.get_by_key/1 (missing key) | 10.51 M | 95.12 ns | 90.0 ns | 160.0 ns | 80.0 ns | 24 B |
| warm-cache | Settings.get_by_key/1 (existing key) | 9.79 M | 102.13 ns | 100.0 ns | 200.0 ns | 90.0 ns | 24 B |

### WatchHistory.Views.Summary

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| cold-fallback | Views.summary/0 | 810.46 | 1.23 ms | 1.2 ms | 1.79 ms | 969.03 µs | 906.5 KB |
| cold-fallback | WatchHistory.stats/0 + heatmap + 3x rewatch_count_map | 795.81 | 1.26 ms | 1.21 ms | 1.91 ms | 975.09 µs | 906.5 KB |
| warm-cache | Views.summary/0 | 17.16 M | 58.27 ns | 60.0 ns | 110.0 ns | 50.0 ns | 0 B |
| warm-cache | WatchHistory.stats/0 + heatmap + 3x rewatch_count_map | 794.57 | 1.26 ms | 1.21 ms | 1.88 ms | 947.9 µs | 906.5 KB |

### WatchHistory.Views.Summary.refresh_cache/0

| Input | Scenario | ips | avg | p50 | p99 | min | memory |
|---|---|---:|---:|---:|---:|---:|---:|
| default | Summary.refresh_cache/0 | 770.64 | 1.3 ms | 1.26 ms | 1.89 ms | 1.01 ms | 912.7 KB |

## Page Mount Timing (Phoenix.LiveViewTest)

| Route | Warm cache? | runs | min | p50 | p95 | max |
|---|---|---:|---:|---:|---:|---:|
| `/` | true | 30 | 14.18 ms | 14.98 ms | 16.33 ms | 20.5 ms |
| `/library` | false | 30 | 14.28 ms | 15.01 ms | 18.42 ms | 20.23 ms |
| `/upcoming` | false | 30 | 15.81 ms | 16.82 ms | 18.28 ms | 18.42 ms |
| `/history` | false | 30 | 15.98 ms | 17.5 ms | 19.97 ms | 19.98 ms |
| `/review` | false | 30 | 15.59 ms | 17.03 ms | 18.28 ms | 19.73 ms |
| `/download` | false | 30 | 15.58 ms | 16.74 ms | 20.93 ms | 24.41 ms |
| `/status` | false | 30 | 16.25 ms | 17.47 ms | 18.94 ms | 19.03 ms |
| `/settings` | false | 30 | 16.88 ms | 18.56 ms | 20.61 ms | 20.77 ms |
| `/console` | false | 30 | 15.42 ms | 16.65 ms | 18.4 ms | 20.71 ms |

## ETS Memory

| Table | Size (rows) | Memory (KB) |
|---|---:|---:|
| `:library_view_browse` | 0 | 2.0 |
| `:library_view_continue_watching` | 12 | 9.6 |
| `:library_view_detail` | 0 | 3.3 |
| `:library_view_detail_canonical` | 0 | 3.3 |
| `:library_view_hero_candidates` | 0 | 2.0 |
| `:library_view_recently_added` | 60 | 17.4 |
| `:library_view_search` | 0 | 3.3 |
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

