# Per-Subsystem Log Rings, and Retiring the Console Drawer

**Date:** 2026-09-16
**Status:** Design approved, not yet implemented

## Problem

The "Technical logs" disclosure on every Status subsystem drill-in is
effectively always blank.

It renders `HealthBoard.log_lines/1`, which flattens the `sample_entries` of
the subsystem's *open incident buckets* — not log history. Three structural
reasons it shows nothing:

1. A healthy subsystem has no buckets. The disclosure renders unconditionally
   (unlike the retention panel beside it), so a healthy page always shows an
   empty section.
2. Incidents with `origin: :subsystem` — the health assessor's verdicts, the
   majority of what reaches these boards — are constructed with
   `sample_entries: []`. A subsystem can be showing errors with the log panel
   still empty.
3. Only `:log`-origin incidents carry samples (≤5), and those already render in
   the incident detail view's "Recent log lines" section.

The same starvation exists, less visibly, in the console: filtering to one
component shows only that component's survivors of a single shared ring.

Separately, the tilde-key console drawer is being retired.

## Glossary

Three distinct things are called "logs" here, kept distinct throughout.

- **Log line** — one entry the app emitted, tagged with a **component**
  (`:pipeline`, `:acquisition`, `:tmdb`, …). Built by
  `Console.Entry.from_log_event/3`. Volatile.
- **Incident** — a recurring fault grouped by fingerprint, durable in
  `incidents` / `diagnostic_events`. Warnings and errors only.
- **Subsystem** — the Status board's tile vocabulary (File watching, Media
  import, Metadata, …). *Not* the same list as component tags:
  `HealthBoard.normalize/1` folds `:nostr` into `:social` and everything
  unrecognised into `:system`.
- **Component layer** — `Log.Component` tags each component `:app` or
  `:framework`. That split already drives default visibility and is reused
  here rather than restated.
- **Journal** — raw `journalctl --user -u <unit> -f` text from the systemd
  unit. A separate log *source*: external process, no component tags, no
  parsed levels, timestamps baked into the message text.

## Core idea

> **A log surface is a selection over the log stream.** The store answers
> selections; every surface is one selection plus a renderer.

After this change there are two selections over the ring store — the
`/console` page (user-chosen) and the Status subsystem panel (fixed by the
subsystem) — plus one separate source, the journal, on Status → System.

## Scope

