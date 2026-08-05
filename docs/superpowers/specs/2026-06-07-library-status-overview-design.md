# Library overview on the Status page

**Date:** 2026-06-07
**Status:** Implemented (revised — see "Placement revision" below)

## Placement revision (post-feedback)

The overview originally shipped as a top-level "Your library" section above the
health board. Per feedback, it was relocated to be the **Library subsystem's
drill-in Activity widget** — it now fleshes out the Library tile's drill-in
(which previously only showed "No issues for this subsystem" + technical logs),
using the existing `ActivityWidgets` registry (`library:
{ActivityWidgetComponents, :library_widget}`). The `LibraryOverview` read-model,
`Library.Completeness`, the cards, and all tests are unchanged; only the render
location moved. The rest of this doc describes the original top-section design
for context.

## Goal

Today `/status` (`StatusLive`) is purely operational: an 8-subsystem health
board, incident drill-ins, activity widgets, and the collapsible "technical
logs." It never answers *"how is my library doing?"*

Add a **"Your library" overview** above the existing health board, giving the
page two altitudes:

1. **Your library** (new) — library-state summary the owner cares about.
2. **System health** (unchanged) — the existing operational board.

## The four overview cards

| Card | Content | Data source |
|------|---------|-------------|
| **At a glance + recent** | movie / show / episode counts, total size on disk, strip of recently-added posters | `Status.fetch_library_stats/0` (exists), `FilePresence.total_size_bytes/0` (new), `Library.list_recently_added/1` (exists) |
| **Pending work** | files awaiting review (→ `/review`), in-flight acquisitions (→ `/download`) | `Review.list_pending_files_for_review/0` (exists), `Acquisition.Pursuits.list_active/0` (exists) |
| **Completeness gaps** | missing artwork (→ repair), missing metadata, incomplete seasons | `Maintenance.missing_images_summary/0` (exists), `Library.Completeness.*` (new) |
| **Storage outlook** | per-drive headroom, drive-offline at-risk files | `Storage.measure_all/0` + `AbsenceSweeper.at_risk_summary/0` (exist) |

### Deliberate consolidation (avoid duplication)

The approved sketch listed "unmatched files" and "missing-on-disk" under
Completeness gaps. Routing them instead to **Pending work** (review queue) and
**Storage outlook** (at-risk) keeps each signal in one place. Completeness gaps
then holds only the *distinct* quality signals: artwork, metadata, season gaps.

### Scoped out (YAGNI for v1)

- Precise "+N added this week" counter — the recent-poster strip already
  conveys freshness; a bespoke 5-type `inserted_at` fan-out isn't worth it.
- Per-download progress bars in the overview — `/download` owns that detail;
  the card shows a count + link.

## Architecture

```
StatusLive (web, thin wiring)
  └─ start_async(:status_overview) ──► MediaCentaur.Status.fetch_overview/0
                                          │  (top-level boundary, check:[in:false,out:false]
                                          │   — the intended cross-context read aggregator,
                                          │   currently tested but unwired)
                                          ├─ Status.fetch_library_stats/0        (counts)
                                          ├─ Library.FilePresence.total_size_bytes/0   (new)
                                          ├─ Library.list_recently_added/1
                                          ├─ Review.list_pending_files_for_review/0
                                          ├─ Acquisition.Pursuits.list_active/0
                                          ├─ Maintenance.missing_images_summary/0
                                          ├─ Library.Completeness.missing_metadata_count/0  (new)
                                          ├─ Library.Completeness.incomplete_season_count/0 (new)
                                          └─ Storage.measure_all/0 + AbsenceSweeper.at_risk_summary/0
                                          ⇒ %MediaCentaur.Status.LibraryOverview{}  (new typed struct)
```

**Module responsibilities (single-purpose):**

- **`MediaCentaur.Status.LibraryOverview`** *(new struct)* — typed view-model
  the Status aggregator returns and the web cards render. Lives in the data
  layer (Status builds it) so web depends on data, not the reverse. Mirrors how
  `SubsystemView` is web-side because `HealthBoard` (web) builds it.
- **`MediaCentaur.Status.fetch_overview/0`** *(new)* — pure cross-context
  composition into `LibraryOverview`. No side effects beyond reads. This finally
  wires `Status` into `StatusLive`, fulfilling its moduledoc'd purpose.
- **`MediaCentaur.Library.Completeness`** *(new, Library-exported)* — gap
  queries that are genuinely Library-domain logic (ADR-029 data-decoupling): the
  domain owns the query; `Status` only aggregates. Functions:
  `missing_metadata_count/0` (library containers lacking a `tmdb`/`tmdb_collection`
  ExternalId), `incomplete_season_count/0` (TV series with ≥1 episode-number gap
  within a season). Gap detection is a pure function
  (`detect_season_gaps/1`) for `async: true` unit testing.
- **`MediaCentaur.Library.FilePresence.total_size_bytes/0`** *(new)* —
  `sum(size)` over presence rows (nil sizes coalesce to 0). Size is FilePresence's
  field, so the aggregate lives with it.

**Web components** (`library_overview_components.ex`), each typed (MC0008) with a
story (MC0009):

- `library_overview/1` — section wrapper laying out the four cards + heading.
- `glance_card/1`, `pending_work_card/1`, `completeness_card/1`,
  `storage_outlook_card/1`.
- Recent-poster strip **reuses the existing `poster_row` component**.

Visual language: daisyUI `card glass-surface` like the activity widgets; color
reserved for health/severity (gap counts use warning hue only when > 0,
neutral at 0); name+icon for identity; eager+sync posters (UIDR-012 / MC0016).

## Async & reactivity

- Overview is computed **off the mount path** via `start_async(:status_overview)`
  (ADR-049 owned async); mount renders empty/loading, `handle_async` fills it in.
  `missing_images_summary/0` does a disk check per image row, so it must never
  run in `mount`.
- **Reactivity:** subscribe to the `library:updates` topic; on
  `{:entities_changed, _}` schedule a single **debounced** refresh
  (`Process.send_after(:refresh_overview, 2_000)` guarded by a pending flag) so a
  bulk import triggers one recompute, not hundreds.
- The existing 5-minute `:refresh_storage` cycle also recomputes the overview as
  cheap insurance.

## Testing (test-first)

- **`Library.Completeness`** — DataCase tests via `create_*` factories:
  missing-metadata counting (with/without ExternalId), season-gap detection
  (contiguous → 0, missing middle/first → counts series once). `detect_season_gaps/1`
  pure unit tests `async: true`.
- **`FilePresence.total_size_bytes/0`** — DataCase: sums sizes, treats nil as 0,
  empty → 0.
- **`Status.fetch_overview/0`** — DataCase: returns a populated
  `LibraryOverview` for a seeded library; empty library → zeroed struct.
- **Pure view-model helpers** (any formatting/severity logic) extracted and
  unit-tested per ADR-030.
- **Page smoke** — extend `page_smoke_test.exs` `/status` fixture so the overview
  renders with real cards (counts, a recent item, a gap > 0), not just empty
  state.

## Out of scope / follow-ups

- Friendly drill-down lists for each gap (the cards link to existing fix
  surfaces; per-item lists can come later).
- Wiki: add the overview to the Status page user doc once the shape settles.
