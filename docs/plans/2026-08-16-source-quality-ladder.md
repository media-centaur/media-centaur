# Within-Tier Source-Quality Ladder

## Problem Statement

Within a resolution tier the release picker has no opinion. `Quality` knows
two tiers (4K, 1080p) and breaks ties on seeders — a signal that is
permanently `nil` on indexers that don't report it, so within-tier auto-picks
degrade to "first result in indexer order". Size cannot stand in as a quality
proxy: it is confounded by audio tracks, subtitle bundles, and container
overhead, and a numeric size budget would demand exactly the release-landscape
expertise a setting exists to encode.

The honest within-tier signal is the release title's **source tokens**: a
remux is untouched disc video by definition, a WEB-DL is an untranscoded
stream, an encode is a re-encode of unknowable fidelity.

## User-Facing Behavior

- Auto-picks within a resolution tier follow a source-fidelity ladder instead
  of list order. With the default preference, a remux wins over a WEB-DL wins
  over a BluRay encode.
- A new Settings dropdown, **Release size preference**, offers exactly two
  semantic answers: *Best fidelity* (default) and *Save space*. No numbers,
  no thresholds, no experimentation loop.
- The swap picker and release rows label each release's source ("Remux",
  "WEB-DL", …) so the pick is legible, and sort by the active ladder.

## Design

The invariant (ADR-061): **gates express bounds and safety (quality
floor/ceiling, red flags); ladders express preference; the profile picks the
ladder; size is never a ranking signal and never a gate.** Nothing can go
unfound because of this feature — the profile reorders, it never excludes.

### Source classification (`MediaCentaur.Search.Quality`)

Token-based, downcased, mirrored on the existing resolution parsing:

| Source | Tokens |
|---|---|
| `:remux` | `remux` (checked first — beats co-occurring `bluray`) |
| `:web_dl` | `web-dl`, `webdl`, `web.dl` |
| `:bluray_encode` | `bluray`, `blu-ray`, `bdrip`, `brrip` without `remux` |
| `:webrip` | `webrip`, `web-rip`, `web.rip` |
| `:hdtv` | `hdtv` |
| `:unknown` | none of the above (bare `WEB` deliberately unclassified — ambiguous scene token) |

### Ladders (fixed, selected by profile)

| Rank | `fidelity` (default) | `space` |
|---|---|---|
| 4 | remux | bluray_encode |
| 3 | web_dl | web_dl |
| 2 | bluray_encode | webrip / hdtv |
| 1 | webrip / hdtv | remux |
| 0 | unknown | unknown |

WEB-DL above BluRay encode on the fidelity ladder is deliberate
(predictable-good over variance); remux at rank 1 — not excluded — on the
space ladder keeps remux-only titles coverable.

### Rank composition

Everywhere a release is ranked, the sort key grows one element between the
existing two: `{resolution, source, seeders}`. Resolution stays primary;
source never gates; seeders stay the final tiebreak.

Sites:
- `RunPlan` movie pick (`run_movie/3` `max_by`)
- `Planner` consolidation sort, singles `max_by`, and offer sort — profile
  arrives via `prefs.size_preference` (planner stays pure)
- `Plans.alternatives_for/1` swap-picker sort

### Setting

`auto_grab.size_preference` (`"fidelity"` | `"space"`, default `"fidelity"`)
in the Settings DB, resolved through `AutoGrabSettings`, edited in the
Settings → Acquisition auto-grab defaults form.

### Display

`ReleaseFacts` derives a source label from the entry title it already
carries — no view-model struct changes.

### Integration Points

Wiki `Settings-Reference.md` documents the new setting.

### Constraints

- Planner purity (no I/O) — profile threads through prefs.
- ADR-027 append-only regression tests.

## Acceptance Criteria

- [ ] A same-tier corpus auto-picks the remux under `fidelity` and the BluRay
      encode under `space`
- [ ] Swap picker sorts by the active ladder and labels source
- [ ] Resolution still dominates: a 4K non-remux beats a 1080p remux
- [ ] Source never gates: a remux-only title is still assigned under `space`
- [ ] Wiki Settings-Reference documents the setting

## Decisions

See `decisions/architecture/2026-08-16-061-source-quality-ladder.md`.

## Smoke Tests

Existing settings-page smoke covers the new dropdown's render path; behaviour
tests live in `quality_test.exs`, `planner_test.exs`, and the run-plan /
plans tests.
