# Per-Subsystem Log Rings

**Date:** 2026-09-16
**Status:** Design approved, not yet implemented

## Problem

The "Technical logs" disclosure on every Status subsystem drill-in is
effectively always blank.

It renders `HealthBoard.log_lines/1`, which flattens the `sample_entries` of
the subsystem's *open incident buckets* — not log history. Three structural
reasons it shows nothing:

1. A healthy subsystem has no buckets, so there is nothing to flatten. The
   disclosure renders unconditionally (unlike the retention panel beside it),
   so a healthy page always shows an empty section.
2. Incidents with `origin: :subsystem` — the health assessor's verdicts, the
   majority of what reaches these boards — are constructed with
   `sample_entries: []`. Their evidence is the headline. A subsystem can be
   showing errors with the log panel still empty.
3. Only `:log`-origin incidents carry samples (≤5), and those are already
   rendered in the incident detail view's "Recent log lines" section.

So the panel is empty when the subsystem is healthy or its issues are faults,
and redundant when it is neither.

The same starvation exists, less visibly, in the Console drawer: filtering to
one component shows only that component's survivors of a single shared ring.

## Glossary

Three distinct things are called "logs" in this area. They are kept distinct
throughout this document.

- **Log line** — one entry the app emitted, tagged with a **component**
  (`:pipeline`, `:acquisition`, `:tmdb`, …). Built by
  `Console.Entry.from_log_event/3`. Volatile.
- **Incident** — a recurring fault grouped by fingerprint, durable in
  `incidents` / `diagnostic_events`. Warnings and errors only.
- **Subsystem** — the Status board's tile vocabulary (File watching, Media
  import, Metadata, …). *Not* the same list as component tags:
  `HealthBoard.normalize/1` folds `:nostr` into `:social` and everything
  unrecognised into `:system`.

**Component layer** — `Log.Component` already tags each component `:app` or
`:framework`. That split already drives the drawer's default visibility and is
reused here rather than restated.

## Decision

`Console.Buffer` stops being one shared ring and becomes **one capped ring per
component**. Every reader takes a view over that single store.

```
Console.Handler ──> Buffer  %{component => ring}   (200 entries per component)
                      │
                      ├─ snapshot/0, snapshot_window/1  → merge all rings, id desc
                      │                                   → Console drawer
                      └─ recent_for(components, opts)   → merge those rings only
                                                          → Status subsystem panel
                                                          → drawer, component-filtered
```

This is one retention model with two consumers, not a Status feature bolted
onto the Console. Filtering the drawer to `:watcher` gains the same guaranteed
depth the Status panel gets.

### Why not the alternatives

- **Filter the existing shared buffer.** Reproduces the reported bug: a busy
  import evicts every other subsystem's history.
- **Durable per-subsystem log table.** A SQLite write per log line plus a
  retention policy per subsystem — heavy machinery for a diagnostic panel, and
  the in-memory option already gives hours of depth.
- **A separate ring store alongside `Console.Buffer`.** Two rings over one
  event stream means every log line held twice in memory. Rejected in favour
  of one store with per-consumer views.

## Sizing

Measured against the live dev node, 1,109 real entries.

Per-entry cost is `744 B heap + message bytes`. The heap part is near-constant
(93 words) because messages are off-heap refc binaries. Messages are already
truncated at 2,000 chars (`Console.Entry`, `truncate(…, 2_000)`), so an entry
is hard-bounded at ~2,750 B.

Observed averages: `:ecto` 1,319 B (995 entries, all `:debug` SQL);
every other component 764–886 B. The sampled buffer was 89% Ecto debug.

**Cap: 200 entries per component, uniform across app and framework.**

| | entries | memory |
|---|---|---|
| 200/component × 16 components | 3,200 | **2.6 MB** (1.8 MB at observed per-component averages) |
| pathological — every entry at the 2 KB truncation | 3,200 | **8.4 MB** |
| *today: default* | 2,000 | *2.4 MB* |
| *today: max slider* | 50,000 | *60 MB* |
| *today: pathological* | 50,000 | *131 MB* |

Same memory as today's default, with a pathological ceiling 15× lower. No
per-ring byte budget is needed on top of the line cap — the existing 2,000-char
truncation already bounds the worst case at 8.4 MB.

### Time depth

Sustained rates from the same 58-minute sample. Components that logged in
page-load bursts (5 lines in 2s) have a meaningless instantaneous rate and a
near-zero sustained rate.

- `acquisition` — 90 lines/hr → 200 lines ≈ **2.2 hours**. The busiest real
  app component in the sample.
- `ecto` — 1,029 lines/hr → 200 lines ≈ 12 minutes. Framework, hidden by
  default.
- Bursty app components (pipeline, library, watcher, social) sustain near
  zero → 200 lines covers days.

**Known limit:** during a bulk library import `:pipeline` bursts far past
90 lines/hr, and 200 lines is minutes rather than hours — which is exactly when
someone would look. This is still strictly better than today (the shared ring
gives less, and takes every other subsystem with it), but it is not a cure. The
drawer's slider is the lever for that case.

## Components

### `Console.Buffer` — the store

Internals rewrite; the public API keeps its current shape and gains one
function.

- State becomes `%{component => ring}`.
- **Lossless by level.** The store keeps every level it is handed. It is now
  the Console's only source, so a write-time level floor is not available. The
  `:info` floor the Status panel wants is applied at read time.
