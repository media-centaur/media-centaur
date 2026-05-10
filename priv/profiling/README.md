# Profiling

Automated profile runs for the in-memory projection layer
([ADR-041](../../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)).
Each run benchmarks the projections against the DB fallback,
times every top-level LiveView mount, and snapshots ETS memory.

## What's here

```
priv/profiling/
├── README.md             # this file
├── baseline-<scale>.md   # tracked reference snapshot, human-readable
├── baseline-<scale>.json # tracked reference snapshot, machine-readable
└── runs/                 # gitignored — per-run reports
    ├── <ISO8601>.md
    ├── <ISO8601>.json
    ├── latest.md         # symlink → most recent .md
    └── latest.json       # symlink → most recent .json
```

Tracked: this README + `baseline-*.{md,json}` for every scale we
have a reference for. Gitignored: everything under `runs/`. Per-run
reports are noisy by nature — only the curated baseline snapshot
goes into history.

## Running a profile

```sh
scripts/profile                    # default --scale=small (~30 s)
scripts/profile --scale=medium     # ~2 min
scripts/profile --scale=large      # ~5 min
scripts/profile --skip-seed        # re-measure against existing DB
scripts/profile --rebaseline       # prompt to promote run → baseline
```

`scripts/profile` sets `MEDIA_CENTARR_CONFIG_OVERRIDE` so the run
uses an isolated `priv/profile/` DB and never touches dev or prod.
The mix task refuses to start without that override.

## Reading the diff

When `baseline-<scale>.json` exists, every run is automatically
diffed against it. The terminal summary lists only metrics outside
the stable threshold, sorted by severity. Glyphs:

| Glyph              | Meaning                                |
|--------------------|----------------------------------------|
| `⚠ REGRESSION`     | ≥ +25 % slower / larger than baseline  |
| `⚠ regression`     | +10 % to +25 % slower / larger         |
| `↓ improvement`    | -10 % to -25 % faster / smaller        |
| `↓ IMPROVEMENT`    | ≥ -25 % faster / smaller               |

Anything within ±10 % is `stable` and not surfaced. Thresholds are
defaults in `MediaCentarr.Profile.Diff`; tighten via the diff API
if you need a sharper signal locally.

Diffed metrics: microbenchmark `median_ns` + `p99_ns` per scenario,
LiveView mount `p50_us` + `p95_us` per route, ETS `bytes` per
projection table.

## Establishing a new baseline

Rebaseline **after** a perf-sensitive change lands and you've
confirmed the new numbers are intentional — the baseline is the
reference future runs compare against, so a careless rebaseline
hides regressions.

```sh
scripts/profile --rebaseline
# review the printed diff, then accept the prompt
jj describe -m "perf: rebaseline profile (scale: small)"
```

The prompt returns `false` in non-interactive contexts, so a
script or CI invocation cannot rebaseline by accident. With no
existing baseline, `--rebaseline` simply *establishes* one.

## Machine specificity

Baselines reflect the hardware that produced them — CPU model,
core count, scheduler behaviour, page cache state. Cross-machine
diffs will show false regressions. Media Centarr is a
single-developer project, so a single machine's baseline is the
working norm; future contributors should rebaseline on their own
hardware before reading too much into deltas.

## Pointers

* [ADR-041 — In-memory projection architecture](../../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)
* `lib/media_centarr/profile/` — Suite, Bench, Mounts, Diff, RunData
* `lib/mix/tasks/profile.ex` — orchestration, terminal summary,
  `--rebaseline` flow
