# Pursuit Detail Page — Redesign

**Date:** 2026-05-11
**Status:** Approved — moving to implementation plan

## Problem

`/download/:pursuit_id` (`MediaCentarrWeb.PursuitLive`) tells the user nothing about *what is actually happening* to a pursuit. It shows static counters (`Attempts: 0`, `Tried releases: 0`, `Origin: manual`, `Started: …`), a state badge, and a timeline. The only available action is **Cancel pursuit**.

Concrete example that triggered this work: a manually-grabbed pursuit sat at `Active` for two days with no downstream events. The page could not answer:

- Is a file downloading right now?
- If not, why not?
- What will happen next?
- Is anything wrong?

The page must answer those three questions at a glance, while keeping the historical event log accessible. New manual triggers (re-search, request decision) close the loop when the user can see something's wrong.

## Goals

1. The page shows **what is happening right now**, not aggregated counters.
2. The page tells the user **what will happen next automatically** (or that nothing will).
3. The page exposes manual triggers that match the situation: re-search, request decision, cancel.
4. The historical event timeline is preserved as **History** below the live status.
5. Storybook is updated *first* — every visual variation has a story before the LiveView is wired.

## Non-Goals

- Redesigning the Downloads list page (`/download`). The row-level summary there is out of scope.
- Adding new pursuit lifecycle states or events beyond what's needed for re-search.
- Replacing the existing Decision Card component when `state == :needs_decision`.

## Architecture

### New ViewModel: `PursuitStatus`

A read-side ViewModel that joins everything we know about a pursuit's current activity:

```elixir
%MediaCentarr.Acquisition.ViewModels.PursuitStatus{
  pursuit_id:        Ecto.UUID.t(),
  title:             String.t(),
  state:             State.t(),                # :active | :needs_decision | terminal
  origin:            :auto | :manual,
  target:            %Target{}                 # tmdb identity for the header
  criteria_summary:  String.t() | nil,
  current_action:    %CurrentAction{},         # what's happening NOW
  next_step:         %NextStep{} | nil,        # what's expected NEXT (nil when terminal)
  download:          %DownloadProgress{} | nil,# live queue data, when present
  staleness:         :fresh | :stale | :very_stale,
  last_activity_at:  DateTime.t() | nil,
  available_actions: [action_atom()]            # :cancel | :re_search | :request_decision
}
```

Embedded structs:

- `CurrentAction` — `%{verb: String.t(), description: String.t(), severity: :info | :success | :warning | :error}`
- `NextStep` — `%{description: String.t()}` (kept structured so we can extend with countdowns/ETAs later)
- `DownloadProgress` — `%{state: :downloading | :queued | :stalled | :paused | :completed | :error | :other, progress_pct: float() | nil, size_bytes: integer() | nil, size_left_bytes: integer() | nil, eta: String.t() | nil, client: String.t() | nil}`
- `Target` — `%{tmdb_type: String.t(), tmdb_id: String.t() | nil, season_number: integer() | nil, episode_number: integer() | nil, year: integer() | nil}`

### Pure derivation: `PursuitStatus.derive/3`

```elixir
@spec derive(Pursuit.t(), Grab.t() | nil, QueueItem.t() | nil) ::
        {CurrentAction.t(), NextStep.t() | nil, [action_atom()]}
```

A pure function — no DB, no PubSub — that produces the dynamic fields from inputs. Tested exhaustively against the truth table below. Lives in `MediaCentarr.Acquisition.ViewModels.PursuitStatus`.

### Read-side assembly: `Pursuits.status_for/1`

```elixir
@spec status_for(Ecto.UUID.t()) :: {:ok, PursuitStatus.t()} | {:error, :not_found}
```

In `MediaCentarr.Acquisition.Pursuits`, next to `header_for/1` and `timeline_for/1`. Steps:

1. `Repo.get(Pursuit, id)` — short-circuit `{:error, :not_found}`.
2. `latest_grab(pursuit_id)` — may be `{:error, :not_found}`; passed as `nil` to derive when absent.
3. `Downloads.QueueMonitor.snapshot()` — filter by normalized title match against `grab.release_title`. Returns the best matching `%QueueItem{}` or `nil`.
4. `latest_event_at(pursuit_id)` — newest `occurred_at` from the event log; drives staleness.
5. Call `derive/3`, assemble the struct, return.

Staleness thresholds:
- `:fresh` — last activity within 1 hour
- `:stale` — within 24 hours
- `:very_stale` — older than 24 hours

### New write-side command: `Pursuits.Commands.ReSearch`

```elixir
@spec execute(%{pursuit_id: Ecto.UUID.t()}) ::
        {:ok, Pursuit.t()} | {:error, :not_found | :not_eligible | term()}
```

