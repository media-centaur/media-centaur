# Pursuit Detail Page Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static-counter pursuit detail page with a live "what's happening now" status panel backed by a new `PursuitStatus` ViewModel, plus manual re-search and request-decision triggers.

**Architecture:** Read-side `Pursuits.status_for/1` joins the pursuit + latest grab + `QueueMonitor` snapshot, then a pure `PursuitStatus.derive/3` function maps `(pursuit_state, grab_status, queue_state)` to current_action/next_step/available_actions via a truth table. The LiveView subscribes to both `acquisition:updates` and `acquisition:queue` so the page refreshes on either event source. Write-side: new `Commands.ReSearch` plus `Acquisition.force_search_now/1` to break snoozed grabs out of their backoff.

**Tech Stack:** Elixir / Phoenix LiveView / Ecto / Phoenix Storybook / Oban (existing `SearchAndGrab` job).

**Spec:** `docs/superpowers/specs/2026-05-11-pursuit-detail-redesign-design.md`

**Project conventions:**
- Run `mix precommit` before declaring the feature complete — must be clean (zero warnings policy).
- Use the `superpowers:test-driven-development` skill cadence: red → green → commit per behaviour.
- This is a JJ repo — use `jj describe -m "..."` then `jj new` for each commit, never `git commit`.
- Always pass `-m` to `jj describe` (memory: `jj-editor-flags`).
- Storybook stories ship FIRST for any new component (memory: `storybook-first`).
- Stories and test fixtures must use generic/PD/CC titles, not real shows (memory: `no-real-show-titles-in-code`).

---

## File Structure

**Create:**
- `lib/media_centarr/acquisition/view_models/current_action.ex` — `%CurrentAction{verb, description, severity}`
- `lib/media_centarr/acquisition/view_models/next_step.ex` — `%NextStep{description}`
- `lib/media_centarr/acquisition/view_models/download_progress.ex` — `%DownloadProgress{state, progress_pct, size_bytes, size_left_bytes, eta, client}`
- `lib/media_centarr/acquisition/view_models/target.ex` — `%Target{tmdb_type, tmdb_id, season_number, episode_number, year}`
- `lib/media_centarr/acquisition/view_models/pursuit_status.ex` — main struct + pure `derive/3`
- `lib/media_centarr/acquisition/pursuits/events/pursuit_re_searched.ex` — new event type
- `lib/media_centarr/acquisition/pursuits/commands/re_search.ex` — new command
- `lib/media_centarr_web/components/acquisition/pursuit_activity.ex` — new live-status component
- `storybook/acquisition/pursuit_activity.story.exs` — 12 variations
- `test/media_centarr/acquisition/view_models/pursuit_status_test.exs` — pure derive tests
- `test/media_centarr/acquisition/pursuits_status_for_test.exs` — integration tests
- `test/media_centarr/acquisition/pursuits/commands/re_search_test.exs` — command tests

**Modify:**
- `lib/media_centarr/acquisition/pursuits.ex` — add `status_for/1`, queue match helper; add `pursuit_re_searched` to summary_for/severity_for
- `lib/media_centarr/acquisition/pursuits/event.ex` — extend `@kinds` with `pursuit_re_searched`
- `lib/media_centarr/acquisition/pursuits/events.ex` — extend `@kind_modules` map
- `lib/media_centarr/acquisition.ex` — add `force_search_now/1` helper
- `lib/media_centarr_web/live/pursuit_live.ex` — full rewire (subscriptions + handle_event + render)
- `lib/media_centarr_web/components/acquisition/pursuit_header.ex` — slim down to identity-only
- `lib/media_centarr_web/components/acquisition/pursuit_timeline.ex` — rename heading
- `storybook/acquisition/pursuit_header.story.exs` — drop counter variations, add target/criteria
- `storybook/acquisition/timeline.story.exs` — update heading variation if it asserts text
- `test/media_centarr_web/live/pursuit_live_test.exs` — extend coverage (if file exists; otherwise leave for new file)

---

## Task 1: Sub-struct ViewModels (CurrentAction, NextStep, DownloadProgress, Target)

**Files:**
- Create: `lib/media_centarr/acquisition/view_models/current_action.ex`
- Create: `lib/media_centarr/acquisition/view_models/next_step.ex`
- Create: `lib/media_centarr/acquisition/view_models/download_progress.ex`
- Create: `lib/media_centarr/acquisition/view_models/target.ex`

These are pure data carriers — no logic, no tests of their own. They are exercised by every test of `PursuitStatus.derive/3` in Task 2.

- [ ] **Step 1: Create `current_action.ex`**

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.CurrentAction do
  @moduledoc "What the pursuit is doing right now — one verb plus context."

  @enforce_keys [:verb, :description, :severity]
  defstruct [:verb, :description, :severity]

  @type severity :: :info | :success | :warning | :error
  @type t :: %__MODULE__{
          verb: String.t(),
          description: String.t(),
          severity: severity()
        }
end
```

- [ ] **Step 2: Create `next_step.ex`**

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.NextStep do
  @moduledoc "What's expected to happen next on this pursuit (automatic)."

  @enforce_keys [:description]
  defstruct [:description]

  @type t :: %__MODULE__{description: String.t()}
end
```

- [ ] **Step 3: Create `download_progress.ex`**

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.DownloadProgress do
  @moduledoc "Live download state for the matched QueueItem."

  @enforce_keys [:state]
  defstruct [:state, :progress_pct, :size_bytes, :size_left_bytes, :eta, :client]

  @type state :: :downloading | :queued | :stalled | :paused | :completed | :error | :other

  @type t :: %__MODULE__{
          state: state(),
          progress_pct: float() | nil,
          size_bytes: integer() | nil,
          size_left_bytes: integer() | nil,
          eta: String.t() | nil,
          client: String.t() | nil
        }
end
```

- [ ] **Step 4: Create `target.ex`**

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.Target do
  @moduledoc "TMDB identity of the pursuit's goal — used in the header."

  @enforce_keys [:tmdb_type]
  defstruct [:tmdb_type, :tmdb_id, :season_number, :episode_number, :year]

  @type t :: %__MODULE__{
          tmdb_type: String.t(),
          tmdb_id: String.t() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          year: integer() | nil
        }
end
```

- [ ] **Step 5: Compile check**

Run: `mix compile --warnings-as-errors`
Expected: clean compile, no warnings.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(acquisition): add CurrentAction/NextStep/DownloadProgress/Target view-models"
jj new
```

---

## Task 2: `PursuitStatus` struct + pure `derive/3` (TDD)

**Files:**
- Create: `lib/media_centarr/acquisition/view_models/pursuit_status.ex`
- Create: `test/media_centarr/acquisition/view_models/pursuit_status_test.exs`

The truth table from the spec. `derive/3` takes `(Pursuit.t(), Grab.t() | nil, QueueItem.t() | nil)` and returns `{CurrentAction.t(), NextStep.t() | nil, [action_atom()]}`. No DB, no PubSub — entirely pure.

- [ ] **Step 1: Write the failing tests**

Create `test/media_centarr/acquisition/view_models/pursuit_status_test.exs`:

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.PursuitStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.ViewModels.PursuitStatus
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Downloads.QueueItem

  defp pursuit(state, attrs \\ %{}) do
    base = %Pursuit{
      id: "p-1",
      title: "Sample Movie",
      state: Atom.to_string(state),
      origin: "auto",
      tmdb_type: "movie",
      attempt_count: 0,
      tried_release_guids: []
    }
    struct(base, attrs)
  end

  defp grab(status, attrs \\ %{}) do
    base = %Grab{
      id: "g-1",
      status: Atom.to_string(status),
      title: "Sample Movie",
      release_title: "Sample.Movie.1080p.WEB-DL.mkv",
      attempt_count: 0
    }
    struct(base, attrs)
  end

  defp queue_item(state, attrs \\ %{}) do
    base = %QueueItem{
      id: "qi-1",
      title: "Sample.Movie.1080p.WEB-DL.mkv",
      state: state
    }
    struct(base, attrs)
  end

  describe "derive/3 — active + searching" do
    test "returns Searching with cancel-only actions" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:active), grab(:searching), nil)

      assert action.verb == "Searching"
      assert action.severity == :info
      assert next != nil
      assert actions == [:cancel]
    end
  end

  describe "derive/3 — active + snoozed" do
    test "returns Snoozed with cancel + re_search + request_decision" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:active), grab(:snoozed), nil)

      assert action.verb == "Snoozed"
      assert action.severity == :info
      assert next != nil
      assert :cancel in actions
      assert :re_search in actions
      assert :request_decision in actions
    end
  end

  describe "derive/3 — active + grabbed + queue states" do
    test "downloading -> Downloading, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:downloading))

      assert action.verb == "Downloading"
      assert action.severity == :info
      assert actions == [:cancel]
    end

    test "queued -> Queued, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:queued))

      assert action.verb == "Queued"
      assert actions == [:cancel]
    end

    test "stalled -> Stalled (warning) with re_search + request_decision" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:stalled))

      assert action.verb == "Stalled"
      assert action.severity == :warning
      assert :re_search in actions
      assert :request_decision in actions
    end

    test "paused -> Paused" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:paused))

      assert action.verb == "Paused"
      assert actions == [:cancel]
    end

    test "completed -> Verifying (waiting for file watcher)" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:completed))

      assert action.verb == "Verifying"
      assert next.description =~ "InboundListener"
      assert actions == [:cancel]
    end

    test "error -> Error with re_search" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:error))

      assert action.verb == "Error"
      assert action.severity == :error
      assert :re_search in actions
    end

    test "no queue match -> Waiting, with re_search hint" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), grab(:grabbed), nil)

      assert action.verb == "Waiting"
      assert :re_search in actions
    end
  end

  describe "derive/3 — active + terminal-failure grab states" do
    test "abandoned -> Stopped with all manual triggers" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), grab(:abandoned), nil)

      assert action.verb == "Stopped"
      assert :re_search in actions
      assert :request_decision in actions
    end

    test "cancelled grab -> Stopped with re_search" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), grab(:cancelled), nil)

      assert action.verb == "Stopped"
      assert :re_search in actions
    end
  end

  describe "derive/3 — active + no grab" do
    test "missing grab logs as Unknown with cancel-only" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), nil, nil)

      assert action.verb == "Unknown"
      assert action.severity == :warning
      assert actions == [:cancel]
    end
  end

  describe "derive/3 — terminal pursuit states" do
    test "needs_decision -> Decision needed" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:needs_decision), grab(:snoozed), nil)

      assert action.verb == "Decision needed"
      assert actions == [:cancel]
    end

    test "satisfied -> Done, no actions, no next_step" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:satisfied), grab(:grabbed), nil)

      assert action.verb == "Done"
      assert action.severity == :success
      assert next == nil
      assert actions == []
    end

    test "exhausted -> Gave up, no actions" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:exhausted), grab(:abandoned), nil)

      assert action.verb == "Gave up"
      assert action.severity == :error
      assert actions == []
    end

    test "cancelled -> Cancelled, no actions" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:cancelled), nil, nil)

      assert action.verb == "Cancelled"
      assert next == nil
      assert actions == []
    end
  end
end
```

