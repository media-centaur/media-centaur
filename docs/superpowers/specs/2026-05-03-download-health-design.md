# Download Health Classifier — Design

**Date:** 2026-05-03
**Status:** Approved (skipping user-review gate per explicit instruction)

## Problem

`MediaCentarr.Acquisition.QueueItem` already carries a normalized `state` atom (`:downloading | :queued | :stalled | :paused | :completed | :error | :other`). The existing `:stalled` is whatever the qBittorrent client itself reports (`stalledDL` — no peers). A torrent that the client *thinks* is downloading but is actually crawling at 50 KB/s looks identical in the UI to one running at 80 MB/s — both render as a blue "Downloading" badge with a progress bar.

We want to classify the *quality* of an active download by observed throughput over a rolling window, plus a few related "stuck" cases (metadata fetch hung, queued for too long), and surface degraded items in the UI.

## Scope

In scope:

- Throughput tracking per torrent ID over a 1-hour rolling window.
- A pure classifier returning one of: `:healthy | :warming_up | :slow | :soft_stall | :frozen | :meta_stuck | :queued_long`.
- Surfacing on the Downloads page (`/downloads`) and a softer escalation on Upcoming cards.
- A predicate API (`Acquisition.Health.degraded?/1`) that future automation can read.

Out of scope (deliberate):

- Auto-cancel / retry-with-next-release automation.
- Any change to `AutoGrabPolicy`.
- Configuration knobs (hardcoded constants for v1, with a comment so future-us knows where to lift them).
- Persisting health history across server restarts (warm-up after restart is acceptable).
- Property tests, Playwright/E2E (the indicator is passive — no new user actions).

## The case taxonomy

| # | Case | Detection | Downloads-page text | Upcoming tooltip | Badge variant |
|---|---|---|---|---|---|
| 1 | Healthy | `:downloading`, throughput ≥ 500 MB/hr | (none) | (none) | — |
| 2 | Warming up | `:downloading`, observed for < 2 min | "Starting…" | "Starting" | — |
| 3 | Slow | `:downloading`, 100–500 MB downloaded in last 1 hr | "Slow — under 500 MB in past hour" | (none — too noisy on cards) | ghost |
| 4 | Soft-stall | `:downloading`, < 100 MB downloaded in last 1 hr | "Less than 100 MB in past hour" | "Stuck" | warning |
| 5 | Frozen | `:downloading`, **0 bytes** in last 10 min | "No progress in 10 minutes" | "Stuck" | warning |
| 6 | Metadata stuck | qBit raw status `metaDL` for ≥ 5 min | "Fetching metadata for over 5 min — magnet may be dead" | "Magnet stuck" | warning |
| 7 | Queued long | `:queued` for ≥ 30 min | "Queued for over 30 minutes" | (none) | ghost |

The existing hard-stall (`:stalled`), `:paused`, `:error`, and `:completed` states keep their current presentation — `Health.classify/3` returns `nil` for them.

### Edge cases

| Situation | Behaviour |
|---|---|
| `size_left` increases poll-to-poll (qBit recheck or file replacement) | Reset history for that ID — start the warm-up window over. |
| Item disappears from queue between polls | Drop history for that ID. If it reappears it's a new entry from our point of view; warm-up restarts. |
| First snapshot after server restart | History empty → all items show `:warming_up` for 2 min. Acceptable. |
| Snapshot gap (offline-mode polls every 30 s, then back to 1 s) | Sparser samples; classification still correct because we compute "delta over a window," not "samples per second." |
| `size_left` is `nil` | No sample appended; classification returns `nil` (no signal). |
| `delta_10min` not computable but `delta_1hr` is (item ~30 min old) | Skip frozen check; still evaluate soft-stall / slow / healthy on 1-hour delta. |
| Both deltas computable, `delta_10min == 0` but `delta_1hr` is huge | `:frozen` (10-min check fires first — recent freeze trumps historical health). |