Forces a fresh `SearchAndGrab` cycle for the pursuit's underlying grab. Records a `pursuit_re_searched` event. Steps:

1. Load pursuit; refuse with `:not_eligible` if not `:active`.
2. Load latest grab; refuse with `:not_eligible` if grab is `nil`, `:grabbed`, or `:searching` (a fresh search is already running).
3. Apply the right re-search transition based on grab state:
   - `:snoozed` — clear the snooze and enqueue a fresh `SearchAndGrab` job immediately (preserves `attempt_count`).
   - `:cancelled` / `:abandoned` — delegate to existing `Acquisition.rearm_grab/1` (resets `attempt_count` to 0, status → `:searching`, enqueues job).
4. Record a `pursuit_re_searched` event.
5. Broadcast on `acquisition:updates`.

The "force out of snooze" path is new — `rearm_grab/1` currently only handles terminal-failure states. Implementation may extend `Acquisition` with a small helper (`force_search_now/1` or similar) — the exact private API is a plan-level decision; the command's contract above is the public surface.

### New event: `pursuit_re_searched`

Records that a user manually re-armed the pursuit's grab.

```elixir
defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitReSearched do
  use Define
  defevent [:pursuit_id, :pursuit_title, :occurred_at]
end
```

Summary line in `Pursuits.summary_for/2`: `"Manual re-search triggered"`. Severity `:info`.

## Components

### `PursuitHeader` (refactored)

**Becomes** an identity card — what the pursuit is *for*, not how it's *doing*.

```
┌─────────────────────────────────────────┐
│ Rick-and-Morty-The-Anime-S01E05-…  [Active] │
│ TV • S01E05 • 2026                      │
│ Criteria: 1080p–4K                      │  (auto pursuits only)
└─────────────────────────────────────────┘
```

Removed from the header: `Attempts`, `Tried releases`, `Started`, `Origin`, cancel button. (These now appear in `PursuitActivity` *when relevant*.)

### `PursuitActivity` (new)

The new big thing. Lives between `PursuitHeader` and `PursuitTimeline`. Renders:

```
┌─────────────────────────────────────────┐
│ ▶ Downloading from "Indexer Name"       │
│   73% • 240 MB / 330 MB • ETA 8m        │
│   [████████████░░░░░░░░░░]              │   (progress bar — only when download present)
│                                         │
│   Next: file lands → identity check     │
│                                         │
│   Last activity: 12 seconds ago         │
│                                         │
│   [Cancel pursuit] [Pick a different release] │
└─────────────────────────────────────────┘
```

Component contract (typed attrs):

```elixir
attr :vm, MediaCentarr.Acquisition.ViewModels.PursuitStatus, required: true
attr :on_cancel,             :string, default: nil
attr :on_re_search,          :string, default: nil
attr :on_request_decision,   :string, default: nil
```

Display rules:
- The leading `▶` / status verb is colored by `current_action.severity`.
- The progress bar renders iff `vm.download` is non-nil and `vm.download.progress_pct` is non-nil.
- The next-step line is hidden when `next_step == nil` (terminal states).
- Buttons render iff their action atom is in `vm.available_actions`. Fixed order: re-search → request_decision → cancel.
- Staleness footnote: red text for `:very_stale`, amber for `:stale`, hidden for `:fresh`.

### `PursuitTimeline` (unchanged structurally)

Heading renamed `Timeline` → `History`. Renders the same vertical event log.

## Current-Action Truth Table

| pursuit | grab | queue item | current_action (verb + description) | next_step | actions |
|---|---|---|---|---|---|
| `active` | `searching` | — | "Searching" — "Looking for an acceptable release (attempt N)." | "Trying expanded queries." | cancel (no re-search — already running) |
| `active` | `snoozed` | — | "Snoozed" — "Next search in ~Hh Mm." | "Will resume automatically." | cancel, re-search, request_decision |
| `active` | `grabbed` | `:downloading` | "Downloading" — "From {indexer/client} — {progress%} • ETA {eta}." | "When complete, file watcher matches the title." | cancel |
| `active` | `grabbed` | `:queued` | "Queued" — "Waiting for a slot at the download client." | "Will start when a slot frees up." | cancel |
| `active` | `grabbed` | `:stalled` | "Stalled" — "Download can't make progress." | "Re-search for a different release, or wait." | cancel, re-search, request_decision |
| `active` | `grabbed` | `:paused` | "Paused" — "Paused at the download client." | "Resume it in your client." | cancel |
| `active` | `grabbed` | `:completed` | "Verifying" — "Download finished — waiting for the file to be matched." | "InboundListener picks it up next." | cancel |
| `active` | `grabbed` | `:error` | "Error" — "Download client reported an error." | "Check your client or re-search." | cancel, re-search |
| `active` | `grabbed` | _none_ | "Waiting" — "Not visible in your download client." | "Either it completed and is being matched, or it never reached the client." | cancel, re-search |
| `active` | `abandoned` | — | "Stopped" — "Auto-search gave up after N attempts." | "Re-search or pick a release manually." | cancel, re-search, request_decision |
| `active` | `cancelled` | — | "Stopped" — "Underlying grab was cancelled." | "Re-search to restart." | cancel, re-search |
| `active` | _none_ | — | "Unknown" — "Pursuit has no linked grab — please cancel." | nil | cancel |
| `needs_decision` | * | * | "Decision needed" — "Pick a release below." | "Decision card below." | cancel |
| `satisfied` | * | * | "Done" — "File landed and identity verified." | nil | (none) |
| `exhausted` | * | * | "Gave up" — "Exhausted after N attempts." | "Start a new pursuit if you still want this." | (none) |
| `cancelled` | * | * | "Cancelled" — "{reason}." | nil | (none) |