- [ ] **Step 2: Run tests; expect failure**

Run: `mix test test/media_centarr/acquisition/view_models/pursuit_status_test.exs`
Expected: All tests fail with `UndefinedFunctionError` — `PursuitStatus.derive/3` does not exist yet.

- [ ] **Step 3: Implement `PursuitStatus` struct + `derive/3`**

Create `lib/media_centarr/acquisition/view_models/pursuit_status.ex`:

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.PursuitStatus do
  @moduledoc """
  Display contract for the pursuit detail page.

  Built by `MediaCentarr.Acquisition.Pursuits.status_for/1` — joins the
  pursuit row with its latest grab and any matching download-client queue
  item, then routes through the pure `derive/3` function to produce
  `current_action`, `next_step`, and `available_actions`.
  """

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Pursuits.State

  alias MediaCentarr.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep,
    Target
  }

  alias MediaCentarr.Downloads.QueueItem

  @enforce_keys [
    :pursuit_id,
    :title,
    :state,
    :origin,
    :target,
    :current_action,
    :available_actions,
    :staleness
  ]
  defstruct [
    :pursuit_id,
    :title,
    :state,
    :origin,
    :target,
    :criteria_summary,
    :current_action,
    :next_step,
    :download,
    :staleness,
    :last_activity_at,
    available_actions: []
  ]

  @type action :: :cancel | :re_search | :request_decision
  @type staleness :: :fresh | :stale | :very_stale

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          title: String.t(),
          state: State.t(),
          origin: :auto | :manual,
          target: Target.t(),
          criteria_summary: String.t() | nil,
          current_action: CurrentAction.t(),
          next_step: NextStep.t() | nil,
          download: DownloadProgress.t() | nil,
          staleness: staleness(),
          last_activity_at: DateTime.t() | nil,
          available_actions: [action()]
        }

  @doc """
  Pure mapping from (pursuit, grab, queue_item) to the dynamic display fields.
  No DB, no PubSub. See the spec's truth table.
  """
  @spec derive(Pursuit.t(), Grab.t() | nil, QueueItem.t() | nil) ::
          {CurrentAction.t(), NextStep.t() | nil, [action()]}
  def derive(%Pursuit{state: "satisfied"}, _grab, _qi),
    do: {
      %CurrentAction{verb: "Done", description: "File landed and identity verified.", severity: :success},
      nil,
      []
    }

  def derive(%Pursuit{state: "exhausted"} = p, _grab, _qi),
    do: {
      %CurrentAction{
        verb: "Gave up",
        description: "Exhausted after #{p.attempt_count} attempts.",
        severity: :error
      },
      %NextStep{description: "Start a new pursuit if you still want this."},
      []
    }

  def derive(%Pursuit{state: "cancelled"}, _grab, _qi),
    do: {
      %CurrentAction{verb: "Cancelled", description: "Pursuit cancelled.", severity: :info},
      nil,
      []
    }

  def derive(%Pursuit{state: "needs_decision"}, _grab, _qi),
    do: {
      %CurrentAction{verb: "Decision needed", description: "Pick a release below.", severity: :warning},
      %NextStep{description: "Use the decision card below to pick or skip."},
      [:cancel]
    }

  def derive(%Pursuit{state: "active"}, nil, _qi),
    do: {
      %CurrentAction{
        verb: "Unknown",
        description: "Pursuit has no linked grab — please cancel.",
        severity: :warning
      },
      nil,
      [:cancel]
    }

  def derive(%Pursuit{state: "active"} = p, %Grab{status: "searching"} = g, _qi),
    do: {
      %CurrentAction{
        verb: "Searching",
        description: "Looking for an acceptable release (attempt #{g.attempt_count + 1}).",
        severity: :info
      },
      %NextStep{description: "Trying expanded queries — will pick the best match or snooze."},
      [:cancel]
    }
    |> with_pursuit(p)

  def derive(%Pursuit{state: "active"}, %Grab{status: "snoozed"}, _qi),
    do: {
      %CurrentAction{
        verb: "Snoozed",
        description: "Waiting before the next search attempt.",
        severity: :info
      },
      %NextStep{description: "Will resume automatically."},
      [:cancel, :re_search, :request_decision]
    }

  def derive(%Pursuit{state: "active"}, %Grab{status: "abandoned"} = g, _qi),
    do: {
      %CurrentAction{
        verb: "Stopped",
        description: "Auto-search gave up after #{g.attempt_count} attempts.",
        severity: :warning
      },
      %NextStep{description: "Re-search or pick a release manually."},
      [:cancel, :re_search, :request_decision]
    }

  def derive(%Pursuit{state: "active"}, %Grab{status: "cancelled"}, _qi),
    do: {
      %CurrentAction{
        verb: "Stopped",
        description: "Underlying grab was cancelled.",
        severity: :warning
      },
      %NextStep{description: "Re-search to restart."},
      [:cancel, :re_search]
    }

  def derive(%Pursuit{state: "active"}, %Grab{status: "grabbed"}, %QueueItem{state: qstate} = qi)
      when not is_nil(qstate),
      do: derive_grabbed_in_queue(qi)

  def derive(%Pursuit{state: "active"}, %Grab{status: "grabbed"}, nil),
    do: {
      %CurrentAction{
        verb: "Waiting",
        description: "Not visible in your download client.",
        severity: :info
      },
      %NextStep{
        description: "Either it completed and is being matched, or it never reached the client."
      },
      [:cancel, :re_search]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :downloading} = qi),
    do: {
      %CurrentAction{
        verb: "Downloading",
        description: download_description(qi),
        severity: :info
      },
      %NextStep{description: "When complete, the file watcher matches the title."},
      [:cancel]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :queued}),
    do: {
      %CurrentAction{
        verb: "Queued",
        description: "Waiting for a slot at the download client.",
        severity: :info
      },
      %NextStep{description: "Will start when a slot frees up."},
      [:cancel]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :stalled}),
    do: {
      %CurrentAction{
        verb: "Stalled",
        description: "Download client can't make progress.",
        severity: :warning
      },
      %NextStep{description: "Re-search for a different release, or wait."},
      [:cancel, :re_search, :request_decision]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :paused}),
    do: {
      %CurrentAction{
        verb: "Paused",
        description: "Paused at the download client.",
        severity: :info
      },
      %NextStep{description: "Resume it in your download client."},
      [:cancel]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :completed}),
    do: {
      %CurrentAction{
        verb: "Verifying",
        description: "Download finished — waiting for the file to be matched.",
        severity: :info
      },
      %NextStep{description: "InboundListener picks it up next."},
      [:cancel]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :error}),
    do: {
      %CurrentAction{
        verb: "Error",
        description: "Download client reported an error.",
        severity: :error
      },
      %NextStep{description: "Check your client or re-search for a different release."},
      [:cancel, :re_search]
    }

  defp derive_grabbed_in_queue(%QueueItem{state: :other}),
    do: {
      %CurrentAction{
        verb: "Waiting",
        description: "Download client state unrecognized.",
        severity: :info
      },
      %NextStep{description: "Re-search to try a different release."},
      [:cancel, :re_search]
    }

  defp download_description(%QueueItem{} = qi) do
    bits =
      []
      |> maybe_prepend(qi.eta, &"ETA #{&1}")
      |> maybe_prepend(qi.progress, &"#{round(&1 * 100)}%")
      |> maybe_prepend(qi.download_client, &"From #{&1}")

    case bits do
      [] -> "Downloading."
      parts -> parts |> Enum.reverse() |> Enum.join(" • ")
    end
  end

  defp maybe_prepend(list, nil, _fmt), do: list
  defp maybe_prepend(list, value, fmt), do: [fmt.(value) | list]

  defp with_pursuit(tuple, _pursuit), do: tuple