## Architecture

One new pure module, one mutation to an existing GenServer, one new field on an existing struct. **No new processes, no DB tables, no config keys, no new PubSub topics.**

```
QueueMonitor (existing)                    Acquisition.Health (new, pure)
─────────────────────                      ────────────────────────────
state.history :: %{                        classify(item, history, now)
  torrent_id => [                            → :healthy | :warming_up
    {monotonic_us, size_left},               | :slow | :soft_stall
    ...                                      | :frozen | :meta_stuck
  ]                                          | :queued_long | nil
}                                          
                                           label(status) → "Less than 100 MB in past hour"
poll_and_broadcast/0:                      short_label(status) → "Stuck"
  1. fetch raw items                       badge_variant(status) → "warning" | "ghost" | nil
  2. update history (drop missing,         degraded?(status) → boolean
     reset on backwards motion,            slow?(status) → boolean
     truncate > 1h)
  3. attach health to each item
  4. cache + broadcast enriched items
```

**Why inside `QueueMonitor` and not a new GenServer:** `QueueMonitor` already polls on the only cadence that matters, already has the snapshot, already runs in a single supervised process. A separate `HealthTracker` would either need its own poll loop (duplication) or read from `:persistent_term` (lag, second source of truth). The history map is bounded by active-torrent count × samples-per-window — trivial RAM.

**Why a pure classifier:** stateless, trivially unit-testable with synthetic histories. The same function powers the UI today and `AutoGrabPolicy` later — no rework when automation arrives.

**New field on `QueueItem`:** `health :: Acquisition.Health.status() | nil`. Populated by `QueueMonitor` after each poll. UI is dumb — reads `item.health`. Drivers (`from_qbittorrent/1`) leave it `nil`; only the monitor sets it.

## Data model

### History entry

```elixir
# In QueueMonitor state
%{
  subscribers: %{},          # existing
  history: %{                 # new
    "abc123hash" => [
      {monotonic_us, size_left_bytes},  # newest first
      ...
    ]
  }
}
```