The unknown-pairing `(active, no grab)` logs a warning via `MediaCentarr.Log` — it indicates a data-integrity issue but the page still renders rather than 500'ing.

## Data Flow & PubSub

LiveView subscriptions in `mount/3`:

- `Acquisition.subscribe()` — existing — pursuit/grab event broadcasts on `acquisition:updates`.
- `Acquisition.subscribe_queue()` — **new on this page** — `QueueMonitor` snapshot broadcasts on `acquisition:queue`. Registering the LiveView bumps `QueueMonitor` to 1s polling cadence.

`handle_info/2` dispatches:

- `{:queue_state, _}` → `load_status(socket)`.
- Pursuit event for `socket.assigns.pursuit_id` → `load_status(socket)`.
- All other messages → no-op.

Every reload calls `Pursuits.status_for(id)` and re-assigns. No internal timer needed — queue snapshots provide a ~1s heartbeat, which automatically refreshes staleness and progress.

The download/queue match is title-based: normalized lowercase, whitespace-and-punctuation-stripped equality between `grab.release_title` and `queue_item.title`. If a future iteration adds the .torrent hash to the grab row, the matcher can switch to hash-equality. For now: normalized title with a `nil` fallback ("Not visible in your download client").

## Storybook (built FIRST)

Per project rule, every visual variation has a story before LiveView wiring. New `storybook/acquisition/pursuit_activity.story.exs` covers:

- `downloading_healthy` — progress, ETA, no warnings
- `downloading_stalled` — `:warning` severity, stall message
- `downloading_paused` — paused state
- `queued_at_client` — `:queued`, no progress yet
- `searching_prowlarr` — `grab.status == :searching`
- `snoozed` — countdown text
- `waiting_for_file` — grabbed but no queue match
- `download_complete_unmatched` — `:completed` queue state, file not yet detected
- `needs_decision` — buttons row including request_decision; Decision Card is rendered separately
- `terminal_satisfied`
- `terminal_exhausted`
- `terminal_cancelled`

Updated `storybook/acquisition/pursuit_header.story.exs`: identity-only variations — manual-origin, auto-origin with criteria, missing target metadata.

`storybook/acquisition/timeline.story.exs`: rename heading to "History"; otherwise unchanged.

## Testing

Strict test-first per `automated-testing` skill. New / extended files:

| File | Coverage |
|---|---|
| `test/media_centarr/acquisition/view_models/pursuit_status_derive_test.exs` (new) | Every row of the truth table — pure inputs, pure outputs |
| `test/media_centarr/acquisition/pursuits_status_for_test.exs` (new) | `status_for/1` with factory pursuits/grabs and faked QueueMonitor snapshots; staleness threshold boundaries |
| `test/media_centarr/acquisition/pursuits/commands/re_search_test.exs` (new) | Re-search command — happy path, refusal on terminal pursuit, refusal on grabbed grab, refusal on missing pursuit |
| `test/media_centarr_web/live/pursuit_live_test.exs` (extend) | Page renders for each pursuit state without 500; cancel / re-search / request-decision events fire the right commands; queue snapshot deliveries refresh the status |
| `storybook/acquisition/pursuit_activity.story.exs` (new) | All 12 variations render under `storybook_test.exs` |

The pure-derivation tests double as executable documentation of the truth table.

## Out-of-scope follow-ups

- Adding a structured "watch dirs" / file-watcher health surface to the page (useful but separate concern).
- Surfacing the linked Grab row directly on the page with a navigation link.
- Cross-pursuit aggregate health on `/download` list rows (the list still uses `PursuitRow`).
- Hash-based queue matching (waits for the grab row to carry the .torrent hash).

## Open questions

None at the time of writing. Real-world feedback after shipping will inform the next iteration.