end
```

- [ ] **Step 4: Run tests; expect green**

Run: `mix test test/media_centarr/acquisition/view_models/pursuit_status_test.exs`
Expected: 14+ tests pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(acquisition): add PursuitStatus view-model with pure derive/3"
jj new
```

---

## Task 3: New event type `pursuit_re_searched`

**Files:**
- Create: `lib/media_centarr/acquisition/pursuits/events/pursuit_re_searched.ex`
- Modify: `lib/media_centarr/acquisition/pursuits/event.ex` (extend `@kinds`)
- Modify: `lib/media_centarr/acquisition/pursuits/events.ex` (extend `@kind_modules`)

- [ ] **Step 1: Write the failing test**

Append to `test/media_centarr/acquisition/pursuits/events_test.exs` (open the file, find the existing "every kind has a struct module" assertion). If unsure, run:

```bash
grep -n "kinds\|kind_modules\|@kind_modules" test/media_centarr/acquisition/pursuits/events_test.exs
```

The exhaustiveness test there will fail when we add `pursuit_re_searched` to `@kinds` without a matching struct. We rely on that test to fail first; no new test code required for this task.

- [ ] **Step 2: Create the event struct**

Create `lib/media_centarr/acquisition/pursuits/events/pursuit_re_searched.ex`:

```elixir
defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitReSearched do
  @moduledoc "Recorded when a user manually re-arms the pursuit's underlying grab."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_re_searched",
    payload_keys: []
end
```

- [ ] **Step 3: Extend `Event.@kinds`**

Edit `lib/media_centarr/acquisition/pursuits/event.ex`. Find:

```elixir
  @kinds ~w(
    pursuit_started
    ...
    pursuit_cancelled
  )
```

Add `pursuit_re_searched` to the list:

```elixir
  @kinds ~w(
    pursuit_started
    search_started
    release_picked
    release_no_match
    download_started
    health_changed
    stall_confirmed
    zero_seeders_confirmed
    auto_cancelled
    fallback_initiated
    user_decision_requested
    user_decision_recorded
    identity_mismatch
    identity_verified
    pursuit_satisfied
    pursuit_exhausted
    pursuit_cancelled
    pursuit_re_searched
  )
```

- [ ] **Step 4: Extend `Events.@kind_modules`**

Edit `lib/media_centarr/acquisition/pursuits/events.ex`. In the alias block add `PursuitReSearched`, and add the map entry:

```elixir
alias MediaCentarr.Acquisition.Pursuits.Events.{
  AutoCancelled,
  DownloadStarted,
  FallbackInitiated,
  HealthChanged,
  IdentityMismatch,
  IdentityVerified,
  PursuitCancelled,
  PursuitExhausted,
  PursuitReSearched,
  PursuitSatisfied,
  PursuitStarted,
  ReleaseNoMatch,
  ReleasePicked,
  SearchStarted,
  StallConfirmed,
  UserDecisionRecorded,
  UserDecisionRequested,
  ZeroSeedersConfirmed
}

@kind_modules %{
  "pursuit_started" => PursuitStarted,
  "search_started" => SearchStarted,
  "release_picked" => ReleasePicked,
  "release_no_match" => ReleaseNoMatch,
  "download_started" => DownloadStarted,
  "health_changed" => HealthChanged,
  "stall_confirmed" => StallConfirmed,
  "zero_seeders_confirmed" => ZeroSeedersConfirmed,
  "auto_cancelled" => AutoCancelled,
  "fallback_initiated" => FallbackInitiated,
  "user_decision_requested" => UserDecisionRequested,
  "user_decision_recorded" => UserDecisionRecorded,
  "identity_mismatch" => IdentityMismatch,
  "identity_verified" => IdentityVerified,
  "pursuit_satisfied" => PursuitSatisfied,
  "pursuit_exhausted" => PursuitExhausted,
  "pursuit_cancelled" => PursuitCancelled,
  "pursuit_re_searched" => PursuitReSearched
}
```

- [ ] **Step 5: Add summary + severity in `Pursuits`**

Edit `lib/media_centarr/acquisition/pursuits.ex`. Find the `summary_for/2` clauses and add (before the catch-all `summary_for(kind, _)`):

```elixir
defp summary_for("pursuit_re_searched", _), do: "Manual re-search triggered"
```

Severity defaults to `:info` via the existing catch-all `severity_for/1` — nothing to add unless you want a non-default. Keep it `:info`.

- [ ] **Step 6: Run tests**

Run: `mix test test/media_centarr/acquisition/pursuits/`
Expected: all event-exhaustiveness tests pass; no regressions.

- [ ] **Step 7: Commit**

```bash
jj describe -m "feat(acquisition): add pursuit_re_searched event type"
jj new
```

---

## Task 4: `Acquisition.force_search_now/1` helper

**Files:**
- Modify: `lib/media_centarr/acquisition.ex`
- Modify: `test/media_centarr/acquisition_test.exs` (or wherever Acquisition tests live)