**Removed:** the tilde-key console drawer (`ConsoleLive`, its sticky mount in
`layouts.ex:286`, the `` ` `` binding).

**Kept:** `/console` (`ConsolePageLive`) with full filtering, all levels, all
components.

**Moved:** the journal tail, from a tab on the console to the Status System
subsystem drill-in.

**Added:** a real log panel on every Status subsystem drill-in.

## Decision

`Console.Buffer` stops being one shared ring and becomes **one capped ring per
component**, 200 entries each. Both readers take a view over that single store.

```
Console.Handler ──> Buffer  %{component => ring}   (200 per component, all levels)
                      │
                      ├─ read(%Filter{}, limit)  → merge selected rings, id desc
                      │     ├─ /console page      (user's persisted Filter)
                      │     └─ Status panel       (subsystem's components, level: :info)
                      └─ config()  → %{cap, filter}

JournalSource ──────────────────────────────────> Status → System journal panel
```

One retention model with two consumers, not a Status feature bolted onto the
console. Filtering `/console` to `:watcher` gains the same guaranteed depth the
Status panel gets.

### Why not the alternatives

- **Filter the existing shared buffer.** Reproduces the reported bug: a busy
  import evicts every other subsystem's history.
- **Durable per-subsystem log table.** A SQLite write per log line plus a
  retention policy per subsystem — heavy machinery for a diagnostic panel, and
  the in-memory option already gives hours to days of depth.
- **A separate ring store alongside `Console.Buffer`.** Two rings over one
  event stream means every log line held twice in memory.
- **Per-*subsystem* rings with a write-time fold.** Simpler (no merge on read),
  but it needs the board's subsystem vocabulary in the domain layer, and
  `/console` filters by component. Rejected because `/console` survives.

## Sizing

Measured against the live dev node, 1,109 real entries.

Per-entry cost is `744 B heap + message bytes`. The heap part is near-constant
(93 words) because messages are off-heap refc binaries. Messages are already
truncated at 2,000 chars (`Console.Entry`, `truncate(…, 2_000)`), so an entry
is hard-bounded at ~2,750 B.

Observed averages: `:ecto` 1,319 B (995 entries, all `:debug` SQL); every other
component 764–886 B. The sampled buffer was 89% Ecto debug.

**Cap: 200 entries per component, uniform across app and framework.**

| | entries | memory |
|---|---|---|
| 200/component × 16 | 3,200 | **2.6 MB** (1.8 MB at observed per-component averages) |
| pathological — every entry at the 2 KB truncation | 3,200 | **8.4 MB** |
| *today: default* | 2,000 | *2.4 MB* |
| *today: max slider* | 50,000 | *60 MB* |
| *today: pathological* | 50,000 | *131 MB* |

Same memory as today's default, with a pathological ceiling 15× lower. No
per-ring byte budget is needed on top of the line cap — the existing 2,000-char
truncation already bounds the worst case at 8.4 MB.

### Time depth

Sustained rates from a 58-minute sample. Components that logged in page-load
bursts (5 lines in 2s) have a meaningless instantaneous rate and a near-zero
sustained rate.

- `acquisition` — 90 lines/hr → 200 lines ≈ **2.2 hours**. The busiest real app
  component in the sample.
- `ecto` — 1,029 lines/hr → 200 lines ≈ 12 minutes. Framework; never reaches a
  Status panel (see `components_for/1`), and `/console` is where it is read.
- Bursty app components (pipeline, library, watcher, social) sustain near zero
  → 200 lines covers days.

**Known limit:** during a bulk library import `:pipeline` bursts far past
90 lines/hr, and 200 lines is minutes rather than hours — exactly when someone
would look. Still strictly better than today (the shared ring gives less and
takes every other subsystem with it), but not a cure. `/console` with a raised
cap is the lever for that case.

## Components

### `Console.Buffer` — the store

Internals rewrite. The read API collapses from four shapes to two.

- State becomes `%{component => ring}`.
- **Lossless by level.** The store keeps every level it is handed; `/console`
  reads `:debug`. The `:info` floor the Status panel wants is applied at read
  time, not write time.
- **Ring keys are bounded.** `Entry.classify_component/2` lets an explicit
  `meta[:component]` through as an arbitrary atom, so ring count is not
  statically bounded by construction. Rings key on `Log.Component.all()`
  membership, folding anything else to `:system`. Bounds ring count at 16.
- **Ordering is free.** `Entry.from_log_event/3` already stamps
  `id: System.unique_integer([:monotonic, :positive])`, globally monotonic
  across the VM. Merging rings newest-first is a sort by `id` descending.
- **The amortized trim must survive.** The current buffer trims once per
  `cap/4` appends rather than per-append — an audit fix (P8) against walking
  the full list on every log line. A naive per-ring rewrite drops it. It has to
  survive, per ring.

**Read API.**

```elixir
read(%Filter{}, limit) :: [Entry.t()]   # the ONE read
config() :: %{cap: pos_integer(), filter: Filter.t()}
```

`read/2` applies the filter's component and level dimensions as a **read
selector** — only the selected rings are pulled. Search stays a read-time
concern at the call site (it is per-keystroke and client-hooked).

This replaces `snapshot/0`, `snapshot_window/1` and `recent/0,1`. `snapshot/0`
bundled `entries + cap + filter` only because mount wanted one call — a
call-site convenience that hardened into an API shape.

`clear/0` clears every ring; `resize/1` resizes every ring.

### `Console.Filter` — the selection type

Unchanged, and used as-is. It already expresses exactly a selection over log
lines — level floor, per-component visibility, search — with `matches?/2` and
`from_persistable/1`. The Status panel constructs one rather than inventing a
parallel selection vocabulary:

```elixir
Filter.new(
  components: Map.new(components, &{&1, :show}),
  default_component: :hide,
  level: :info
)
```

Which means the panel's live-update path reuses `Logic.should_insert_entry?/3`
verbatim.

### `Console.Handler` — unchanged seam

Still one `append/1` call; still cheap and crash-free.
`ErrorReports.LogHandler` remains an independent peer handler. Neither path
changes.

### The cap setting

`console_components.ex` renders a bare range input, 100–50,000, step 100, with
a naked number label — no text label to rewrite.

Re-ranged to **100–1,000 per component, step 100, default 200**. At the 1,000
maximum that is ~13 MB, still a fifth of today's ceiling, and it is the lever
for the bulk-import case above. The number label gains a unit word so the
per-component meaning is visible.

**New settings key `console_lines_per_component`; `console_buffer_size` is
deleted.** The old key means "total lines"; keeping it while changing its
meaning is one key meaning two things across versions. Note that
`load_settings` does *not* clamp out-of-range values — it resets them to the
default (`buffer.ex:323-330`) — so a stale value would silently become the new
default rather than a proportional one. A new key makes the change explicit.
No compatibility shim (repo policy: remove obsolete paths).

### `HealthBoard` — the fold

Gains `components_for(subsystem)`, **derived** by folding `Log.Component.app()`
through the existing `normalize/1` so the two directions cannot drift.

- Social pulls `:social` + `:nostr`.
- System pulls `:system` + `:review` + `:apps` + `:settings`.
- Framework components (`:phoenix`, `:ecto`, `:live_view`) are excluded, so
  subsystem panels never show framework logs. They stay on `/console` behind
  the same opt-in that hides them today.
- **`:self_update` maps to no component.** `Log.Component`'s moduledoc records
  that SelfUpdate's logs were deliberately unified onto `:system`. The Updates
  tile therefore gets no log section. This is a *declared hole*, asserted by a
  test (`components_for(:self_update) == []`), not an accident.

`log_lines/1` is deleted with its tests. Nothing else reads incident
`sample_entries` except the incident detail view, which keeps its own "Recent
log lines" section unchanged.

### `log_line/1` — one row renderer

`log_list/1` (`console_components.ex:120`) currently fuses a container
(`phx-update="stream"`, `phx-hook="LogTail"`) with a row (timestamp, component
badge, message, `data-message` for client search). The row is extracted as
`log_line/1`; `/console` wraps it in the stream container, the Status panel
renders it flat. Collapses the duplication at the moment it would be created.

### The Status subsystem panel

- Renders **only when that subsystem has lines**. That alone removes the
  always-blank complaint; no empty-state copy is added.
- Reads `Console.read(filter, 200)` with the subsystem filter above.
- **The panel's 200-line render cap is its own constant, not the ring cap.** If
  the cap slider is raised to 1,000 the rings deepen but the panel still
  renders at most 200 lines, because a disclosure holding 1,000 monospace rows
  is a DOM cost with no reader. `/console` is where full depth is read.
- Newest-first, `max-h` scroll region, no autoscroll.
- A component chip appears **only** on subsystems that fold more than one tag
  (Social, System), where "which part said this" is genuinely ambiguous.
- No level or search controls — that is `/console`'s job, and status surfaces
  do not rehash feature surfaces.

### Live updates

`StatusLive` subscribes to the existing `console:logs` topic while a subsystem
drill-in is open. The drill-in is `handle_params`-driven, so that is the
subscribe/unsubscribe point. Each `{:log_entries, _}` batch is filtered with
`Logic.should_insert_entry?/3` against the panel's filter and prepended,
holding the assign at the 200-line render cap. Closing the drill-in
unsubscribes.

Per-component PubSub topics were considered and rejected: the drill-in is only
open while a human is looking, so filtering one shared topic is the simpler
correct choice.

### Removing the drawer

- `console_live.ex` (68 lines), the sticky `live_render` in `layouts.ex:286`,
  the `` ` `` binding, and `console_live_test.exs` are deleted.
- **`console_live/shared.ex` (281 lines) is deleted, not kept.** It is a
  `__using__` macro whose only purpose is sharing mount/handle_info/handle_event
  between the drawer and the page. With one consumer it is indirection wrapping
  no duplication. It inlines into `ConsolePageLive`, which becomes an ordinary
  LiveView instead of a 50-line shell over a macro. `Logic` (pure functions)
  stays as its own module.
- The memory-noted constraint "Console is deliberately outside the input
  system" narrows to `/console` as an ordinary page. **No nav work is done
  here** — the surface is still in design flux.

### Relocating the journal

The journal is not a second copy of the ring panel. The ring holds structured,
subsystem-scoped entries that start empty at boot; the journal holds raw
whole-process text that **survives restarts and contains what killed the VM**.
It is the only source for "what happened before this VM started", so it is
complementary, and it is labelled as the service's systemd journal rather than
as more subsystem logs.

- It lands on the Status **System** subsystem drill-in, below that subsystem's
  own ring panel.
- **Subscribe on expand, not on drill-in open.** `JournalSource` refcounts
  subscribers and only spawns `journalctl -f` while someone is watching;
  subscribing merely because the System tile was opened would spawn a process
  for a passer-by. Collapsing the disclosure, or leaving the drill-in,
  unsubscribes.
- `journal_available?/0` returns `{:error, :no_unit_detected}` with no systemd
  unit (a bare `mix phx.server`, or non-Linux). The panel renders only when a
  unit exists — the same "render only when there's something" rule as the ring
  panel.
- On `/console`, `source_tabs/1`, `journal_list/1`, the `active_source` assign
  and the journal stream handlers are deleted. One source each: `/console` is
  the app's own log stream, Status → System is the OS journal. No tabs on
  either.

## Performance

`read/2` sorts only the selected rings' entries by `id`. The whole-store case
is ≤3,200 entries, against today's 50,000-entry worst case.

Filter changes get **cheaper**. `console_live/shared.ex` currently answers a
filter change with `Logic.visible_entries(Console.snapshot(), filter)` — pull
everything, then discard. Its `Console.snapshot/0` call sites (resize, filter
change, download payload) become `read/2` with the filter, so only the selected
rings are pulled. `visible_entries/2` keeps the search dimension and loses the
component and level dimensions to the read selector.

## Testing

- `Console.Buffer`: per-component eviction, uniform cap, merge ordering by
  `id`, unknown-component folding, `read/2` component and level selection,
  amortized trim behaviour, `clear/0` and `resize/1` across rings.
- `HealthBoard.components_for/1`: the app-only derivation, the Social and
  System folds, and `components_for(:self_update) == []`.
- `health_drill_in.story.exs` gains variations for the new panel states — lines
  present, no lines (section absent), and a multi-component fold showing chips
  — in the same commit, per MC0009. `log_line/1` gets its own story.
- `status_live_test.exs`: subscribe on drill-in open, a broadcast batch
  appending only matching components, unsubscribe on close; journal
  subscribe-on-expand and unsubscribe-on-collapse.
- `console_page_live_test.exs` absorbs the drawer's coverage where it was
  testing shared behaviour; `console_live_test.exs` is deleted.

## Documentation

The console drawer is described as *the* way to read logs in several places,
all of which change:

- `CLAUDE.md` — "Observability for Debugging" section.
- `docs/architecture.md`, `docs/GLOSSARY.md`.
- The `troubleshoot` skill.
- Wiki: `Keyboard-Shortcuts.md` / `Keyboard-and-Gamepad.md` (the `` ` ``
  binding), `Troubleshooting.md`.

## Scheduled convergence

**`Retention` ↔ `HealthBoard` subsystem vocabulary.**
`Retention.Policy.subsystem` is a domain field whose moduledoc constrains it to
"one of the Status-page health-board subsystem keys" — a domain context
constrained by a web module, enforced by prose alone. `ErrorReports` likewise
groups by component and relies on `HealthBoard.normalize/1` at display time.

The right shape is a domain module owning which subsystems exist and which log
components fold into each, with the web layer keeping labels, glyphs,
descriptions and tile order.

This work does **not** force it: with per-component rings the fold stays at
read time in the web layer where it already lives. Recorded here rather than
fixed, with a named trigger — **the next time a third context needs the
subsystem vocabulary**, it gets promoted to the domain and `Retention`'s prose
constraint becomes a code reference.

## Out of scope

- **Giving `:self_update` its own component tag.** That reverses a deliberate
  decision recorded in `Log.Component`; it belongs in its own change.
- **Any durable log storage.** Explicitly in-memory.
- **Input-system / nav coverage for `/console`.** The surface is in design
  flux; mouse-only stands.

## Optional, droppable

**A URL-param filter preset on `/console`** (`/console?components=watcher`),
parsed into a `Filter`. Nearly free now that `read/2` takes a filter, and it
gives the Status panel a natural "see everything for this subsystem"
escalation. The panel works without it.