- **Ring keys are bounded.** `Entry.classify_component/2` lets an explicit
  `meta[:component]` through as an arbitrary atom, so ring count is not
  statically bounded by construction. Rings key on `Log.Component.all()`
  membership, folding anything else to `:system`. Bounds ring count at 16.
- **Ordering is free.** `Entry.from_log_event/3` already stamps
  `id: System.unique_integer([:monotonic, :positive])`, globally monotonic
  across the VM. Merging rings newest-first is a sort by `id` descending.
- New read: `recent_for(components, opts)` where `opts` accepts `:level`
  (floor) and `:limit`. Merges only the named rings.
- `clear/0` clears every ring; `resize/1` resizes every ring.

### `Console.Handler` — unchanged seam

Still one `append/1` call. The handler stays a cheap, crash-free hand-off.
`ErrorReports.LogHandler` remains an independent peer handler; neither path
changes.

### `HealthBoard` — the fold

Gains `components_for(subsystem)`, **derived** by folding
`Log.Component.app()` through the existing `normalize/1` so the two directions
cannot drift.

- Social pulls `:social` + `:nostr`.
- System pulls `:system` + `:review` + `:apps` + `:settings`.
- Framework components (`:phoenix`, `:ecto`, `:live_view`) are excluded, so
  subsystem panels never show framework logs. They stay in the Console drawer
  behind the same opt-in that hides them today.
- **`:self_update` maps to no component.** `Log.Component`'s moduledoc records
  that SelfUpdate's logs were deliberately unified onto `:system`. The Updates
  tile therefore gets no log section, rather than silently reversing that
  decision or showing it unrelated system noise.

`log_lines/1` is deleted along with its tests. Nothing else reads incident
`sample_entries` except the incident detail view, which keeps its own "Recent
log lines" section unchanged.

### The Status panel

- The disclosure renders **only when that subsystem has lines**. That alone
  removes the always-blank complaint; no empty-state copy is added.
- Reads `Console.recent_for(components, level: :info, limit: 200)`. Because the
  store is lossless, the panel reads the whole ring and filters — under debug
  logging a ring is mostly debug and the panel renders whatever info+ survives.
- **The panel's 200-line render cap is its own constant, not the ring cap.** If
  the drawer's slider is raised to 1,000 the rings deepen but the panel still
  renders at most 200 lines, because a disclosure holding 1,000 monospace rows
  is a DOM cost with no reader. The Console drawer is where the full depth is
  read.
- Newest-first, `HH:MM:SS` + message, level colour via the existing
  `Console.View.level_color/1`, in a `max-h` scroll region. No autoscroll.
- A component chip appears **only** on subsystems that fold more than one tag
  (Social, System), where "which part said this" is genuinely ambiguous.
- No level or search controls in the panel — that is the Console drawer's job,
  and status surfaces do not rehash feature surfaces.

### Live updates

`StatusLive` subscribes to the existing `console:logs` topic while a subsystem
drill-in is open. The drill-in is `handle_params`-driven, so that is the
subscribe/unsubscribe point. Each `{:log_entries, _}` batch is filtered to the
open subsystem's components and prepended, holding the assign at the panel's
200-line render cap. Closing the drill-in unsubscribes.

Per-component PubSub topics were considered and rejected: the drill-in is only
open while a human is looking, so filtering one shared topic is the simpler
correct choice.

### The drawer's cap control

`console_components.ex` renders a bare range input, 100–50,000, step 100, with
a naked number label — no text label to rewrite.

Re-ranged to **100–1,000 per component, step 100, default 200**. At the 1,000
maximum that is ~13 MB, still a fifth of today's ceiling, and it is the lever
for the bulk-import case above. The number label gains a unit word so the
per-component meaning is visible.

Persisted values above the new maximum **clamp on read**. No migration layer
(repo policy: remove obsolete paths rather than add compatibility shims).

## Performance

`snapshot/0` sorts up to 3,200 entries by `id` inside the buffer process on
mount, resize, filter change and download. Appends are batched casts, so a
brief block is tolerable — and the sort is over 3,200 terms, not today's
50,000-entry worst case.

Filter changes get **cheaper**. `console_live/shared.ex` currently answers a
filter change with `Logic.visible_entries(Console.snapshot(), filter)` — pull
everything, then discard. Its three `Console.snapshot/0` call sites (resize,
filter change, download payload) switch to `recent_for/2` with the filter's
visible components, so only the selected rings are pulled. `Filter.components`
and `default_component` become the read selector; `visible_entries/2` keeps the
level and search dimensions and loses the component dimension.

## Testing

- `Console.Buffer` tests largely rewrite: per-component eviction, uniform cap,
  merge ordering by `id`, unknown-component folding, `recent_for/2` level floor
  and limit, `clear/0` and `resize/1` across rings.
- `HealthBoard.components_for/1`: the app-only derivation, the Social and
  System folds, and `:self_update` returning no components.
- `health_drill_in.story.exs` gains variations for the new panel states — lines
  present, no lines (section absent), and a multi-component fold showing chips
  — in the same commit, per MC0009.
- `status_live_test.exs`: subscribe on drill-in open, a broadcast batch
  appending only matching components, unsubscribe on close.

## Out of scope

- **An "Open in Console filtered to this subsystem" link.** The console drawer
  has no cross-page filter-preset mechanism; building one is separate work.
- **Giving `:self_update` its own component tag.** That reverses a deliberate
  decision recorded in `Log.Component`; it belongs in its own change if wanted.
- **Any durable log storage.** Explicitly in-memory.
