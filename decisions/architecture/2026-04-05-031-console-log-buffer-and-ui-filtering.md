---
status: accepted
date: 2026-04-05
---
# In-memory log buffer and UI-driven filtering for the Guake-style console

## Context and Problem Statement

The existing `MediaCentarr.Log` module gates info-level component logs at the
Erlang primary filter based on a `MapSet` in `:persistent_term`. This makes
enabled components truly zero-cost when disabled, but makes log visibility
opaque: filter state lives in memory only, requires IEx or a settings-page
toggle to change, and historical log entries from disabled components are
permanently lost — they never reach any handler.

Operators need a browser-native way to tail logs with live filtering without
switching terminals or SSHing into a remote shell. When diagnosing pipeline
runs, TMDB matching, or watcher behavior, context is lost every time the user
switches to `journalctl` or a separate terminal.

## Decision Outcome

Chosen option: "In-memory ring buffer with UI-driven filtering", because it
captures all logs without new infrastructure, exposes filter state from the
browser, and keeps the `Log` macro API unchanged at all call sites.

### Design

Install a `:logger` handler (`MediaCentarr.Console.Handler`) that captures all
log events into a GenServer-backed ring buffer (`MediaCentarr.Console.Buffer`,
default 2,000 entries, configurable up to 50,000). Expose the buffer via a
sticky LiveView drawer present on every page and a full-page `/console` route.
Persist user filter state and buffer size to `Settings.Entry` with debounced
writes.

The Erlang primary filter is removed entirely; filter semantics move to the
console UI. Framework log suppression (`Logger.put_module_level/2`) is also
removed — framework logs become filterable pseudo-components (`:phoenix`,
`:ecto`, `:live_view`) in the same console filter.

The `MediaCentarr.Log` module shrinks to only the `info/2`, `warning/2`, and
`error/2` macros — the primary filter management helpers are gone.

### Rules

1. **`MediaCentarr.Console` is the public facade.** LiveViews and other callers
   interact with the console only through `MediaCentarr.Console` public
   functions — never directly with `Buffer` or `Handler` (per ADR-026 GenServer
   API encapsulation).
2. **Filter state is server-side.** The active component filter and level filter
   are stored in LiveView assigns and persisted to `Settings.Entry`. Client-side
   text search (the search input) is a pure client filter layered on top.
3. **Cross-context rescan:** `Console.rescan_library/0` dispatches to
   `MediaCentarr.Watcher.Supervisor.scan/0` via `Task.Supervisor`. This is a
   direct public-function call, consistent with existing cross-context patterns
   (ADR-029 allows consumer modules to call Library and Watcher directly).
4. **Buffer size is configurable at runtime.** Users can adjust the cap (1,000
   to 50,000) from the console UI. The setting is persisted and applied on the
   next buffer trim cycle.

### Consequences

* Good, because all logs are captured and filterable from the browser — no
  terminal or SSH access needed for routine diagnosis
* Good, because filter state is persistent across page navigation and restart
* Good, because the closed-loop feedback loop is natural: the rescan button
  emits pipeline and watcher logs that appear inline in the console
* Good, because `MediaCentarr.Log` surface area drops from ~290 lines to ~50 —
  the primary filter management helpers, component enable/disable helpers, and
  `:persistent_term` logic are all removed
* Good, because framework logs (Ecto, Phoenix, LiveView) are available on-demand
  via filterable chips rather than permanently suppressed
* Bad, because every info log now allocates an `Entry` struct, even when the
  component chip is hidden in the UI. At ~100 logs/sec this is ~30 KB/sec of
  short-lived garbage — trivially collected, but a non-zero cost versus the
  previous zero-cost primary filter
* Bad, because buffer state is lost on BEAM restart. The default `:logger`
  handler still writes to stdout, so journald and terminal history remain
  available for crash forensics
* Bad, because the sticky LiveView drawer adds a persistent process per
  connected browser. In a single-user household deployment this is negligible
* Neutral, because the `mix phx.server` terminal now shows framework-level info
  logs (Ecto queries, Phoenix request logs) that were previously silenced.
  Terminal users can filter via journalctl; the browser console is the intended
  primary viewer
* Neutral, because existing `Log.info/warning/error` call sites are unchanged —
  the macro API is identical; only the capture and filtering mechanism moved