- **Key:** `item.id` (qBittorrent's hash — stable across restarts of qBit and of us).
- **Value:** list of `{System.monotonic_time(:microsecond), size_left}` tuples, **newest first**. Monotonic time so clock changes don't break us.
- **Bounded:** truncate entries older than `@max_window_us` (1 hour) on every insert. At 1 s cadence: ≤ 3 600 samples per torrent; 10 active torrents ≈ 36 000 small tuples — trivial RAM.

### Per-poll algorithm

```
now = monotonic_time(:microsecond)
{:ok, items} ← Acquisition.list_downloads(:all)
active = items |> reject(&(&1.state == :completed))

history' = history
  |> drop_keys_not_in(active)
  |> Enum.reduce(active, fn item, h ->
       prev = h[item.id]
       cond do
         is_nil(item.size_left)         -> h                                     # no signal
         backwards_motion?(prev, item)  -> Map.put(h, item.id, [{now, item.size_left}])  # recheck → reset
         true                           -> push_sample(h, item.id, now, item.size_left)
       end
     end)

active' = Enum.map(active, &attach_health(&1, history'[&1.id], now))
```

`backwards_motion?` is true when the newest existing sample's `size_left` is *less than* the new `size_left`. (qBit recheck restored bytes we'd already counted as downloaded; can't reason about throughput across that boundary.)

## Classifier rules (canonical)

```elixir
@warmup_us       2 * 60 * 1_000_000        # 2 min
@frozen_us      10 * 60 * 1_000_000        # 10 min
@hour_us        60 * 60 * 1_000_000        # 1 hour
@meta_stuck_us   5 * 60 * 1_000_000        # 5 min
@queued_long_us 30 * 60 * 1_000_000        # 30 min

@soft_stall_bytes 100 * 1024 * 1024        # 100 MB
@slow_bytes       500 * 1024 * 1024        # 500 MB
```

**Decision order** (first match wins):

```
classify(item, history, now):

  # — non-throughput cases —
  state == :queued
    age_in_state ≥ 30 min   → :queued_long
    else                    → nil

  raw status == "metaDL"
    age_in_state ≥ 5 min    → :meta_stuck
    else                    → :warming_up

  state != :downloading     → nil   # :stalled, :paused, :error keep their own UI

  # — throughput cases (state == :downloading) —
  size_left is nil          → nil
  oldest_sample_age < 2 min → :warming_up

  delta_10min == 0          → :frozen
  delta_1hr  < 100 MB       → :soft_stall
  delta_1hr  < 500 MB       → :slow
  else                      → :healthy
```

`age_in_state` for `:queued_long` and `:meta_stuck`: derived from the oldest history sample's timestamp. We reset history on backwards motion and on reappearance, so "this item has been in our snapshot for ≥ 30 min" is a sound proxy for "queued ≥ 30 min."

`delta_window(history, window_us)`: find newest sample (`size_left_now`) and the newest sample older than `now - window_us` (`size_left_then`). Return `size_left_then - size_left_now`. If no sample is old enough to span the window, return `nil` and skip that comparison.

## UI surfacing

### Downloads page (`acquisition_live.ex`)

When `health` is non-nil and non-`:healthy`, render a **secondary line** below the title in the colour matching `badge_variant`:

```
[Downloading]   18h 7m            Sample.Show.S01E02.1080p.WEB-DL.mkv
                                  Less than 100 MB in past hour          ← new
                                  ▓▓░░░░░░░░░░░░░  12.4%
```

Secondary text, not a second badge — `state` already owns the badge slot, and a degraded `:downloading` is still `:downloading`.

**Sort order tweak in `acquisition_live/logic.ex`:** within `:downloading`, items with `health ∈ {:soft_stall, :frozen, :meta_stuck}` sort first, then `:slow`, then everything else by ETA. Stuck items bubble to the top.

### Upcoming cards (`upcoming_cards.ex`)

Cards show a tiny status icon per release. When the queue item is `{:soft_stall, :frozen, :meta_stuck}`, the existing `:downloading` icon gets:

- `warning` colour tint (instead of `info`)
- tooltip showing the `short_label` ("Stuck", "Magnet stuck")

`:slow` and `:queued_long` produce **no visual change** on upcoming cards — too dense a surface. Triage of slow items happens on `/downloads`.

`:warming_up` and `:healthy` look identical to today.

### Re-render cadence

Already handled — `QueueMonitor` broadcasts `{:queue_snapshot, items}` every 1 s when watched. Items now carry `health`. Existing subscribers re-render automatically.

## Public API

### `MediaCentarr.Acquisition.Health` (new)

```elixir
@type status :: :healthy | :warming_up | :slow | :soft_stall
              | :frozen | :meta_stuck | :queued_long

@spec classify(QueueItem.t(), [{integer(), non_neg_integer()}], integer()) :: status() | nil
@spec label(status()) :: String.t()
@spec short_label(status()) :: String.t()
@spec badge_variant(status()) :: String.t() | nil
@spec degraded?(status() | nil) :: boolean()    # :soft_stall | :frozen | :meta_stuck
@spec slow?(status() | nil) :: boolean()        # :slow
```

`degraded?/1` is the function `AutoGrabPolicy` will call in a future automation slice. Defining the predicate now — even though nothing calls it in v1 — is what makes this slice "informational, but actions can ride on top later."

### `MediaCentarr.Acquisition.QueueItem` (existing — one new field)

```elixir
defstruct [
  ...,
  :health   # Acquisition.Health.status() | nil — populated by QueueMonitor only
]
```

`from_qbittorrent/1` leaves it `nil`. Drivers translate; only the monitor classifies (it's the only thing with history).

### `MediaCentarr.Acquisition` (existing facade — no changes)

`Acquisition.list_downloads/1` and `Acquisition.queue_snapshot/0` keep their shapes. Items carry the new field.

## Testing

### 6a. `Acquisition.HealthTest` — pure classifier (the bulk)

Table-driven — one test per row of the decision tree. No GenServer, no time travel, no stubs.

| State | History shape | Expected |
|---|---|---|
| `:downloading`, `size_left=nil` | (any) | `nil` |
| `:downloading` | empty | `:warming_up` |
| `:downloading` | one sample, 90 s old | `:warming_up` |
| `:downloading` | spans 1 hr, delta = 0 / 10 min | `:frozen` |
| `:downloading` | spans 1 hr, delta = 50 MB / hr | `:soft_stall` |
| `:downloading` | spans 1 hr, delta = 300 MB / hr | `:slow` |
| `:downloading` | spans 1 hr, delta = 2 GB / hr | `:healthy` |
| `:downloading` | 30 min old, delta_10min=0 | `:frozen` |
| `:downloading` | 30 min old, delta_10min > 0, delta_30min = 40 MB | `:warming_up` (no full-window data) |
| raw status `"metaDL"` | < 5 min | `:warming_up` |
| raw status `"metaDL"` | ≥ 5 min | `:meta_stuck` |
| `:queued` | < 30 min | `nil` |
| `:queued` | ≥ 30 min | `:queued_long` |
| `:stalled`, `:paused`, `:error`, `:completed` | (any) | `nil` |

Plus `label/1`, `short_label/1`, `badge_variant/1`, `degraded?/1`, `slow?/1` round-trip tests for every variant.

### 6b. `QueueMonitorTest` — history bookkeeping

Stub the download client (follow existing `download_client/dispatcher.ex` test patterns) and drive the monitor through scripted snapshot sequences:

- Item appears in poll 1, present in poll 2 → history has 2 samples.
- Item disappears in poll 3 → history no longer contains the ID.
- Item's `size_left` increases poll-to-poll → history reset to a single new sample.
- `size_left = nil` in a poll → no sample appended; existing history preserved.
- Items beyond 1 hour old → truncated on next insert.
- Item flips to `:completed` → filtered before classification (regression guard).

Time control: pass an injectable `now_fn` to `poll_and_broadcast/0`, or peek history via `:sys.get_state/1` test-only path. Existing `cadence_ms/2` is already extracted as a pure function — follow that pattern.

### 6c. LiveView render — UI surfacing

Two LiveView smoke tests:

1. **Downloads page**: render with a fixture queue containing one `:soft_stall` item. Assert "Less than 100 MB in past hour" text appears below the title with `warning` colour. Assert a `:healthy` item shows no secondary line.
2. **Upcoming cards**: render a card whose underlying queue item is `:soft_stall`. Assert tooltip text is "Stuck" and icon class includes warning tint. Assert `:slow` produces no visual change vs `:healthy`.

Both tests build queue items directly with `health` set — they don't go through the monitor.

### Test-first ordering

1. `HealthTest` table → `Health` module
2. `QueueItem` `:health` field test → struct change
3. `QueueMonitorTest` history bookkeeping → monitor changes
4. LiveView render assertions → UI changes
5. `mix precommit` — must end zero-warning

## Defaults summary

| Constant | Value | Rationale |
|---|---|---|
| Warm-up window | 2 min | Avoid classifying brand-new torrents |
| Frozen window | 10 min, 0 bytes | Tight — only flag truly motionless |
| Soft-stall threshold | 100 MB / 1 hr (~28 KB/s avg) | Matches the user's stated example |
| Slow threshold | 500 MB / 1 hr (~140 KB/s avg) | Conservative — never flags healthy cable/fiber downloads |
| Metadata stuck | 5 min | Magnets usually resolve in seconds |
| Queued long | 30 min | qBit's queue normally cycles within minutes |

All constants are module attributes in `Acquisition.Health` with a comment marking them as the "future config knob" surface if/when needed.