This breaks a snoozed grab out of its backoff and enqueues a fresh `SearchAndGrab` job *without* resetting `attempt_count` (that's what distinguishes it from `rearm_grab/1`).

- [ ] **Step 1: Find the right test file**

Run: `ls test/media_centarr/acquisition*test.exs && grep -l "rearm_grab" test/media_centarr/`
Expected: confirms the existing test file location for `Acquisition`. If `test/media_centarr/acquisition_test.exs` exists, use it; otherwise create the file mirroring the structure of nearby tests.

- [ ] **Step 2: Write the failing test**

Add to the file from Step 1:

```elixir
describe "force_search_now/1" do
  setup do
    grab = create_grab(%{status: "snoozed", attempt_count: 3})
    {:ok, grab: grab}
  end

  test "returns the updated grab with status searching and attempt_count preserved", %{grab: grab} do
    {:ok, updated} = Acquisition.force_search_now(grab.id)

    assert updated.status == "searching"
    assert updated.attempt_count == 3
  end

  test "enqueues a SearchAndGrab Oban job", %{grab: grab} do
    {:ok, _updated} = Acquisition.force_search_now(grab.id)

    assert_enqueued(worker: MediaCentarr.Acquisition.Jobs.SearchAndGrab, args: %{"grab_id" => grab.id})
  end

  test "no-ops on grabs that are not snoozed" do
    grab = create_grab(%{status: "searching"})
    {:ok, returned} = Acquisition.force_search_now(grab.id)

    assert returned.id == grab.id
    refute_enqueued(worker: MediaCentarr.Acquisition.Jobs.SearchAndGrab)
  end

  test "returns :not_found for unknown grab id" do
    assert {:error, :not_found} = Acquisition.force_search_now(Ecto.UUID.generate())
  end
end
```

(`assert_enqueued/refute_enqueued` come from `use Oban.Testing` — make sure the test module sets that up. Mirror what the existing `rearm_grab` tests do.)

- [ ] **Step 3: Run tests; expect failure**

Run: `mix test test/media_centarr/acquisition_test.exs` (or whichever file)
Expected: `UndefinedFunctionError` on `force_search_now/1`.

- [ ] **Step 4: Implement `force_search_now/1`**

Edit `lib/media_centarr/acquisition.ex`. Add near `rearm_grab/1` (around line 612):

```elixir
@doc """
Breaks a snoozed grab out of its backoff and enqueues a fresh
`SearchAndGrab` job immediately. Unlike `rearm_grab/1`, this preserves
`attempt_count` (the user is asking for an immediate retry, not a
clean-slate restart).

No-op for grabs in any state other than `:snoozed` — including
already-searching, terminal-success, and terminal-failure. Returns the
unchanged grab in those cases so callers can chain.
"""
@spec force_search_now(Ecto.UUID.t()) :: {:ok, Grab.t()} | {:error, :not_found}
def force_search_now(grab_id) do
  case Repo.get(Grab, grab_id) do
    nil ->
      {:error, :not_found}

    %Grab{status: "snoozed"} = grab ->
      {:ok, refreshed} =
        grab
        |> Ecto.Changeset.change(status: "searching")
        |> Repo.update()

      Oban.insert(SearchAndGrab.new(%{"grab_id" => refreshed.id}))
      broadcast({:auto_grab_armed, refreshed})
      Log.info(:library, "auto-grab forced — #{refreshed.title}")
      {:ok, refreshed}

    %Grab{} = grab ->
      {:ok, grab}
  end
end
```

- [ ] **Step 5: Run tests; expect green**

Run: `mix test test/media_centarr/acquisition_test.exs`
Expected: all four `force_search_now` tests pass; no regressions in nearby tests.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(acquisition): add force_search_now/1 — break snooze without resetting attempts"
jj new
```

---

## Task 5: `Pursuits.Commands.ReSearch` command

**Files:**
- Create: `lib/media_centarr/acquisition/pursuits/commands/re_search.ex`
- Create: `test/media_centarr/acquisition/pursuits/commands/re_search_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/media_centarr/acquisition/pursuits/commands/re_search_test.exs`:

```elixir
defmodule MediaCentarr.Acquisition.Pursuits.Commands.ReSearchTest do
  use MediaCentarr.DataCase, async: false
  use Oban.Testing, repo: MediaCentarr.Repo

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.Commands.ReSearch
  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Repo

  defp setup_with_grab(pursuit_state, grab_status) do
    pursuit = create_pursuit(%{state: pursuit_state})

    grab =
      create_grab(%{
        pursuit_id: pursuit.id,
        status: grab_status,
        attempt_count: 3
      })

    {pursuit, grab}
  end

  describe "execute/1 — happy paths" do
    test "snoozed grab: enqueues a SearchAndGrab and records pursuit_re_searched" do
      {pursuit, grab} = setup_with_grab("active", "snoozed")

      assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})

      assert_enqueued(
        worker: MediaCentarr.Acquisition.Jobs.SearchAndGrab,
        args: %{"grab_id" => grab.id}
      )

      assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "pursuit_re_searched")
    end

    test "abandoned grab: re-arms (resets attempt_count) and records event" do
      {pursuit, _grab} = setup_with_grab("active", "abandoned")

      assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})

      assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "pursuit_re_searched")
    end

    test "cancelled grab: re-arms" do
      {pursuit, _grab} = setup_with_grab("active", "cancelled")
      assert {:ok, _updated} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end
  end

  describe "execute/1 — refusal paths" do
    test "refuses when pursuit is terminal" do
      {pursuit, _grab} = setup_with_grab("satisfied", "grabbed")
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "refuses when grab is missing" do
      pursuit = create_pursuit(%{state: "active"})
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "refuses when grab is already grabbed (file is coming)" do
      {pursuit, _grab} = setup_with_grab("active", "grabbed")
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "refuses when grab is already searching" do
      {pursuit, _grab} = setup_with_grab("active", "searching")
      assert {:error, :not_eligible} = ReSearch.execute(%{pursuit_id: pursuit.id})
    end

    test "returns :not_found for unknown pursuit_id" do
      assert {:error, :not_found} = ReSearch.execute(%{pursuit_id: Ecto.UUID.generate()})
    end
  end
end
```

- [ ] **Step 2: Run tests; expect failure**

Run: `mix test test/media_centarr/acquisition/pursuits/commands/re_search_test.exs`
Expected: all tests fail (`ReSearch` not defined).

- [ ] **Step 3: Implement the command**

Create `lib/media_centarr/acquisition/pursuits/commands/re_search.ex`:

```elixir
defmodule MediaCentarr.Acquisition.Pursuits.Commands.ReSearch do
  @moduledoc """
  Forces a fresh `SearchAndGrab` cycle for an Active pursuit.

  - `snoozed` grab → break the snooze, preserve `attempt_count`, enqueue
    immediately.
  - `abandoned` / `cancelled` grab → delegate to `Acquisition.rearm_grab/1`
    (resets `attempt_count` to 0).
  - any other grab state → `{:error, :not_eligible}`.
  """

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitReSearched

  @spec execute(%{pursuit_id: Ecto.UUID.t()}) ::
          {:ok, Pursuit.t()} | {:error, :not_found | :not_eligible | term()}
  def execute(%{pursuit_id: id}) when is_binary(id) do
    case Pursuits.get(id) do
      {:error, :not_found} = error ->
        error

      {:ok, %Pursuit{state: state}} when state != "active" ->
        {:error, :not_eligible}

      {:ok, %Pursuit{}} ->
        case Pursuits.latest_grab(id) do
          {:error, :not_found} ->
            {:error, :not_eligible}

          {:ok, grab} ->
            run_for(id, grab)
        end
    end
  end

  defp run_for(pursuit_id, %Grab{status: "snoozed"} = grab) do
    Runner.run(pursuit_id, "pursuit re-searched", fn pursuit ->
      with {:ok, _} <- Acquisition.force_search_now(grab.id),
           {:ok, _event} <-
             Events.record(%PursuitReSearched{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: DateTime.utc_now(:second)
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp run_for(pursuit_id, %Grab{status: status} = grab) when status in ~w(abandoned cancelled) do
    Runner.run(pursuit_id, "pursuit re-searched", fn pursuit ->
      with {:ok, _} <- Acquisition.rearm_grab(grab.id),
           {:ok, _event} <-
             Events.record(%PursuitReSearched{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: DateTime.utc_now(:second)
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp run_for(_pursuit_id, %Grab{}), do: {:error, :not_eligible}
end
```

- [ ] **Step 4: Add ReSearch to Acquisition boundary exports**

Edit `lib/media_centarr/acquisition.ex`. Find the `use Boundary, ..., exports: [...]` block and add `Pursuits.Commands.ReSearch`:

```elixir
exports: [
  AutoGrabSettings,
  CancelReasons,
  Grab,
  GrabStatus,
  Quality,
  QueryExpander,
  Prowlarr,
  Pursuits,
  Pursuits.Commands.Cancel,
  Pursuits.Commands.RecordUserChoice,
  Pursuits.Commands.ReSearch,
  Pursuits.Events,
  ...
]
```

- [ ] **Step 5: Run tests; expect green**

Run: `mix test test/media_centarr/acquisition/pursuits/commands/re_search_test.exs`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(acquisition): add Pursuits.Commands.ReSearch"
jj new
```

---

## Task 6: `Pursuits.status_for/1` read-side assembly

**Files:**
- Modify: `lib/media_centarr/acquisition/pursuits.ex`
- Create: `test/media_centarr/acquisition/pursuits_status_for_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/media_centarr/acquisition/pursuits_status_for_test.exs`:

```elixir
defmodule MediaCentarr.Acquisition.PursuitsStatusForTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.ViewModels.PursuitStatus
  alias MediaCentarr.Downloads.QueueItem
  alias MediaCentarr.Downloads.QueueState

  @queue_cache_key {MediaCentarr.Downloads.QueueMonitor, :state}

  setup do
    on_exit(fn -> :persistent_term.put(@queue_cache_key, %QueueState{items: []}) end)
    :persistent_term.put(@queue_cache_key, %QueueState{items: []})
    :ok
  end

  defp put_queue(items), do: :persistent_term.put(@queue_cache_key, %QueueState{items: items})

  test "returns :not_found for unknown pursuit_id" do
    assert {:error, :not_found} = Pursuits.status_for(Ecto.UUID.generate())
  end

  test "active manual pursuit with grabbed grab and no queue match -> Waiting" do
    pursuit = create_pursuit(%{state: "active", origin: "manual", title: "Sample Movie"})
    _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})

    {:ok, %PursuitStatus{} = status} = Pursuits.status_for(pursuit.id)

    assert status.current_action.verb == "Waiting"
    assert :re_search in status.available_actions
    assert status.download == nil
  end

  test "active grab matched in queue -> Downloading with DownloadProgress" do
    pursuit = create_pursuit(%{state: "active", title: "Public Domain Reel"})

    _grab =
      create_grab(%{
        pursuit_id: pursuit.id,
        status: "grabbed",
        title: pursuit.title,
        release_title: "Public.Domain.Reel.1080p.WEB-DL.mkv"
      })

    put_queue([
      %QueueItem{
        id: "abc",
        title: "Public.Domain.Reel.1080p.WEB-DL.mkv",
        state: :downloading,
        progress: 0.42,
        download_client: "qBittorrent"
      }
    ])

    {:ok, %PursuitStatus{} = status} = Pursuits.status_for(pursuit.id)

    assert status.current_action.verb == "Downloading"
    assert status.download != nil
    assert status.download.state == :downloading
    assert_in_delta status.download.progress_pct, 42.0, 0.01
    assert status.download.client == "qBittorrent"
  end

  test "staleness :very_stale for pursuits older than 24h with no recent events" do
    pursuit = create_pursuit(%{state: "active", title: "Movie A"})
    _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})

    older_than_24h = DateTime.add(DateTime.utc_now(:second), -48 * 3600, :second)
    create_pursuit_event(pursuit, "pursuit_started", %{occurred_at: older_than_24h})

    {:ok, status} = Pursuits.status_for(pursuit.id)
    assert status.staleness == :very_stale
  end

  test "staleness :fresh when latest event is within the last hour" do
    pursuit = create_pursuit(%{state: "active", title: "Movie B"})
    _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})
    create_pursuit_event(pursuit, "pursuit_started")

    {:ok, status} = Pursuits.status_for(pursuit.id)
    assert status.staleness == :fresh
  end
end
```

- [ ] **Step 2: Run tests; expect failure**

Run: `mix test test/media_centarr/acquisition/pursuits_status_for_test.exs`
Expected: `UndefinedFunctionError` on `Pursuits.status_for/1`.

- [ ] **Step 3: Implement `status_for/1` in `Pursuits`**

Edit `lib/media_centarr/acquisition/pursuits.ex`. Add the alias and function. Near the top, extend the aliases:

```elixir
alias MediaCentarr.Acquisition.ViewModels.{
  CurrentAction,
  DownloadProgress,
  NextStep,
  PursuitHeader,
  PursuitRow,
  PursuitStatus,
  Target,
  Timeline,
  TimelineEntry
}

alias MediaCentarr.Downloads.QueueItem
alias MediaCentarr.Downloads.QueueMonitor
```

(`CurrentAction`, `NextStep`, `QueueItem` may be only used inside the new code — the compiler will warn if unused. Drop any of these that the implementation below doesn't reference.)

Add the public function, placed alongside `header_for/1` and `timeline_for/1`:

```elixir
@doc """
Returns the full `PursuitStatus` view-model for the detail page —
identity + current activity + available manual triggers + staleness.
"""
@spec status_for(Ecto.UUID.t()) :: {:ok, PursuitStatus.t()} | {:error, :not_found}
def status_for(id) do
  case get(id) do
    {:error, :not_found} = error ->
      error

    {:ok, pursuit} ->
      grab = case latest_grab(id) do
        {:ok, grab} -> grab
        {:error, :not_found} -> nil
      end

      queue_item = find_queue_match(grab)
      {current_action, next_step, actions} = PursuitStatus.derive(pursuit, grab, queue_item)
      last_activity_at = latest_event_at(id)

      status = %PursuitStatus{
        pursuit_id: pursuit.id,
        title: pursuit.title,
        state: String.to_existing_atom(pursuit.state),
        origin: String.to_existing_atom(pursuit.origin),
        target: build_target(pursuit),
        criteria_summary: summarize_criteria(pursuit.criteria),
        current_action: current_action,
        next_step: next_step,
        download: build_download(queue_item),
        staleness: staleness_for(last_activity_at),
        last_activity_at: last_activity_at,
        available_actions: actions
      }

      {:ok, status}
  end
end

defp build_target(%Pursuit{} = p) do
  %Target{
    tmdb_type: p.tmdb_type,
    tmdb_id: p.tmdb_id,
    season_number: p.season_number,
    episode_number: p.episode_number,
    year: p.year
  }
end

defp build_download(nil), do: nil

defp build_download(%QueueItem{} = qi) do
  %DownloadProgress{
    state: qi.state,
    progress_pct: progress_pct(qi.progress),
    size_bytes: qi.size,
    size_left_bytes: qi.size_left,
    eta: qi.timeleft,
    client: qi.download_client
  }
end

defp progress_pct(nil), do: nil
defp progress_pct(p) when is_number(p), do: p * 100.0

defp find_queue_match(nil), do: nil
defp find_queue_match(%Grab{release_title: nil}), do: nil

defp find_queue_match(%Grab{release_title: title}) do
  normalized = normalize_title(title)

  QueueMonitor.snapshot()
  |> Enum.find(fn item -> normalize_title(item.title) == normalized end)
end

defp normalize_title(nil), do: ""

defp normalize_title(title) when is_binary(title) do
  title
  |> String.downcase()
  |> String.replace(~r/[^a-z0-9]+/i, "")
end

defp latest_event_at(pursuit_id) do
  Event
  |> where([e], e.pursuit_id == ^pursuit_id)
  |> order_by([e], desc: e.occurred_at)
  |> limit(1)
  |> select([e], e.occurred_at)
  |> Repo.one()
end

defp staleness_for(nil), do: :very_stale

defp staleness_for(%DateTime{} = ts) do
  diff_seconds = DateTime.diff(DateTime.utc_now(:second), ts)

  cond do
    diff_seconds < 3600 -> :fresh
    diff_seconds < 86_400 -> :stale
    true -> :very_stale
  end
end
```

- [ ] **Step 4: Run tests; expect green**

Run: `mix test test/media_centarr/acquisition/pursuits_status_for_test.exs`
Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(acquisition): add Pursuits.status_for/1 — full detail-page status assembly"
jj new
```

---

## Task 7: Refactor `PursuitHeader` component (identity-only)

**Files:**
- Modify: `lib/media_centarr_web/components/acquisition/pursuit_header.ex`
- Modify: `lib/media_centarr/acquisition/view_models/pursuit_header.ex`
- Modify: `storybook/acquisition/pursuit_header.story.exs`

The header becomes a *what is this pursuit for?* card — no counters, no cancel button. The full counter context (attempts, tried releases) is intentionally dropped; if we ever need it back, it goes in `PursuitActivity` for the relevant states.

- [ ] **Step 1: Update the ViewModel**

Edit `lib/media_centarr/acquisition/view_models/pursuit_header.ex`. Replace the file with:

```elixir
defmodule MediaCentarr.Acquisition.ViewModels.PursuitHeader do
  @moduledoc "Identity contract for the detail-page header."

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow
  alias MediaCentarr.Acquisition.ViewModels.Target

  @enforce_keys [:id, :title, :state, :target]
  defstruct [:id, :title, :state, :target, :criteria_summary]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: PursuitRow.state(),
          target: Target.t(),
          criteria_summary: String.t() | nil
        }
end
```

- [ ] **Step 2: Update the component**

Edit `lib/media_centarr_web/components/acquisition/pursuit_header.ex`. Replace the file with:

```elixir
defmodule MediaCentarrWeb.Components.Acquisition.PursuitHeader do
  @moduledoc "Identity card for `/download/:pursuit_id` — title, state, target, criteria."

  use Phoenix.Component

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

  attr :vm, PursuitHeader, required: true

  def pursuit_header(assigns) do
    ~H"""
    <header class="glass-surface rounded-xl p-5 space-y-2">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-lg font-medium truncate">{@vm.title}</h2>
        <PursuitStyle.state_badge state={@vm.state} />
      </div>

      <div :if={target_summary(@vm.target)} class="text-xs text-base-content/70">
        {target_summary(@vm.target)}
      </div>

      <div :if={@vm.criteria_summary} class="text-xs text-base-content/60">
        Criteria: {@vm.criteria_summary}
      </div>
    </header>
    """
  end

  defp target_summary(%{tmdb_type: "movie", year: nil}), do: "Movie"
  defp target_summary(%{tmdb_type: "movie", year: y}), do: "Movie • #{y}"
  defp target_summary(%{tmdb_type: "tv", season_number: nil}), do: "TV"

  defp target_summary(%{tmdb_type: "tv", season_number: s, episode_number: nil}),
    do: "TV • S#{pad(s)}"

  defp target_summary(%{tmdb_type: "tv", season_number: s, episode_number: e}),
    do: "TV • S#{pad(s)}E#{pad(e)}"

  defp target_summary(%{tmdb_type: type}), do: type
  defp target_summary(_), do: nil

  defp pad(n) when is_integer(n) and n < 10, do: "0#{n}"
  defp pad(n) when is_integer(n), do: "#{n}"
end
```

- [ ] **Step 3: Update `Pursuits.header_for/1` to populate the new shape**

Edit `lib/media_centarr/acquisition/pursuits.ex`. Replace `build_header/1` with:

```elixir
defp build_header(%Pursuit{} = pursuit) do
  %PursuitHeader{
    id: pursuit.id,
    title: pursuit.title,
    state: String.to_existing_atom(pursuit.state),
    target: build_target(pursuit),
    criteria_summary: summarize_criteria(pursuit.criteria)
  }
end
```

- [ ] **Step 4: Update the storybook story**

Replace `storybook/acquisition/pursuit_header.story.exs`:

```elixir
defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitHeader do
  @moduledoc "Identity header for `/download/:pursuit_id`."

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader
  alias MediaCentarr.Acquisition.ViewModels.Target

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitHeader.pursuit_header/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :movie_with_year,
        description: "Movie pursuit with year and 1080–4K criteria",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-movie",
            title: "Public Domain Feature 1925",
            state: :active,
            target: %Target{tmdb_type: "movie", tmdb_id: "1", year: 1925},
            criteria_summary: "max_quality: 2160p, min_quality: 1080p"
          }
        }
      },
      %Variation{
        id: :tv_episode,
        description: "TV episode pursuit",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-tv",
            title: "Sample Show S01E03",
            state: :active,
            target: %Target{tmdb_type: "tv", tmdb_id: "10", season_number: 1, episode_number: 3},
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :needs_decision,
        description: "Pursuit in needs_decision",
        attributes: %{
          vm: %PursuitHeader{
            id: "story-decision",
            title: "Sample Show S01E04",
            state: :needs_decision,
            target: %Target{tmdb_type: "tv", season_number: 1, episode_number: 4},
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :terminal_satisfied,
        attributes: %{
          vm: %PursuitHeader{
            id: "story-satisfied",
            title: "Movie A",
            state: :satisfied,
            target: %Target{tmdb_type: "movie", year: 2023},
            criteria_summary: nil
          }
        }
      },
      %Variation{
        id: :terminal_exhausted,
        attributes: %{
          vm: %PursuitHeader{
            id: "story-exhausted",
            title: "Movie B",
            state: :exhausted,
            target: %Target{tmdb_type: "movie"},
            criteria_summary: nil
          }
        }
      }
    ]
  end
end
```

- [ ] **Step 5: Compile + storybook smoke**

Run: `mix compile --warnings-as-errors`
Expected: clean.

Run: `mix test test/media_centarr_web/storybook_test.exs`
Expected: green — every variation renders without crashing.

- [ ] **Step 6: Run the broader test suite to catch other consumers**

Run: `mix test test/media_centarr/acquisition/ test/media_centarr_web/`
Expected: any test that constructed the old `PursuitHeader` struct directly will fail; fix those imports/constructions to use the new shape. There should be at most a handful (search for `%PursuitHeader{`).

- [ ] **Step 7: Commit**

```bash
jj describe -m "refactor(acquisition): slim PursuitHeader to identity-only (title/state/target/criteria)"
jj new
```

---

## Task 8: New `PursuitActivity` component + storybook stories

**Files:**
- Create: `lib/media_centarr_web/components/acquisition/pursuit_activity.ex`
- Create: `storybook/acquisition/pursuit_activity.story.exs`

Storybook stories ship FIRST (project rule). For this task: build the component and its stories side-by-side and verify in storybook before wiring it into the LiveView (Task 9).

- [ ] **Step 1: Implement the component**

Create `lib/media_centarr_web/components/acquisition/pursuit_activity.ex`:

```elixir
defmodule MediaCentarrWeb.Components.Acquisition.PursuitActivity do
  @moduledoc """
  Live status card for the pursuit detail page.

  Renders the current_action verb + description, an optional download
  progress bar, the next_step sentence, manual action buttons (driven by
  `vm.available_actions`), and a staleness footnote.
  """

  use Phoenix.Component

  import MediaCentarrWeb.CoreComponents, only: [button: 1]

  alias MediaCentarr.Acquisition.ViewModels.PursuitStatus

  attr :vm, PursuitStatus, required: true
  attr :on_cancel, :string, default: nil
  attr :on_re_search, :string, default: nil
  attr :on_request_decision, :string, default: nil

  def pursuit_activity(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4">
      <div class="space-y-1">
        <div class={"text-base font-medium #{severity_class(@vm.current_action.severity)}"}>
          {@vm.current_action.verb}
        </div>
        <div class="text-sm text-base-content/80">{@vm.current_action.description}</div>
      </div>

      <div :if={@vm.download && @vm.download.progress_pct} class="space-y-1">
        <div class="h-2 rounded-full bg-base-content/10 overflow-hidden">
          <div
            class="h-full bg-primary transition-all duration-300"
            style={"width: #{progress_width(@vm.download.progress_pct)}%"}
          />
        </div>
      </div>

      <div :if={@vm.next_step} class="text-xs text-base-content/60">
        Next: {@vm.next_step.description}
      </div>

      <div :if={@vm.available_actions != []} class="flex flex-wrap gap-2 justify-end pt-1">
        <.button
          :if={:re_search in @vm.available_actions and @on_re_search}
          variant="ghost"
          size="sm"
          phx-click={@on_re_search}
        >
          Re-search
        </.button>
        <.button
          :if={:request_decision in @vm.available_actions and @on_request_decision}
          variant="ghost"
          size="sm"
          phx-click={@on_request_decision}
        >
          Pick a different release
        </.button>
        <.button
          :if={:cancel in @vm.available_actions and @on_cancel}
          variant="dismiss"
          size="sm"
          phx-click={@on_cancel}
        >
          Cancel pursuit
        </.button>
      </div>

      <div :if={staleness_message(@vm)} class={"text-xs #{staleness_class(@vm.staleness)}"}>
        {staleness_message(@vm)}
      </div>
    </section>
    """
  end

  defp severity_class(:success), do: "text-success"
  defp severity_class(:warning), do: "text-warning"
  defp severity_class(:error), do: "text-error"
  defp severity_class(_), do: "text-base-content"

  defp staleness_class(:very_stale), do: "text-error"
  defp staleness_class(:stale), do: "text-warning"
  defp staleness_class(_), do: "text-base-content/40"

  defp staleness_message(%{staleness: :fresh}), do: nil
  defp staleness_message(%{last_activity_at: nil}), do: nil

  defp staleness_message(%{last_activity_at: ts}) do
    "Last activity: #{relative_time(ts)}"
  end

  defp relative_time(%DateTime{} = ts) do
    diff_seconds = DateTime.diff(DateTime.utc_now(:second), ts)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86_400)}d ago"
    end
  end

  defp progress_width(pct) when is_number(pct), do: max(0, min(100, round(pct)))
end
```

- [ ] **Step 2: Create the storybook stories**

Create `storybook/acquisition/pursuit_activity.story.exs`:

```elixir
defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitActivity do
  @moduledoc "Live status card for `/download/:pursuit_id`."

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep,
    PursuitStatus,
    Target
  }

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitActivity.pursuit_activity/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  defp base(overrides) do
    base = %PursuitStatus{
      pursuit_id: "story-pursuit",
      title: "Sample Movie",
      state: :active,
      origin: :auto,
      target: %Target{tmdb_type: "movie"},
      current_action: %CurrentAction{
        verb: "Downloading",
        description: "Sample description.",
        severity: :info
      },
      available_actions: [:cancel],
      staleness: :fresh
    }

    struct(base, overrides)
  end

  def variations do
    [
      %Variation{
        id: :downloading_healthy,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Downloading",
                description: "From qBittorrent • 42% • ETA 8m",
                severity: :info
              },
              download: %DownloadProgress{
                state: :downloading,
                progress_pct: 42.0,
                client: "qBittorrent",
                eta: "8m"
              },
              next_step: %NextStep{description: "When complete, the file watcher matches the title."}
            ),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :downloading_stalled,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Stalled",
                description: "Download client can't make progress.",
                severity: :warning
              },
              download: %DownloadProgress{state: :stalled, progress_pct: 12.0},
              next_step: %NextStep{description: "Re-search for a different release, or wait."},
              available_actions: [:cancel, :re_search, :request_decision]
            ),
          on_cancel: "noop",
          on_re_search: "noop",
          on_request_decision: "noop"
        }
      },
      %Variation{
        id: :downloading_paused,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Paused",
                description: "Paused at the download client.",
                severity: :info
              },
              download: %DownloadProgress{state: :paused, progress_pct: 67.0},
              next_step: %NextStep{description: "Resume it in your download client."}
            ),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :queued_at_client,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Queued",
                description: "Waiting for a slot at the download client.",
                severity: :info
              },
              download: %DownloadProgress{state: :queued},
              next_step: %NextStep{description: "Will start when a slot frees up."}
            ),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :searching_prowlarr,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Searching",
                description: "Looking for an acceptable release (attempt 2).",
                severity: :info
              },
              next_step: %NextStep{description: "Trying expanded queries — will pick the best match or snooze."}
            ),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :snoozed,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Snoozed",
                description: "Waiting before the next search attempt.",
                severity: :info
              },
              next_step: %NextStep{description: "Will resume automatically."},
              available_actions: [:cancel, :re_search, :request_decision],
              staleness: :stale,
              last_activity_at: DateTime.add(DateTime.utc_now(:second), -3 * 3600, :second)
            ),
          on_cancel: "noop",
          on_re_search: "noop",
          on_request_decision: "noop"
        }
      },
      %Variation{
        id: :waiting_for_file,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Waiting",
                description: "Not visible in your download client.",
                severity: :info
              },
              next_step: %NextStep{
                description: "Either it completed and is being matched, or it never reached the client."
              },
              available_actions: [:cancel, :re_search],
              staleness: :very_stale,
              last_activity_at: DateTime.add(DateTime.utc_now(:second), -2 * 86_400, :second)
            ),
          on_cancel: "noop",
          on_re_search: "noop"
        }
      },
      %Variation{
        id: :download_complete_unmatched,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Verifying",
                description: "Download finished — waiting for the file to be matched.",
                severity: :info
              },
              download: %DownloadProgress{state: :completed, progress_pct: 100.0},
              next_step: %NextStep{description: "InboundListener picks it up next."}
            ),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :needs_decision,
        attributes: %{
          vm:
            base(
              state: :needs_decision,
              current_action: %CurrentAction{
                verb: "Decision needed",
                description: "Pick a release below.",
                severity: :warning
              },
              next_step: %NextStep{description: "Use the decision card below to pick or skip."}
            ),
          on_cancel: "noop"
        }
      },
      %Variation{
        id: :terminal_satisfied,
        attributes: %{
          vm:
            base(
              state: :satisfied,
              current_action: %CurrentAction{
                verb: "Done",
                description: "File landed and identity verified.",
                severity: :success
              },
              next_step: nil,
              available_actions: []
            )
        }
      },
      %Variation{
        id: :terminal_exhausted,
        attributes: %{
          vm:
            base(
              state: :exhausted,
              current_action: %CurrentAction{
                verb: "Gave up",
                description: "Exhausted after 12 attempts.",
                severity: :error
              },
              next_step: %NextStep{description: "Start a new pursuit if you still want this."},
              available_actions: []
            )
        }
      },
      %Variation{
        id: :terminal_cancelled,
        attributes: %{
          vm:
            base(
              state: :cancelled,
              current_action: %CurrentAction{
                verb: "Cancelled",
                description: "Pursuit cancelled.",
                severity: :info
              },
              next_step: nil,
              available_actions: []
            )
        }
      }
    ]
  end
end
```

- [ ] **Step 3: Run storybook tests**

Run: `mix test test/media_centarr_web/storybook_test.exs`
Expected: every variation renders without crashing.

- [ ] **Step 4: Compile check**

Run: `mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(acquisition): add PursuitActivity component + storybook stories"
jj new
```

---

## Task 9: Rename `PursuitTimeline` heading

**Files:**
- Modify: `lib/media_centarr_web/components/acquisition/pursuit_timeline.ex`
- Modify: `storybook/acquisition/timeline.story.exs` (only if it asserts the heading text)

- [ ] **Step 1: Update the heading**

Edit `lib/media_centarr_web/components/acquisition/pursuit_timeline.ex`. Change the heading line:

```elixir
<h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50 mb-3">History</h3>
```

(was "Timeline".)

- [ ] **Step 2: Storybook smoke**

Run: `mix test test/media_centarr_web/storybook_test.exs`
Expected: green.

- [ ] **Step 3: Commit**

```bash
jj describe -m "refactor(acquisition): rename Timeline section heading to History"
jj new
```

---

## Task 10: Rewire `PursuitLive`

**Files:**
- Modify: `lib/media_centarr_web/live/pursuit_live.ex`

Replace the LiveView to use `Pursuits.status_for/1`, subscribe to queue snapshots, and add re-search + request-decision handlers.

- [ ] **Step 1: Replace `pursuit_live.ex`**

Replace the file with:

```elixir
defmodule MediaCentarrWeb.PursuitLive do
  @moduledoc """
  Detail page for a single pursuit at `/download/:pursuit_id`.

  Subscribes to `acquisition:updates` and `acquisition:queue` so the
  status panel refreshes on both pursuit events and queue snapshots.
  Every refresh recomputes via `Pursuits.status_for/1`.
  """

  use MediaCentarrWeb, :live_view

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{CancelReasons, Pursuits}
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Pursuits.Commands.{Cancel, RecordUserChoice, ReSearch, RequestDecision}
  alias MediaCentarr.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentarr.Acquisition.ViewModels
  alias MediaCentarr.Acquisition.ViewModels.Alternative
  alias MediaCentarrWeb.Components.Acquisition.DecisionCard, as: DecisionCardComponent
  alias MediaCentarrWeb.Components.Acquisition.{PursuitActivity, PursuitHeader, PursuitTimeline}
  alias MediaCentarrWeb.Layouts

  @decision_prompt "Pick an alternative release."

  @impl true
  def mount(%{"pursuit_id" => id}, _session, socket) do
    if connected?(socket) do
      Acquisition.subscribe()
      Acquisition.subscribe_queue()
    end

    socket =
      socket
      |> assign(pursuit_id: id)
      |> load_state()

    {:ok, socket}
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/download">
      <div class="max-w-2xl mx-auto py-8 text-center text-base-content/60">
        Pursuit not found.
        <.link navigate="/download" class="link link-primary ml-2">Back to Downloads</.link>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/download">
      <div class="max-w-2xl mx-auto space-y-4 py-6">
        <div>
          <.link navigate="/download" class="text-xs text-base-content/60 hover:text-base-content">
            ← Back to Downloads
          </.link>
        </div>

        <PursuitHeader.pursuit_header vm={@header} />

        <PursuitActivity.pursuit_activity
          vm={@status}
          on_cancel="cancel_pursuit"
          on_re_search="re_search"
          on_request_decision="request_decision"
        />

        <DecisionCardComponent.decision_card :if={@decision_card} vm={@decision_card} />

        <PursuitTimeline.timeline vm={@timeline} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("cancel_pursuit", _params, socket) do
    case Cancel.execute(%{
           pursuit_id: socket.assigns.pursuit_id,
           cancelled_by: :user,
           reason: CancelReasons.user_request()
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Pursuit cancelled.") |> load_state()}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit cancel failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not cancel pursuit.")}
    end
  end

  def handle_event("re_search", _params, socket) do
    case ReSearch.execute(%{pursuit_id: socket.assigns.pursuit_id}) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Re-searching now…") |> load_state()}

      {:error, :not_eligible} ->
        {:noreply, put_flash(socket, :error, "This pursuit can't be re-searched right now.")}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit re-search failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not re-search this pursuit.")}
    end
  end

  def handle_event("request_decision", _params, socket) do
    case RequestDecision.execute(%{
           pursuit_id: socket.assigns.pursuit_id,
           prompt: @decision_prompt
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Pick a release below.") |> load_state()}

      {:error, reason} ->
        Log.warning(:acquisition, "request decision failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not switch to decision mode.")}
    end
  end

  def handle_event(
        "pick_alternative",
        %{"pursuit-id" => pursuit_id, "guid" => guid, "label" => label},
        socket
      ) do
    case RecordUserChoice.execute(%{
           pursuit_id: pursuit_id,
           chosen_guid: guid,
           choice_label: label
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Trying alternative…") |> load_state()}

      {:error, reason} ->
        Log.warning(:acquisition, "record user choice failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not pick that alternative.")}
    end
  end

  @impl true
  def handle_info({:queue_state, _queue}, socket), do: {:noreply, load_state(socket)}

  def handle_info(%struct{pursuit_id: pid}, %{assigns: %{pursuit_id: pid}} = socket) do
    if PursuitEvents.event?(struct) do
      {:noreply, load_state(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- private ---------------------------------------------------------------

  defp load_state(socket) do
    case Pursuits.get(socket.assigns.pursuit_id) do
      {:ok, %Pursuit{} = pursuit} ->
        {:ok, header} = Pursuits.header_for(pursuit.id)
        {:ok, status} = Pursuits.status_for(pursuit.id)
        timeline = Pursuits.timeline_for(pursuit.id)
        decision_card = build_decision_card(pursuit)

        socket
        |> assign(:pursuit, pursuit)
        |> assign(:header, header)
        |> assign(:status, status)
        |> assign(:timeline, timeline)
        |> assign(:decision_card, decision_card)
        |> assign(:not_found?, false)

      {:error, :not_found} ->
        assign(socket, :not_found?, true)
    end
  end

  defp build_decision_card(%Pursuit{state: "needs_decision"} = pursuit) do
    %ViewModels.DecisionCard{
      pursuit_id: pursuit.id,
      prompt: @decision_prompt,
      alternatives: fetch_alternatives(pursuit),
      loading?: false
    }
  end

  defp build_decision_card(_pursuit), do: nil

  defp fetch_alternatives(%Pursuit{} = pursuit) do
    opts =
      []
      |> put_when_present(:type, search_type_for(pursuit.tmdb_type))
      |> put_when_present(:year, pursuit.year)

    case Acquisition.search(pursuit.title, opts) do
      {:ok, results} ->
        excluded = MapSet.new(pursuit.tried_release_guids)

        results
        |> Enum.reject(fn r -> MapSet.member?(excluded, r.guid) end)
        |> Enum.take(8)
        |> Enum.map(&search_result_to_alternative/1)

      {:error, _reason} ->
        []
    end
  end

  defp search_type_for("tv"), do: :tv
  defp search_type_for("movie"), do: :movie
  defp search_type_for(_), do: nil

  defp put_when_present(opts, _key, nil), do: opts
  defp put_when_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp search_result_to_alternative(result) do
    %Alternative{
      guid: result.guid,
      title: result.title,
      indexer: indexer_name(result),
      quality: quality_label(result),
      size_bytes: Map.get(result, :size_bytes),
      seeders: Map.get(result, :seeders),
      indexer_id: Map.get(result, :indexer_id)
    }
  end

  defp indexer_name(%{indexer: indexer}) when is_binary(indexer), do: indexer
  defp indexer_name(_), do: "Unknown"

  defp quality_label(%{quality: q}) when is_atom(q), do: MediaCentarr.Acquisition.Quality.label(q)
  defp quality_label(_), do: nil
end
```

- [ ] **Step 2: Compile check**

Run: `mix compile --warnings-as-errors`
Expected: clean. If `RequestDecision` isn't currently exported from the Acquisition boundary, add it to the exports list in `lib/media_centarr/acquisition.ex`.

- [ ] **Step 3: Smoke test the page**

Run: `mix test test/media_centarr_web/page_smoke_test.exs`
Expected: existing smoke test for `/download` still passes; the `/download/:id` mount path isn't covered by `page_smoke_test.exs` directly but we'll add a smoke test next.

- [ ] **Step 4: Commit**

```bash
jj describe -m "refactor(pursuit_live): rewire to use Pursuits.status_for/1 + queue subscriptions"
jj new
```

---

## Task 11: PursuitLive smoke + handler tests

**Files:**
- Create: `test/media_centarr_web/live/pursuit_live_test.exs` (if absent)

- [ ] **Step 1: Check whether the test file exists**

Run: `test -f test/media_centarr_web/live/pursuit_live_test.exs && echo exists || echo create`
Expected output: `create`. If it shows `exists`, open the file and append the tests below.

- [ ] **Step 2: Write the tests**

Create `test/media_centarr_web/live/pursuit_live_test.exs`:

```elixir
defmodule MediaCentarrWeb.PursuitLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Downloads.QueueState
  alias MediaCentarr.Repo

  @queue_cache_key {MediaCentarr.Downloads.QueueMonitor, :state}

  setup do
    on_exit(fn -> :persistent_term.put(@queue_cache_key, %QueueState{items: []}) end)
    :persistent_term.put(@queue_cache_key, %QueueState{items: []})
    :ok
  end

  describe "rendering across states" do
    test "renders for an Active pursuit with a snoozed grab", %{conn: conn} do
      pursuit = create_pursuit(%{state: "active", title: "Sample Movie"})
      _grab = create_grab(%{pursuit_id: pursuit.id, status: "snoozed", title: pursuit.title})

      {:ok, _view, html} = live(conn, "/download/#{pursuit.id}")

      assert html =~ "Snoozed"
      assert html =~ "Re-search"
    end

    test "renders Done for a satisfied pursuit", %{conn: conn} do
      pursuit = create_pursuit(%{state: "satisfied", title: "Sample Movie"})
      _grab = create_grab(%{pursuit_id: pursuit.id, status: "grabbed", title: pursuit.title})

      {:ok, _view, html} = live(conn, "/download/#{pursuit.id}")

      assert html =~ "Done"
      refute html =~ "Cancel pursuit"
    end

    test "renders Not found for unknown id", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/download/#{Ecto.UUID.generate()}")
      assert html =~ "Pursuit not found"
    end
  end

  describe "manual triggers" do
    test "Cancel pursuit transitions the pursuit to cancelled", %{conn: conn} do
      pursuit = create_pursuit(%{state: "active", title: "Sample Movie"})
      _grab = create_grab(%{pursuit_id: pursuit.id, status: "snoozed", title: pursuit.title})

      {:ok, view, _html} = live(conn, "/download/#{pursuit.id}")
      render_click(view, "cancel_pursuit", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "cancelled"
    end

    test "Re-search records the pursuit_re_searched event", %{conn: conn} do
      pursuit = create_pursuit(%{state: "active", title: "Sample Movie"})
      _grab = create_grab(%{pursuit_id: pursuit.id, status: "snoozed", title: pursuit.title})

      {:ok, view, _html} = live(conn, "/download/#{pursuit.id}")
      render_click(view, "re_search", %{})

      assert Repo.get_by(Event, pursuit_id: pursuit.id, kind: "pursuit_re_searched")
    end

    test "Request decision flips the pursuit to needs_decision", %{conn: conn} do
      pursuit = create_pursuit(%{state: "active", title: "Sample Movie"})
      _grab = create_grab(%{pursuit_id: pursuit.id, status: "snoozed", title: pursuit.title})

      {:ok, view, _html} = live(conn, "/download/#{pursuit.id}")
      render_click(view, "request_decision", %{})

      reloaded = Repo.reload(pursuit)
      assert reloaded.state == "needs_decision"
    end
  end
end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/media_centarr_web/live/pursuit_live_test.exs`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
jj describe -m "test(pursuit_live): cover state rendering + manual triggers"
jj new
```

---

## Task 12: Precommit gauntlet + manual smoke

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: zero warnings, all checks green. Fix anything reported, re-run.

- [ ] **Step 2: Manual smoke in dev**

In an existing `iex --name repl@127.0.0.1 --remsh media_centarr_dev@127.0.0.1` session, recompile:

```
iex> recompile()
```

Navigate to a real `/download/:id` URL in the browser. Verify:
- Header shows title + state badge + target line (Movie/TV) + criteria (if any).
- Activity card shows current action + next step + buttons appropriate to state.
- Timeline still renders, now labeled "History".
- For a snoozed/abandoned pursuit, Re-search and Pick-a-different-release buttons appear.

- [ ] **Step 3: Final commit if anything was tidied**

```bash
jj describe -m "chore: precommit cleanup for pursuit detail redesign"
jj new
```

(If nothing changed, skip this step.)

---

## Self-Review

**Spec coverage:**

- Goals 1–4 (live status, next step, manual triggers, history preserved) — covered by Tasks 7, 8, 9, 10.
- Goal 5 (storybook-first) — Tasks 7 + 8 ship stories alongside components.
- Non-Goal: not changing the Downloads list — confirmed; no edits planned for `/download` rows.
- `PursuitStatus` ViewModel — Tasks 1 + 2.
- `PursuitStatus.derive/3` truth table — Task 2.
- `Pursuits.status_for/1` — Task 6.
- `Pursuits.Commands.ReSearch` — Task 5.
- `Acquisition.force_search_now/1` helper — Task 4.
- `pursuit_re_searched` event — Task 3.
- `PursuitHeader` refactor — Task 7.
- `PursuitActivity` component — Task 8.
- `PursuitTimeline` heading rename — Task 9.
- LiveView rewire — Task 10.
- Tests — Tasks 2 / 4 / 5 / 6 / 11.

**Placeholder scan:** every step contains concrete code or commands. No "TBD" / "TODO" / "similar to" references.

**Type consistency:** `PursuitStatus.t/0` definition in Task 2 matches the struct accesses in `Pursuits.status_for/1` (Task 6) and `PursuitActivity` (Task 8). `DownloadProgress.progress_pct` is a float across all uses. `available_actions` uses `[:cancel, :re_search, :request_decision]` consistently.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-11-pursuit-detail-redesign.md`.

Per the user's preference ("trust your instincts, get this online so I can use it"), I'll execute inline rather than offering a choice — using the `superpowers:executing-plans` skill, batching checkpoints at sensible boundaries (after Task 5 commands; after Task 8 component+stories; after Task 11 tests; after Task 12 precommit).
