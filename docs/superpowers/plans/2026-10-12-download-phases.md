# Download phases and the one download strip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every surface on Incoming draws a download-client job as its phase on a short protocol-specific ladder, from one `download_strip/1` component, so the NZB-fetch and post-processing states stop rendering as text dumps.

**Architecture:** `MediaCentaur.Downloads.Phase` is a pure projection of a `QueueItem` into `{ladder, current, condition, figure}`; `DownloadProgress` carries it; one component (`Components.Acquisition.DownloadStrip`) draws it; the pursuit row, the orphan row and the pursuit modal's activity card compose from that component and draw no bar or state word of their own. The SABnzbd driver supplies the three facts the projection needs that it dropped before: the post-processing stage line, a nil instead of the zero clock, and a placeholder name for a job still fetching its NZB.

**Tech Stack:** Elixir/Phoenix LiveView, Phoenix Storybook, Tailwind v4, ExUnit. Spec: `docs/superpowers/specs/2026-10-12-download-phases-design.md`. Plan 2 (app-owned grabs, identity at grab) follows this plan and is written separately.

**House rules that apply:** run `mix` only as `~/scripts/agents/agent-mix` (CLAUDE.md); test-first; placeholders in test content, never real titles; every public function component gets a story (MC0009); status labels are plain colored text, never a badge; animate only `transform`/`opacity`.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur/downloads/queue_item.ex` (modify) | Driver facts: `stage_line` from SABnzbd history, zero clock → nil, placeholder name for a Grabbing slot |
| `lib/media_centaur/downloads/phase.ex` (create) | The phase projection: ladder, current step, condition, figure, word, text class |
| `lib/media_centaur/acquisition/view_models/download_progress.ex` (modify) | Gains `phase` |
| `lib/media_centaur/acquisition/queue_matcher.ex` (modify) | `to_download/1` fills `phase` |
| `lib/media_centaur_web/components/acquisition/cell_vocabulary.ex` (modify) | Gains `:underway` — the step under way on a ladder |
| `lib/media_centaur_web/components/acquisition/download_strip.ex` (create) | The one drawing of a job |
| `assets/css/app.css` (modify) | `.progress-indeterminate` |
| `storybook/acquisition/download_strip.story.exs` (create), `_acquisition.index.exs` (modify) | Story: one variation per phase per protocol plus conditions |
| `lib/media_centaur_web/components/acquisition/pursuit_row.ex` (modify) | Footer becomes the strip |
| `lib/media_centaur_web/live/incoming_live/orphan_queue.ex` (modify) | Row becomes the strip; copy |
| `lib/media_centaur_web/live/incoming_live/logic.ex` (modify) | `state_label/1`, `state_badge_variant/1`, `state_text_class/1` removed (Phase owns the words) |
| `lib/media_centaur_web/components/acquisition/pursuit_activity.ex` (modify) | Download block becomes the strip |
| `lib/media_centaur/acquisition/view_models/pursuit_status.ex` (modify) | Post-processing sentence carries the figure |
| Tests | `test/media_centaur/downloads/queue_item_test.exs`, `test/media_centaur/downloads/phase_test.exs` (create), `test/media_centaur/acquisition/queue_matcher_test.exs`, `test/media_centaur_web/components/acquisition/cell_vocabulary_test.exs`, `test/media_centaur_web/components/acquisition/download_strip_test.exs` (create), `test/media_centaur_web/live/incoming_live/logic_test.exs`, `test/media_centaur_web/live/incoming_live_test.exs`, `test/media_centaur/acquisition/view_models/pursuit_status_test.exs` |

Branch: `git switch -c download-phases` from `main` before Task 1.

---

### Task 1: SABnzbd driver facts

**Files:**
- Modify: `lib/media_centaur/downloads/queue_item.ex`
- Test: `test/media_centaur/downloads/queue_item_test.exs`

- [ ] **Step 1: Write the failing tests**

Add inside `describe "from_sabnzbd_queue/1"` (after the `Grabbing` test at line 221):

```elixir
    test "a Grabbing slot is named by its URL (API key included) — substitute the placeholder, never show the URL" do
      raw = %{
        "nzo_id" => "nzo_grab",
        "filename" => "Trying to fetch NZB from https://indexer.example/api?t=get&id=abc&apikey=SECRET",
        "status" => "Grabbing",
        "mb" => "0.00",
        "mbleft" => "0.00",
        "percentage" => "0",
        "timeleft" => "0:00:00"
      }

      item = QueueItem.from_sabnzbd_queue(raw)

      assert item.state == :fetching_nzb
      assert item.title == "Fetching NZB…"
      refute item.normalized_title =~ "secret"
    end

    test "the zero clock is not an ETA" do
      raw = %{
        "nzo_id" => "nzo_zero",
        "filename" => "Sample.Show.S01E02.1080p.WEB-DL",
        "status" => "Queued",
        "mb" => "100.00",
        "mbleft" => "100.00",
        "percentage" => "0",
        "timeleft" => "0:00:00"
      }

      assert QueueItem.from_sabnzbd_queue(raw).timeleft == nil
    end

    test "live queue slots carry no stage line" do
      raw = %{
        "nzo_id" => "nzo_live",
        "filename" => "Sample.Show.S01E02.1080p.WEB-DL",
        "status" => "Downloading",
        "mb" => "100.00",
        "mbleft" => "50.00",
        "percentage" => "50",
        "timeleft" => "0:01:00"
      }

      assert QueueItem.from_sabnzbd_queue(raw).stage_line == nil
    end
```

Add inside `describe "from_sabnzbd_history/1"`:

```elixir
    test "a post-processing entry carries SABnzbd's stage line; a blank one is nil" do
      unpacking = base_sab_history(%{"status" => "Extracting", "action_line" => "Unpacking: 45%"})
      assert QueueItem.from_sabnzbd_history(unpacking).stage_line == "Unpacking: 45%"

      done = base_sab_history(%{"status" => "Completed", "action_line" => ""})
      assert QueueItem.from_sabnzbd_history(done).stage_line == nil

      absent = base_sab_history(%{"status" => "Verifying"})
      assert QueueItem.from_sabnzbd_history(absent).stage_line == nil
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/queue_item_test.exs`
Expected: 4 failures — `title` is the URL, `timeleft` is `"0:00:00"`, and `stage_line` is not a key of `QueueItem`.

- [ ] **Step 3: Implement**

In `lib/media_centaur/downloads/queue_item.ex`:

Add to the `defstruct` list, after `:normalized_title`:

```elixir
    # SABnzbd's `action_line` on a history slot — the live text of the
    # post-processing stage ("Unpacking: 45%", "Verifying: 12/56"). Nil for
    # live-queue slots, torrents, and completed jobs (SABnzbd blanks it).
    # `Downloads.Phase` parses the figure out of it.
    :stage_line
```

Add to `@type t`: `stage_line: String.t() | nil`.

Replace the first lines of `from_sabnzbd_queue/1`:

```elixir
  def from_sabnzbd_queue(raw) when is_map(raw) do
    title = title_from_sabnzbd(raw["filename"], raw["status"])

    %__MODULE__{
      id: raw["nzo_id"],
      title: title,
      status: raw["status"],
      state: state_from_sabnzbd_queue(raw["status"]),
      protocol: :usenet,
      download_client: "SABnzbd",
      indexer: blank_to_nil(raw["cat"]),
      size: megabytes_to_bytes(raw["mb"]),
      size_left: megabytes_to_bytes(raw["mbleft"]),
      progress: parse_progress_percent(raw["percentage"]),
      timeleft: timeleft_from_sabnzbd(raw["timeleft"]),
      normalized_title: normalize_title(title)
    }
  end
```

In `from_sabnzbd_history/1` add `stage_line: blank_to_nil(raw["action_line"]),` after `content_path:`.

Add the private helpers next to `title_from_qbittorrent/2`:

```elixir
  # While SABnzbd is fetching the NZB it names the slot after the URL it is
  # fetching — "Trying to fetch NZB from https://…&apikey=…". That is an
  # unnamed job: the URL is meaningless as a title and carries the indexer
  # key, so it never reaches a view-model. Same placeholder rule as a
  # qBittorrent torrent before its metadata arrives.
  defp title_from_sabnzbd(_filename, "Grabbing"), do: "Fetching NZB…"
  defp title_from_sabnzbd(filename, _status) when is_binary(filename), do: filename
  defp title_from_sabnzbd(_filename, _status), do: ""

  # SABnzbd reports "0:00:00" for a job with nothing to estimate (grabbing,
  # queued, paused). A zero clock is the absence of an ETA, not an ETA.
  defp timeleft_from_sabnzbd("0:00:00"), do: nil
  defp timeleft_from_sabnzbd(value), do: blank_to_nil(value)
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/queue_item_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/downloads/queue_item.ex test/media_centaur/downloads/queue_item_test.exs
git commit -m "feat(downloads): SABnzbd stage line, zero-clock ETA, placeholder name for a fetching job"
```

---

### Task 2: The phase projection

**Files:**
- Create: `lib/media_centaur/downloads/phase.ex`
- Test: `test/media_centaur/downloads/phase_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.Downloads.PhaseTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Downloads.{Phase, QueueItem}

  defp usenet(state, overrides \\ %{}) do
    struct!(
      %QueueItem{id: "nzo", title: "Sample.Show", state: state, protocol: :usenet, status: nil},
      overrides
    )
  end

  defp torrent(state, overrides \\ %{}) do
    struct!(
      %QueueItem{id: "hash", title: "Sample.Show", state: state, protocol: :torrent, status: nil},
      overrides
    )
  end

  describe "of/1 — usenet ladder" do
    test "fetching the NZB is the first step, with no figure" do
      phase = Phase.of(usenet(:fetching_nzb, %{progress: 19.0}))

      assert phase.ladder == [:fetch, :download, :verify, :unpack, :move, :done]
      assert phase.current == :fetch
      assert phase.condition == nil
      assert phase.figure == nil
    end

    test "downloading carries the client's percentage as a 0..1 figure" do
      phase = Phase.of(usenet(:downloading, %{progress: 42.0}))

      assert phase.current == :download
      assert phase.figure == 0.42
    end

    test "post-processing steps read their figure from the stage line" do
      assert %{current: :verify, figure: figure} =
               Phase.of(usenet(:verifying, %{stage_line: "Verifying: 14/56"}))

      assert_in_delta figure, 0.25, 0.001

      assert %{current: :unpack, figure: 0.45} =
               Phase.of(usenet(:extracting, %{stage_line: "Unpacking: 45%"}))

      assert %{current: :move, figure: nil} = Phase.of(usenet(:moving, %{stage_line: nil}))
    end

    test "repair appears on the ladder only while it is happening" do
      phase = Phase.of(usenet(:repairing, %{stage_line: "Repairing: 12%"}))

      assert phase.ladder == [:fetch, :download, :verify, :repair, :unpack, :move, :done]
      assert phase.current == :repair
      assert phase.figure == 0.12
    end

    test "completed is done with a full figure" do
      assert %{current: :done, figure: 1.0} = Phase.of(usenet(:completed, %{progress: 100.0}))
    end

    test "queued and paused are conditions on the download step" do
      assert %{current: :download, condition: :queued} = Phase.of(usenet(:queued))
      assert %{current: :download, condition: :paused, figure: 0.5} =
               Phase.of(usenet(:paused, %{progress: 50.0}))
    end

    test "a failed job has no position and the failed condition" do
      assert %{current: nil, condition: :failed, figure: nil} = Phase.of(usenet(:error))
    end
  end

  describe "of/1 — torrent ladder" do
    test "metadata fetch is the first step, read from the raw status" do
      phase = Phase.of(torrent(:downloading, %{status: "metaDL", progress: 0.0}))

      assert phase.ladder == [:metadata, :download, :done]
      assert phase.current == :metadata
      assert phase.figure == nil
    end

    test "downloading, stalled, queued, paused, done" do
      assert %{current: :download, condition: nil, figure: 0.5} =
               Phase.of(torrent(:downloading, %{status: "downloading", progress: 50.0}))

      assert %{current: :download, condition: :stalled} = Phase.of(torrent(:stalled))
      assert %{current: :download, condition: :queued} = Phase.of(torrent(:queued))
      assert %{current: :download, condition: :paused} = Phase.of(torrent(:paused))
      assert %{current: :done, figure: 1.0} = Phase.of(torrent(:completed, %{progress: 100.0}))
    end

    test "an unknown client state has no position and no condition" do
      assert %{current: nil, condition: nil} = Phase.of(torrent(:other))
    end
  end

  describe "word/1 and text_class/1" do
    test "the condition speaks before the step" do
      assert Phase.word(Phase.of(usenet(:paused))) == "Paused"
      assert Phase.word(Phase.of(torrent(:stalled))) == "Stalled"
      assert Phase.word(Phase.of(usenet(:queued))) == "Queued"
      assert Phase.word(Phase.of(usenet(:error))) == "Failed"
    end

    test "each step has its word" do
      assert Phase.word(Phase.of(usenet(:fetching_nzb))) == "Fetching NZB"
      assert Phase.word(Phase.of(torrent(:downloading, %{status: "metaDL"}))) == "Fetching metadata"
      assert Phase.word(Phase.of(usenet(:downloading))) == "Downloading"
      assert Phase.word(Phase.of(usenet(:verifying))) == "Verifying"
      assert Phase.word(Phase.of(usenet(:repairing))) == "Repairing"
      assert Phase.word(Phase.of(usenet(:extracting))) == "Unpacking"
      assert Phase.word(Phase.of(usenet(:moving))) == "Moving"
      assert Phase.word(Phase.of(usenet(:completed))) == "Done"
      assert Phase.word(Phase.of(torrent(:other))) == "Unknown"
    end

    test "color is signal: calm while working, warning for a held job, error for a failed one" do
      assert Phase.text_class(Phase.of(usenet(:extracting))) == "text-info/80"
      assert Phase.text_class(Phase.of(usenet(:completed))) == "text-success/80"
      assert Phase.text_class(Phase.of(usenet(:queued))) == "text-base-content/55"
      assert Phase.text_class(Phase.of(usenet(:paused))) == "text-warning/80"
      assert Phase.text_class(Phase.of(torrent(:stalled))) == "text-warning/80"
      assert Phase.text_class(Phase.of(usenet(:error))) == "text-error/80"
      assert Phase.text_class(Phase.of(torrent(:other))) == "text-base-content/60"
    end
  end

  describe "working?/1" do
    test "true only for a positioned, unconditioned, unfinished job — what earns an indeterminate bar" do
      assert Phase.working?(Phase.of(usenet(:moving)))
      assert Phase.working?(Phase.of(usenet(:fetching_nzb)))
      refute Phase.working?(Phase.of(usenet(:completed)))
      refute Phase.working?(Phase.of(usenet(:paused)))
      refute Phase.working?(Phase.of(usenet(:error)))
      refute Phase.working?(Phase.of(torrent(:other)))
    end
  end

  describe "step_word/1" do
    test "names a ladder step for a hover label" do
      assert Phase.step_word(:fetch) == "Fetch NZB"
      assert Phase.step_word(:metadata) == "Fetch metadata"
      assert Phase.step_word(:download) == "Download"
      assert Phase.step_word(:verify) == "Verify"
      assert Phase.step_word(:repair) == "Repair"
      assert Phase.step_word(:unpack) == "Unpack"
      assert Phase.step_word(:move) == "Move"
      assert Phase.step_word(:done) == "Done"
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/phase_test.exs`
Expected: compile error — `MediaCentaur.Downloads.Phase` is undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Downloads.Phase do
  @moduledoc """
  Where a download-client job is on its protocol's ladder of phases — the
  projection every surface draws a job from.

  A job moves through a short, protocol-specific ladder:

    * usenet — `:fetch` (the client is pulling the NZB), `:download`,
      `:verify`, `:repair` (only while it happens; SABnzbd does not say
      afterwards whether it did), `:unpack`, `:move`, `:done`
    * torrent — `:metadata`, `:download`, `:done`

  `current` is the step under way, or nil when the job has no position
  (failed, or a state the driver could not place). `condition` qualifies
  the step — `:queued`, `:paused`, `:stalled`, `:failed` — and is not a
  step. `figure` is how far through the current step the job is, 0..1,
  or nil when the client gives no figure: the client's percentage during
  `:download`, parsed from the SABnzbd stage line in post-processing
  ("Unpacking: 45%", "Verifying: 14/56"), nil while fetching.

  Pure: derived from `QueueItem.state`, `status`, `protocol`, `progress`
  and `stage_line`, never stored. `QueueItem.state` stays the client's
  word for cancel routing, health and the status sentence; this module is
  the one place the ladder is known. A SABnzbd history "Queued" (the
  post-processing queue) and a live-queue "Queued" both arrive as
  `:queued`; both draw as the queued condition on `:download`, which
  misplaces the lit step for the seconds a job waits for post-processing
  and is accepted.
  """

  alias MediaCentaur.Downloads.QueueItem

  @type step :: :fetch | :metadata | :download | :verify | :repair | :unpack | :move | :done
  @type condition :: nil | :queued | :paused | :stalled | :failed

  @type t :: %__MODULE__{
          ladder: [step()],
          current: step() | nil,
          condition: condition(),
          figure: float() | nil
        }

  @enforce_keys [:ladder, :current, :condition, :figure]
  defstruct [:ladder, :current, :condition, :figure]

  @usenet [:fetch, :download, :verify, :unpack, :move, :done]
  @usenet_repairing [:fetch, :download, :verify, :repair, :unpack, :move, :done]
  @torrent [:metadata, :download, :done]

  @doc "Projects a queue item onto its ladder."
  @spec of(QueueItem.t()) :: t()
  def of(%QueueItem{protocol: :usenet} = item) do
    {current, condition} = usenet_position(item.state)

    %__MODULE__{
      ladder: if(current == :repair, do: @usenet_repairing, else: @usenet),
      current: current,
      condition: condition,
      figure: figure(current, item)
    }
  end

  def of(%QueueItem{} = item) do
    {current, condition} = torrent_position(item.state, item.status)

    %__MODULE__{
      ladder: @torrent,
      current: current,
      condition: condition,
      figure: figure(current, item)
    }
  end

  defp usenet_position(:fetching_nzb), do: {:fetch, nil}
  defp usenet_position(:downloading), do: {:download, nil}
  defp usenet_position(:queued), do: {:download, :queued}
  defp usenet_position(:paused), do: {:download, :paused}
  defp usenet_position(:stalled), do: {:download, :stalled}
  defp usenet_position(:verifying), do: {:verify, nil}
  defp usenet_position(:repairing), do: {:repair, nil}
  defp usenet_position(:extracting), do: {:unpack, nil}
  defp usenet_position(:moving), do: {:move, nil}
  defp usenet_position(:completed), do: {:done, nil}
  defp usenet_position(:error), do: {nil, :failed}
  defp usenet_position(_other), do: {nil, nil}

  # qBittorrent folds the metadata fetch into `:downloading`; the raw
  # status still says which it is.
  defp torrent_position(:downloading, "metaDL"), do: {:metadata, nil}
  defp torrent_position(:downloading, _status), do: {:download, nil}
  defp torrent_position(:queued, _status), do: {:download, :queued}
  defp torrent_position(:paused, _status), do: {:download, :paused}
  defp torrent_position(:stalled, _status), do: {:download, :stalled}
  defp torrent_position(:completed, _status), do: {:done, nil}
  defp torrent_position(:error, _status), do: {nil, :failed}
  defp torrent_position(_state, _status), do: {nil, nil}

  defp figure(:download, %QueueItem{progress: pct}) when is_number(pct), do: pct / 100
  defp figure(:done, _item), do: 1.0

  defp figure(step, %QueueItem{stage_line: line}) when step in [:verify, :repair, :unpack, :move],
    do: stage_figure(line)

  defp figure(_step, _item), do: nil

  # "Unpacking: 45%" → 0.45; "Verifying: 14/56" → 0.25; anything else → nil.
  defp stage_figure(line) when is_binary(line) do
    case Regex.run(~r/(\d+(?:\.\d+)?)\s*%\s*$/, line) do
      [_, pct] -> clamp(parse_number(pct) / 100)
      nil -> ratio_figure(line)
    end
  end

  defp stage_figure(_line), do: nil

  defp ratio_figure(line) do
    case Regex.run(~r/(\d+)\s*\/\s*(\d+)\s*$/, line) do
      [_, done, total] ->
        total = String.to_integer(total)
        if total > 0, do: clamp(String.to_integer(done) / total)

      nil ->
        nil
    end
  end

  defp parse_number(text) do
    case Float.parse(text) do
      {value, _rest} -> value
      :error -> 0.0
    end
  end

  defp clamp(value), do: value |> max(0.0) |> min(1.0)

  @doc "The word the strip shows: the condition when there is one, else the step."
  @spec word(t()) :: String.t()
  def word(%__MODULE__{condition: :queued}), do: "Queued"
  def word(%__MODULE__{condition: :paused}), do: "Paused"
  def word(%__MODULE__{condition: :stalled}), do: "Stalled"
  def word(%__MODULE__{condition: :failed}), do: "Failed"
  def word(%__MODULE__{current: :fetch}), do: "Fetching NZB"
  def word(%__MODULE__{current: :metadata}), do: "Fetching metadata"
  def word(%__MODULE__{current: :download}), do: "Downloading"
  def word(%__MODULE__{current: :verify}), do: "Verifying"
  def word(%__MODULE__{current: :repair}), do: "Repairing"
  def word(%__MODULE__{current: :unpack}), do: "Unpacking"
  def word(%__MODULE__{current: :move}), do: "Moving"
  def word(%__MODULE__{current: :done}), do: "Done"
  def word(%__MODULE__{current: nil}), do: "Unknown"

  @doc "A ladder step's name, for the hover label on its segment."
  @spec step_word(step()) :: String.t()
  def step_word(:fetch), do: "Fetch NZB"
  def step_word(:metadata), do: "Fetch metadata"
  def step_word(:download), do: "Download"
  def step_word(:verify), do: "Verify"
  def step_word(:repair), do: "Repair"
  def step_word(:unpack), do: "Unpack"
  def step_word(:move), do: "Move"
  def step_word(:done), do: "Done"

  @doc """
  Text-color class for the word (status labels are plain colored text,
  never a badge). Calm info while the client works, success when done,
  warning for a held job, error for a failed one.
  """
  @spec text_class(t()) :: String.t()
  def text_class(%__MODULE__{condition: :failed}), do: "text-error/80"
  def text_class(%__MODULE__{condition: :paused}), do: "text-warning/80"
  def text_class(%__MODULE__{condition: :stalled}), do: "text-warning/80"
  def text_class(%__MODULE__{condition: :queued}), do: "text-base-content/55"
  def text_class(%__MODULE__{current: :done}), do: "text-success/80"
  def text_class(%__MODULE__{current: nil}), do: "text-base-content/60"
  def text_class(%__MODULE__{}), do: "text-info/80"

  @doc """
  Whether the client is actively working the job: positioned, not held by
  a condition, not done. A working job with no figure earns an
  indeterminate bar so the row still reads alive.
  """
  @spec working?(t()) :: boolean()
  def working?(%__MODULE__{current: nil}), do: false
  def working?(%__MODULE__{current: :done}), do: false
  def working?(%__MODULE__{condition: nil}), do: true
  def working?(%__MODULE__{}), do: false
end
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/phase_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/downloads/phase.ex test/media_centaur/downloads/phase_test.exs
git commit -m "feat(downloads): Phase — a job's position on its protocol's ladder"
```

---

### Task 3: `DownloadProgress` carries the phase

**Files:**
- Modify: `lib/media_centaur/acquisition/view_models/download_progress.ex`
- Modify: `lib/media_centaur/acquisition/queue_matcher.ex:160-200`
- Test: `test/media_centaur/acquisition/queue_matcher_test.exs`

- [ ] **Step 1: Write the failing test**

Add inside `describe "to_download/1"`:

```elixir
    test "carries the job's phase" do
      download = QueueMatcher.to_download(item("abc", "Sample.Movie", %{progress: 42.0}))

      assert %MediaCentaur.Downloads.Phase{current: :download, figure: 0.42} = download.phase
    end

    test "a usenet job in post-processing reads its figure from the stage line" do
      download =
        QueueMatcher.to_download(
          item("nzo", "Sample.Movie", %{
            protocol: :usenet,
            state: :extracting,
            progress: nil,
            stage_line: "Unpacking: 45%"
          })
        )

      assert download.phase.current == :unpack
      assert download.phase.figure == 0.45
      assert download.progress_pct == nil
    end
```

(Check the `item/3` helper at the top of the test file accepts a `protocol` override; if it builds the struct with `struct!(%QueueItem{...}, overrides)` it does.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/queue_matcher_test.exs`
Expected: failure — `phase` is not a key of `DownloadProgress`.

- [ ] **Step 3: Implement**

In `download_progress.ex`, add `:phase` to the `defstruct` and to the typespec:

```elixir
  defstruct [:state, :title, :progress_pct, :size_bytes, :size_left_bytes, :eta, :client, :protocol, :phase]
```

```elixir
          phase: MediaCentaur.Downloads.Phase.t() | nil
```

with a comment above the struct:

```elixir
  # `phase` is the job's position on its protocol's ladder
  # (`Downloads.Phase`) — what the download strip draws. `state` stays
  # the client's word for callers that route on it.
```

In `queue_matcher.ex`, add `phase: Phase.of(qi)` to both `to_download/1` clauses and `alias MediaCentaur.Downloads.Phase` at the top. The `:fetching_nzb` clause keeps `progress_pct: nil` and `eta: nil` (the watchlist pill reads `progress_pct`).

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/queue_matcher_test.exs test/media_centaur/acquisition/view_models/pursuit_status_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/view_models/download_progress.ex lib/media_centaur/acquisition/queue_matcher.ex test/media_centaur/acquisition/queue_matcher_test.exs
git commit -m "feat(acquisition): DownloadProgress carries the job's phase"
```

---

### Task 4: `:underway` in the cell vocabulary

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/cell_vocabulary.ex`
- Test: `test/media_centaur_web/components/acquisition/cell_vocabulary_test.exs`

- [ ] **Step 1: Write the failing test**

Add a describe:

```elixir
  describe ":underway — the ladder step under way" do
    test "is lit in the primary and pulses, at both sizes" do
      assert CellVocabulary.segment_treatment(:underway) =~ "bg-primary/80"
      assert CellVocabulary.segment_treatment(:underway) =~ "animate-pulse"
      assert CellVocabulary.cell_treatment(:underway) =~ "animate-pulse"
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/acquisition/cell_vocabulary_test.exs`
Expected: failure — `segment_treatment(:underway)` returns the default `bg-base-content/10`.

- [ ] **Step 3: Implement**

In the moduledoc's state list add:

```
    * `:underway` — primary fill, pulsing. The ladder step a
      download-client job is working through right now (the download
      strip); past steps are `:landed`, later steps the muted default.
```

Add `:underway` to `@type state`, and:

```elixir
  def cell_treatment(:underway), do: "bg-primary/40 border border-primary/80 text-base-content/80 animate-pulse"
```

```elixir
  def segment_treatment(:underway), do: "bg-primary/80 animate-pulse"
```

(Place each beside its `:claimed` clause.)

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/acquisition/cell_vocabulary_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/acquisition/cell_vocabulary.ex test/media_centaur_web/components/acquisition/cell_vocabulary_test.exs
git commit -m "feat(acquisition): :underway cell state for the phase ladder"
```

---

### Task 5: The download strip

**Files:**
- Create: `lib/media_centaur_web/components/acquisition/download_strip.ex`
- Modify: `assets/css/app.css` (after `.progress-fill`, line ~1983)
- Create: `storybook/acquisition/download_strip.story.exs`
- Modify: `storybook/acquisition/_acquisition.index.exs`
- Test: `test/media_centaur_web/components/acquisition/download_strip_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaurWeb.Components.Acquisition.DownloadStripTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.ViewModels.DownloadProgress
  alias MediaCentaur.Downloads.{Phase, QueueItem}
  alias MediaCentaurWeb.Components.Acquisition.DownloadStrip

  defp download(protocol, state, overrides) do
    item =
      struct!(
        %QueueItem{id: "job", title: "Sample.Show.S01E01.1080p.WEB-DL", state: state, protocol: protocol},
        overrides
      )

    %DownloadProgress{
      state: state,
      title: item.title,
      progress_pct: item.progress,
      size_bytes: item.size,
      eta: item.timeleft,
      client: if(protocol == :usenet, do: "SABnzbd", else: "qBittorrent"),
      protocol: protocol,
      phase: Phase.of(item)
    }
  end

  defp strip(download, attrs \\ []) do
    render_component(
      &DownloadStrip.download_strip/1,
      Keyword.merge([download: download, queue_item_id: "job", cancel_title: "Sample Show"], attrs)
    )
  end

  test "a transfer draws the word, the figure, the ETA, the size and the client" do
    html =
      strip(download(:torrent, :downloading, %{status: "downloading", progress: 42.0, size: 4_200_000_000, timeleft: "12m"}))

    assert html =~ "Downloading"
    assert html =~ "42%"
    assert html =~ "ETA 12m"
    assert html =~ "4.2 GB"
    assert html =~ "qBittorrent"
    assert html =~ ~s|style="width: 42%"|
  end

  test "the ladder lights the current step and fills the steps behind it" do
    html = strip(download(:usenet, :extracting, %{stage_line: "Unpacking: 45%"}))

    assert html =~ ~s|data-step="fetch" data-step-state="landed"|
    assert html =~ ~s|data-step="download" data-step-state="landed"|
    assert html =~ ~s|data-step="verify" data-step-state="landed"|
    assert html =~ ~s|data-step="unpack" data-step-state="underway"|
    assert html =~ ~s|data-step="move" data-step-state="ahead"|
    assert html =~ "Unpacking"
    assert html =~ "45%"
    assert html =~ ~s|style="width: 45%"|
    refute html =~ "ETA"
  end

  test "a working step with no figure draws the indeterminate bar" do
    html = strip(download(:usenet, :moving, %{stage_line: nil}))

    assert html =~ "Moving"
    assert html =~ "progress-indeterminate"
    refute html =~ "%"
  end

  test "fetching the NZB is step one with the indeterminate bar and no figure" do
    html = strip(download(:usenet, :fetching_nzb, %{progress: 19.0}))

    assert html =~ ~s|data-step="fetch" data-step-state="underway"|
    assert html =~ "Fetching NZB"
    assert html =~ "progress-indeterminate"
    refute html =~ "19%"
  end

  test "a held job keeps its figure but gets no motion" do
    html = strip(download(:torrent, :paused, %{progress: 50.0}))

    assert html =~ "Paused"
    assert html =~ ~s|style="width: 50%"|
    refute html =~ "progress-indeterminate"
  end

  test "a failed job has no lit step and no bar" do
    html = strip(download(:usenet, :error, %{}))

    assert html =~ "Failed"
    refute html =~ ~s|data-step-state="underway"|
    refute html =~ "progress-fill"
    refute html =~ "progress-indeterminate"
  end

  test "the state word is plain text, never a badge" do
    html = strip(download(:usenet, :verifying, %{}))
    refute html =~ "badge"
  end

  test "cancel renders only with a queue item id, armed when the id matches" do
    download = download(:torrent, :downloading, %{progress: 10.0})

    assert strip(download, queue_item_id: nil) |> String.contains?("cancel_download") == false
    assert strip(download) =~ ~s|phx-value-id="job"|
    assert strip(download, cancel_armed_id: "job") =~ "Click again to cancel"
  end

  test "telemetry age qualifies the figures" do
    html = strip(download(:torrent, :downloading, %{progress: 10.0}), telemetry_age: "last seen 4m ago")
    assert html =~ "last seen 4m ago"
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/acquisition/download_strip_test.exs`
Expected: compile error — `DownloadStrip` is undefined.

- [ ] **Step 3: Implement the component**

```elixir
defmodule MediaCentaurWeb.Components.Acquisition.DownloadStrip do
  @moduledoc """
  The one drawing of a download-client job: its phase on the ladder, the
  phase word, the figure bar, and the facts beside them.

  Every surface that shows a job composes from `download_strip/1` — the
  pursuit row's footer, the Other downloads row, the pursuit modal's
  activity card. None draws a bar or a state word of its own; three
  drawings of one idea is how the transfer footer, the orphan badge and
  the modal's fatter bar drifted apart.

  Reads `DownloadProgress.phase` (`Downloads.Phase`): the ladder as one
  small segment per step in the shared `CellVocabulary` (past steps
  `:landed`, the current step `:underway`, later steps the muted default;
  each segment names its step on hover), the phase word as plain colored
  text, and the 3px bar — the known figure when there is one, the
  indeterminate slide while the client works with no figure, nothing for
  a held or failed job without a figure. ETA shows only during the
  download step: the client's estimate describes the transfer.

  Cancel is the house arm gesture (MC0027 tier 2): the host owns which
  job is armed and passes it as `cancel_armed_id`; a strip with no
  `queue_item_id` draws no cancel (the modal cancels the pursuit, not the
  job).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [armed_button: 1, icon: 1]

  alias MediaCentaur.Acquisition.ViewModels.DownloadProgress
  alias MediaCentaur.Downloads.Phase
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Acquisition.CellVocabulary

  attr :download, DownloadProgress, required: true

  attr :queue_item_id, :string,
    default: nil,
    doc: "The client's id for the job. Nil draws no cancel control."

  attr :cancel_title, :string,
    default: nil,
    doc: "The name the cancel event carries (`phx-value-title`)."

  attr :cancel_armed_id, :string,
    default: nil,
    doc: "Host-owned: the queue-item id whose cancel is one click from firing."

  attr :telemetry_age, :string,
    default: nil,
    doc: "Staleness qualifier (\"last seen 4m ago\") when the client is lagging; nil when fresh."

  attr :bare, :boolean,
    default: false,
    doc: "Skips the top border and padding — the host frame (identity-banner strip, orphan row) provides its own."

  def download_strip(assigns) do
    phase = assigns.download.phase
    figure = phase && phase.figure
    pct = figure && round(figure * 100)

    assigns =
      assigns
      |> assign(:phase, phase)
      |> assign(:pct, pct)
      |> assign(:indeterminate?, is_nil(pct) and phase != nil and Phase.working?(phase))

    ~H"""
    <div class={[@bare && "space-y-1.5", !@bare && "border-t border-base-content/5 pt-2 space-y-1.5"]}>
      <div class="flex items-center gap-3">
        <.ladder :if={@phase} phase={@phase} />
        <span class={["flex-shrink-0 text-xs font-medium uppercase tracking-wider", Phase.text_class(@phase)]}>
          {Phase.word(@phase)}
        </span>
        <%!-- The release name is what tells three otherwise-identical
              strips apart on a multi-download pursuit. --%>
        <span :if={@download.title} class="min-w-0 truncate text-xs text-base-content/55" data-tip={@download.title}>
          {@download.title}
        </span>
        <%!-- Facts cluster right, beside the cancel affordance — a
              left-glued cluster leaves the row's width as dead span on
              wide viewports. --%>
        <div class="flex-1" />
        <span :if={@pct} class="text-xs text-base-content/60 tabular-nums">{@pct}%</span>
        <span
          :if={@download.eta && @phase && @phase.current == :download}
          class="text-xs text-base-content/55 tabular-nums"
        >
          ETA {@download.eta}
        </span>
        <span :if={@download.size_bytes} class="flex-shrink-0 text-xs text-base-content/55 tabular-nums">
          {Format.format_size_decimal(@download.size_bytes)}
        </span>
        <span :if={@download.client} class="flex-shrink-0 text-xs text-base-content/55">
          {@download.client}
        </span>
        <%!-- When the download client is lagging/offline these figures are
              last-known, not live — qualify them so the user isn't misled
              into thinking the bar is updating in real time. --%>
        <span :if={@telemetry_age} class="text-xs text-warning/80 tabular-nums">· {@telemetry_age}</span>
        <%!-- No `shape="circle"`: the armed state relabels the control,
              and a fixed circle would clip the label it grows into. --%>
        <.armed_button
          :if={@queue_item_id}
          armed={@cancel_armed_id == @queue_item_id}
          event="cancel_download"
          armed_label="Click again to cancel"
          variant="destructive_inline"
          size="xs"
          class="text-base-content/55 hover:text-error"
          phx-value-id={@queue_item_id}
          phx-value-title={@cancel_title}
          data-tip="Cancel and delete"
          aria-label="Cancel download"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.armed_button>
      </div>

      <div :if={@pct} class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
        <div class="progress-fill h-full bg-primary rounded-full" style={"width: #{@pct}%"}></div>
      </div>
      <div :if={@indeterminate?} class="progress-indeterminate h-[3px] bg-base-content/10 rounded-full"></div>
    </div>
    """
  end

  # The ladder: one segment per step, the same w-2 squares as the
  # composite pursuit card's unit segments (UIDR-014) — the shape of
  # completion, not a percentage.
  attr :phase, Phase, required: true

  defp ladder(assigns) do
    ~H"""
    <div class="flex flex-shrink-0 items-center gap-1" aria-hidden="true">
      <span
        :for={{step, state} <- steps(@phase)}
        data-step={step}
        data-step-state={state}
        data-tip={Phase.step_word(step)}
        class={["w-2 h-2 rounded-sm", segment_class(state)]}
      ></span>
    </div>
    """
  end

  # Past steps landed, the current step underway, later steps ahead. A
  # job with no position (failed, unknown) lights nothing.
  defp steps(%Phase{ladder: ladder, current: nil}), do: Enum.map(ladder, &{&1, :ahead})

  defp steps(%Phase{ladder: ladder, current: current}) do
    index = Enum.find_index(ladder, &(&1 == current))

    ladder
    |> Enum.with_index()
    |> Enum.map(fn
      {step, i} when i < index -> {step, :landed}
      {step, i} when i == index -> {step, :underway}
      {step, _i} -> {step, :ahead}
    end)
  end

  defp segment_class(:landed), do: CellVocabulary.segment_treatment(:landed)
  defp segment_class(:underway), do: CellVocabulary.segment_treatment(:underway)
  defp segment_class(:ahead), do: CellVocabulary.segment_treatment(:ahead)
end
```

`CellVocabulary.segment_treatment(:ahead)` hits the `_other` clause (`bg-base-content/10`) — that is the intended muted default; no new vocabulary state.

- [ ] **Step 4: Add the CSS**

In `assets/css/app.css` directly after the `.progress-fill` rule:

```css
/* Indeterminate figure bar — the download strip's "the client is working
   but gives no figure" state (fetching an NZB, moving a finished file).
   A highlight slides across the 3px slot; transform-only, so it never
   touches layout or the blur layers (UIDR-012 animation rules). */
.progress-indeterminate {
  position: relative;
  overflow: hidden;
}

.progress-indeterminate::after {
  content: "";
  position: absolute;
  inset: 0;
  width: 40%;
  border-radius: 9999px;
  background: var(--color-primary);
  animation: progress-slide 1.4s ease-in-out infinite;
}

@keyframes progress-slide {
  from {
    transform: translateX(-100%);
  }

  to {
    transform: translateX(250%);
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/acquisition/download_strip_test.exs`
Expected: all pass. If `Format.format_size_decimal(4_200_000_000)` renders other than `"4.2 GB"`, read `lib/media_centaur/format.ex` and adjust the assertion to its output — the helper is the house formatter and is not changed here.

- [ ] **Step 6: Write the story**

```elixir
defmodule MediaCentaurWeb.Storybook.Acquisition.DownloadStrip do
  @moduledoc """
  The one drawing of a download-client job. One variation per phase per
  protocol, then the conditions, then the strip's extras (telemetry age,
  cancel armed, no cancel). Each builds a `DownloadProgress` the way
  `QueueMatcher.to_download/1` would, from a `QueueItem` literal.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.DownloadProgress
  alias MediaCentaur.Downloads.{Phase, QueueItem}

  def function, do: &MediaCentaurWeb.Components.Acquisition.DownloadStrip.download_strip/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-xl identity-row rounded-lg px-4 py-3" style="--banner-hue: 210">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :usenet_ladder,
        description: "A usenet job at each step of its ladder.",
        variations: [
          variation(:fetching_nzb, "Fetching NZB — step one, no figure, the indeterminate bar.",
            usenet(:fetching_nzb, title: "Fetching NZB…", progress: 19.0)
          ),
          variation(:downloading, "Downloading — the client's percentage and ETA.",
            usenet(:downloading, progress: 42.0, timeleft: "12m")
          ),
          variation(:verifying, "Verifying — figure from the stage line's n/m count.",
            usenet(:verifying, stage_line: "Verifying: 14/56")
          ),
          variation(:repairing, "Repairing — the step appears on the ladder only while it happens.",
            usenet(:repairing, stage_line: "Repairing: 12%")
          ),
          variation(:unpacking, "Unpacking — figure from the stage line's percentage.",
            usenet(:extracting, stage_line: "Unpacking: 45%")
          ),
          variation(:moving, "Moving — minutes-long for a large file, no figure, indeterminate.",
            usenet(:moving, stage_line: nil)
          ),
          variation(:done, "Done.", usenet(:completed, progress: 100.0))
        ]
      },
      %VariationGroup{
        id: :torrent_ladder,
        description: "A torrent at each step of its shorter ladder.",
        variations: [
          variation(:metadata, "Fetching metadata — qBittorrent's metaDL.",
            torrent(:downloading, status: "metaDL", title: "Fetching torrent details…")
          ),
          variation(:downloading, "Downloading.", torrent(:downloading, progress: 42.0, timeleft: "12m")),
          variation(:done, "Done.", torrent(:completed, progress: 100.0))
        ]
      },
      %VariationGroup{
        id: :conditions,
        description: "A condition speaks before the step; a held job keeps its figure without motion.",
        variations: [
          variation(:queued, "Queued — passive waiting, muted.", torrent(:queued)),
          variation(:paused, "Paused.", torrent(:paused, progress: 67.0)),
          variation(:stalled, "Stalled — the client can't make progress.", torrent(:stalled, progress: 12.0)),
          variation(:failed, "Failed — nothing lit, no bar.", usenet(:error))
        ]
      },
      %VariationGroup{
        id: :extras,
        variations: [
          variation(:stale, "The client is lagging — figures qualified with a last-seen age.",
            torrent(:downloading, progress: 42.0, timeleft: "12m"),
            telemetry_age: "last seen 4m ago"
          ),
          variation(:cancel_armed, "Cancel armed — the control relabels and turns danger.",
            torrent(:downloading, progress: 42.0),
            cancel_armed_id: "job"
          ),
          variation(:no_cancel, "No queue item id — the modal cancels the pursuit, not the job.",
            torrent(:downloading, progress: 42.0),
            queue_item_id: nil
          )
        ]
      }
    ]
  end

  defp variation(id, description, download, extra \\ []) do
    %Variation{
      id: id,
      description: description,
      attributes:
        Map.merge(
          %{download: download, queue_item_id: "job", cancel_title: "Sample Show", bare: true},
          Map.new(extra)
        )
    }
  end

  defp usenet(state, opts), do: build(:usenet, "SABnzbd", state, opts)
  defp torrent(state, opts \\ []), do: build(:torrent, "qBittorrent", state, opts)

  defp build(protocol, client, state, opts) do
    item = %QueueItem{
      id: "job",
      title: Keyword.get(opts, :title, "Sample.Show.S01E01.1080p.WEB-DL"),
      status: Keyword.get(opts, :status),
      state: state,
      protocol: protocol,
      download_client: client,
      size: 4_200_000_000,
      progress: Keyword.get(opts, :progress),
      timeleft: Keyword.get(opts, :timeleft),
      stage_line: Keyword.get(opts, :stage_line)
    }

    %DownloadProgress{
      state: state,
      title: item.title,
      progress_pct: item.progress,
      size_bytes: item.size,
      eta: item.timeleft,
      client: client,
      protocol: protocol,
      phase: Phase.of(item)
    }
  end
end
```

Add to `storybook/acquisition/_acquisition.index.exs` after the `pursuit_row` entry:

```elixir
  def entry("download_strip"), do: [icon: {:fa, "bars-progress", :thin}, name: "Download strip"]
```

- [ ] **Step 7: Run the storybook tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass, with the new story compiled and rendered. (Find the exact test file names with `ls test/media_centaur_web | grep storybook` if these differ.)

- [ ] **Step 8: Look at it**

Run: `~/scripts/agents/page-shot --url http://localhost:2160/storybook/acquisition/download_strip --wait-ms 3000 --viewport 1600x1200` and Read the PNG. The ladder reads as a row of small squares with one pulsing; the word sits beside it in the phase color; the indeterminate bar slides. Adjust spacing only.

- [ ] **Step 9: Commit**

```bash
git add lib/media_centaur_web/components/acquisition/download_strip.ex assets/css/app.css storybook/acquisition/download_strip.story.exs storybook/acquisition/_acquisition.index.exs test/media_centaur_web/components/acquisition/download_strip_test.exs
git commit -m "feat(incoming): the download strip — one drawing of a job on its phase ladder"
```

---

### Task 6: The pursuit row composes the strip

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/pursuit_row.ex`
- Modify: `lib/media_centaur_web/live/incoming_live/logic.ex:500-556`
- Modify: `storybook/acquisition/pursuit_row.story.exs:174-330`
- Test: `test/media_centaur_web/live/incoming_live/logic_test.exs:603-640`, `test/media_centaur_web/live/incoming_live_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/media_centaur_web/live/incoming_live_test.exs`, after the test `"a matched queue item renders as a footer under the right pursuit card"`, add:

```elixir
    test "a matched usenet job in post-processing draws its phase, not a text dump", %{conn: conn} do
      pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/incoming?zone=activity")

      unpacking = %QueueItem{
        id: "nzo-unpacking",
        title: "sample movie 2010 1080p web dl",
        state: :extracting,
        status: "Extracting",
        protocol: :usenet,
        download_client: "SABnzbd",
        stage_line: "Unpacking: 45%"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [unpacking]}})

      html = render_until(view, ~s|data-pursuit-id="#{pursuit.id}"|)
      assert html =~ ~s|data-step="unpack" data-step-state="underway"|
      assert html =~ "Unpacking"
      assert html =~ "45%"
      refute html =~ "Other downloads"
    end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs --only line:<line of the new test>`
Expected: failure — no `data-step` markup; the row still renders the old footer.

- [ ] **Step 3: Implement**

In `pursuit_row.ex`:

- Replace the `import MediaCentaurWeb.CoreComponents, only: [armed_button: 1, badge: 1, icon: 1]` with `import MediaCentaurWeb.CoreComponents, only: [badge: 1]`.
- Remove `alias MediaCentaur.Format` only if no other use remains (`display_title/1` uses `Format.episode_label/2` — keep it). Remove `alias MediaCentaurWeb.IncomingLive.Logic`.
- Add `alias MediaCentaurWeb.Components.Acquisition.DownloadStrip`.
- In the `:media` door, replace the `<.download_footer ... bare />` call with:

```heex
        <DownloadStrip.download_strip
          :for={paired <- @paired_downloads}
          download={paired.download}
          queue_item_id={paired.queue_item_id}
          cancel_title={@vm.release_title || @vm.title}
          cancel_armed_id={@cancel_armed_id}
          telemetry_age={@telemetry_age}
          bare
        />
```

- In the `:query` door, the same without `bare`.
- Delete the private `download_footer/1` (its attrs and body) and `progress_width/1`.
- Update the moduledoc's third surface: "3. **Download strip** — `DownloadStrip.download_strip/1` per claimed job. Only when `:download` is non-nil."

In `logic.ex`, delete `state_label/1`, `state_badge_variant/1`, `state_text_class/1` and their `@doc`s (lines ~500–556). `Downloads.Phase` owns the words now. Run `grep -rn "Logic.state_" lib` — the only remaining caller is `orphan_queue.ex`, handled in Task 7; compile will fail until then, so do Task 7's Step 3 before running the suite, or leave the three functions in place until Task 7 and delete them there. Prefer the latter: leave them for now.

In `storybook/acquisition/pursuit_row.story.exs`, in the `:download_footer` group:
- Rename the group id to `:download_strip` and its description to "When a job is paired, the download strip renders and the status sentence is hidden — the live phase speaks for itself. Every phase lives in the Download strip story; this group covers the row's framing."
- Keep `:matched_downloading`, `:matched_downloading_stale`, `:matched_cancel_armed`, `:no_match_searching`, `:grabbing`, `:handed_off`, `:never_arrived`, `:downloaded_not_landed` and the rest; delete `:matched_fetching_nzb`, `:matched_stalled`, `:matched_queued`, `:matched_error` (the strip story holds them).
- Add `phase:` to every remaining `%DownloadProgress{}` literal in the file. Add a helper at the bottom and use it:

```elixir
  alias MediaCentaur.Downloads.{Phase, QueueItem}

  # A DownloadProgress the way `QueueMatcher.to_download/1` builds one.
  defp progress(state, opts) do
    item = %QueueItem{
      id: "job",
      title: Keyword.get(opts, :title),
      status: Keyword.get(opts, :status),
      state: state,
      protocol: Keyword.get(opts, :protocol, :torrent),
      progress: Keyword.get(opts, :progress_pct),
      size: Keyword.get(opts, :size_bytes),
      timeleft: Keyword.get(opts, :eta)
    }

    %DownloadProgress{
      state: state,
      title: item.title,
      progress_pct: item.progress,
      size_bytes: item.size,
      size_left_bytes: Keyword.get(opts, :size_left_bytes),
      eta: item.timeleft,
      client: Keyword.get(opts, :client),
      protocol: item.protocol,
      phase: Phase.of(item)
    }
  end
```

and rewrite e.g. the `:matched_downloading` download as:

```elixir
              download:
                progress(:downloading,
                  title: "Sample.Movie.2010.1080p.WEB-DL",
                  progress_pct: 42.0,
                  size_bytes: 4_200_000_000,
                  size_left_bytes: 2_400_000_000,
                  eta: "12m",
                  client: "qBittorrent"
                ),
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass, including the earlier `"ETA 10m"` assertion (download phase still shows ETA).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/acquisition/pursuit_row.ex storybook/acquisition/pursuit_row.story.exs test/media_centaur_web/live/incoming_live_test.exs
git commit -m "refactor(incoming): the pursuit row composes the download strip"
```

---

### Task 7: Other downloads composes the strip

**Files:**
- Modify: `lib/media_centaur_web/live/incoming_live/orphan_queue.ex`
- Modify: `lib/media_centaur_web/live/incoming_live/logic.ex:500-556` (delete the three state helpers)
- Test: `test/media_centaur_web/live/incoming_live_test.exs`, `test/media_centaur_web/live/incoming_live/logic_test.exs:603-640`

- [ ] **Step 1: Write the failing test**

After the test `"an unmatched queue item appears under 'Other downloads', and the pursuit shows its no-match hint"`, add:

```elixir
    test "an unmatched job under Other downloads is drawn by the strip — phase word as text, no badge", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/incoming?zone=activity")

      fetching = %QueueItem{
        id: "nzo-orphan-fetch",
        title: "Fetching NZB…",
        state: :fetching_nzb,
        status: "Grabbing",
        protocol: :usenet,
        download_client: "SABnzbd"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [fetching]}})

      html = render(view)
      assert html =~ "Other downloads"
      assert html =~ ~s|id="orphan-nzo-orphan-fetch"|
      assert html =~ ~s|data-step="fetch" data-step-state="underway"|
      assert html =~ "progress-indeterminate"
      refute html =~ ~r/class="[^"]*badge[^"]*"[^>]*>\s*Fetching NZB/
      refute html =~ "0:00:00"
    end
```

Delete the `describe "state_label/1"` and `describe "state_badge_variant/1"` blocks from `logic_test.exs` (lines 603–640).

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs --only line:<line of the new test>`
Expected: failure — the row has no ladder markup.

- [ ] **Step 3: Implement**

Rewrite `orphan_row/1` in `orphan_queue.ex`:

```elixir
  attr :item, QueueItem, required: true
  attr :cancel_armed_id, :string, default: nil

  defp orphan_row(assigns) do
    assigns = assign(assigns, :download, QueueMatcher.to_download(assigns.item))

    ~H"""
    <div id={"orphan-#{@item.id}"} class="px-4 py-3 border-b border-base-content/5 last:border-0">
      <DownloadStrip.download_strip
        download={@download}
        queue_item_id={@item.id}
        cancel_title={@item.title}
        cancel_armed_id={@cancel_armed_id}
        bare
      />
    </div>
    """
  end
```

Replace the imports and aliases at the top:

```elixir
  use Phoenix.Component

  alias MediaCentaur.Acquisition.QueueMatcher
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaurWeb.Components.Acquisition.DownloadStrip
```

Change the section copy:

```heex
        <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          Other downloads
        </h2>
        <p class="mt-0.5 text-[11px] text-base-content/55">
          Downloads in your clients that no pursuit claims.
        </p>
```

Update the moduledoc: "Each row is the download strip (`DownloadStrip.download_strip/1`), so an unclaimed job is drawn exactly as a claimed one, cancel included."

Now delete `state_label/1`, `state_badge_variant/1`, `state_text_class/1` and their docs from `logic.ex`. `grep -rn "state_label\|state_badge_variant\|state_text_class" lib/media_centaur_web/live/incoming_live lib/media_centaur_web/components/acquisition` must return nothing.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/incoming_live/logic_test.exs`
Expected: pass. The existing orphan tests (`"orphan downloads list keys rows by id and survives mid-list cancel"`) still find `id="orphan-…"` and `phx-value-id`.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/incoming_live/orphan_queue.ex lib/media_centaur_web/live/incoming_live/logic.ex test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/incoming_live/logic_test.exs
git commit -m "refactor(incoming): Other downloads composes the download strip; Phase owns the state words"
```

---

### Task 8: The pursuit modal's activity card composes the strip

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/pursuit_activity.ex:53-83`
- Modify: `storybook/acquisition/pursuit_activity.story.exs`
- Test: `test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs`

- [ ] **Step 1: Write the failing test**

Find in `incoming_live_pursuit_modal_test.exs` the test that opens the modal for a pursuit with a paired download (grep `progress_pct` or `queue_state`). Add beside it:

```elixir
    test "the activity card draws the paired job with the download strip", %{conn: conn} do
      pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/incoming?zone=activity")

      item = %QueueItem{
        id: "nzo-modal",
        title: "sample movie 2010 1080p web dl",
        state: :verifying,
        status: "Verifying",
        protocol: :usenet,
        download_client: "SABnzbd",
        stage_line: "Verifying: 14/56"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [item]}})
      render_until(view, ~s|data-pursuit-id="#{pursuit.id}"|)

      view |> element(~s|[data-pursuit-id="#{pursuit.id}"]|) |> render_click()
      html = render(view)

      assert html =~ ~s|data-step="verify" data-step-state="underway"|
      assert html =~ "25%"
    end
```

(Use the file's own helper for opening the modal if `render_click` on the card is not how its other tests do it — mirror the neighbouring test.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs --only line:<line>`
Expected: failure — the modal shows no ladder.

- [ ] **Step 3: Implement**

In `pursuit_activity.ex` replace the `<div :if={@vm.downloads != []} class="space-y-3.5">…</div>` block (lines 53–83) with:

```heex
      <div :if={@vm.downloads != []} class="space-y-3">
        <DownloadStrip.download_strip
          :for={entry <- @vm.downloads}
          download={entry.download}
          queue_item_id={nil}
          bare
        />
      </div>
```

Add `alias MediaCentaurWeb.Components.Acquisition.DownloadStrip`. Delete `progress_width/1` from this module. Update the moduledoc: "an optional download strip per claimed job (the modal cancels the pursuit, so the strip draws no job cancel)".

In `pursuit_activity.story.exs`, every `%DownloadProgress{…}` literal gains `phase:`. Add the same `progress/2` helper as in the pursuit row story (copy it; stories are independent files) and rewrite each literal through it, e.g. `download: progress(:downloading, progress_pct: 42.0, client: "qBittorrent", eta: "8m")`. Check how `base/1` feeds `downloads` — if the story passes only `download:` and `downloads: []`, add a `downloads: [%{download: …, release_title: "Sample.Movie.2010.1080p.WEB-DL"}]` to the `:downloading_healthy` variation so the strip renders in the catalog.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/acquisition/pursuit_activity.ex storybook/acquisition/pursuit_activity.story.exs test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs
git commit -m "refactor(incoming): the pursuit modal composes the download strip"
```

---

### Task 9: The status sentence carries the figure

**Files:**
- Modify: `lib/media_centaur/acquisition/view_models/pursuit_status.ex:444-456`
- Test: `test/media_centaur/acquisition/view_models/pursuit_status_test.exs:234-300`

- [ ] **Step 1: Write the failing test**

Inside `describe "derive/6 — active + acquired + queue states"`, find the table test over `{:verifying, "Verifying"}, {:extracting, "Unpacking"}` (line ~284) and read how it builds the queue item and calls `derive`. Add after it, using the same builders:

```elixir
    test "a post-processing step with a figure says how far along it is" do
      item = queue_item(%{state: :extracting, status: "Extracting", protocol: :usenet, stage_line: "Unpacking: 45%"})
      status = derive_with_queue(pursuit, target, [item])

      assert status.current_action.verb == "Unpacking"
      assert status.current_action.description == "45% through this step at the download client."
    end

    test "a post-processing step without a figure keeps the plain sentence" do
      item = queue_item(%{state: :moving, status: "Moving", protocol: :usenet, stage_line: nil})
      status = derive_with_queue(pursuit, target, [item])

      assert status.current_action.description == "Post-processing at the download client."
    end
```

(`queue_item/1` and `derive_with_queue/3` stand for whatever helpers the neighbouring table test uses — use those exact names and arities.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/pursuit_status_test.exs`
Expected: one failure on the description.

- [ ] **Step 3: Implement**

In `pursuit_status.ex`, change the post-processing clause:

```elixir
  defp at_client_action(%QueueItem{state: state} = qi)
       when state in [:verifying, :repairing, :extracting, :moving] do
    {
      %CurrentAction{
        verb: postprocessing_verb(state),
        description: postprocessing_description(qi),
        severity: :info
      },
      %NextStep{description: "The finished file lands in the library when this completes."},
      [:cancel]
    }
  end
```

and add beside `postprocessing_verb/1`:

```elixir
  defp postprocessing_description(%QueueItem{} = qi) do
    case Phase.of(qi).figure do
      figure when is_number(figure) -> "#{round(figure * 100)}% through this step at the download client."
      nil -> "Post-processing at the download client."
    end
  end
```

with `alias MediaCentaur.Downloads.Phase` added to the module's aliases.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/pursuit_status_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/view_models/pursuit_status.ex test/media_centaur/acquisition/view_models/pursuit_status_test.exs
git commit -m "feat(acquisition): the post-processing sentence carries the step's figure"
```

---

### Task 10: Precommit, docs, wiki

**Files:**
- Modify: `docs/pipeline.md` or `docs/download-clients.md` (one paragraph), `.claude/skills/user-interface/SKILL.md` (Component Inventory row), `../media-centaur.wiki/` Incoming page

- [ ] **Step 1: Run precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: zero warnings, zero Credo findings, all tests green. Fix anything reported (unused aliases from the deleted footer are the likely finding).

- [ ] **Step 2: Contributor docs**

In `docs/download-clients.md`, under the driver contract table, add:

```markdown
| Phase projection | `Downloads.Phase` — a job's step on its protocol's ladder, the condition on it, and the figure; the one place the ladder is known. Every surface draws a job from it through `Components.Acquisition.DownloadStrip`. |
```

In `.claude/skills/user-interface/SKILL.md` Component Inventory, add a row:

```markdown
| `download_strip/1` | `acquisition/download_strip.ex` | The one drawing of a download-client job: phase ladder, phase word, figure bar, facts, cancel (pursuit row, Other downloads, pursuit modal) | ✅ |
```

- [ ] **Step 3: Wiki**

In `~/src/media-centaur/media-centaur.wiki/`, find the Incoming page (grep `Other downloads`). Replace its description of the download row with: "Each download shows where it is: a short row of steps (fetch, download, verify, unpack, move for usenet; metadata, download for torrents) with the current step lit, the step's name, and a bar that fills when the client reports a figure and slides when it is working without one. Other downloads lists jobs in your clients that no pursuit claims, drawn the same way."

```sh
cd ~/src/media-centaur/media-centaur.wiki
git add -A
git commit -m "wiki: Incoming draws downloads by phase"
git push
```

- [ ] **Step 4: Commit**

```bash
git add docs/download-clients.md .claude/skills/user-interface/SKILL.md
git commit -m "docs: download phases and the download strip"
```

- [ ] **Step 5: Verify in the running app**

With a usenet download in flight: `~/scripts/agents/page-shot --url http://localhost:2160/incoming?zone=activity --wait-ms 3000 --viewport 1600x1000`, Read the PNG. If the headless probe lands on the profile picker, append the profile's selection the way `page-shot` callers in `scripts/` do, or ask the owner to look. Confirm the stage line's real format in `~/scripts/agents/mc-eval` output or the SABnzbd history while a job unpacks; if the format differs from "Unpacking: 45%" / "Verifying: 14/56", extend `Phase.stage_figure/1`'s two regexes and add the observed line to `phase_test.exs`.

---

## Self-review

- **Spec coverage.** Phase projection: Task 2. Driver facts (stage line, zero clock, placeholder name): Task 1. `DownloadProgress.phase`: Task 3. One strip with a story, three call sites: Tasks 5–8. Badge-vs-text resolved: Task 7 test. Modal bar resolved: Task 8. Stale story premise: Task 6. Status sentence figure: Task 9. Identity at grab, column rename, category, direct grabs: Plan 2 (`docs/superpowers/plans/2026-10-12-app-owned-grabs.md`), deliberately out of this plan.
- **Placeholders.** Task 9's helper names (`queue_item/1`, `derive_with_queue/3`) are stand-ins for the test file's own helpers and say so; everything else is literal.
- **Type consistency.** `Phase.of/1`, `word/1`, `step_word/1`, `text_class/1`, `working?/1`; `DownloadProgress.phase`; `download_strip/1` attrs `download`, `queue_item_id`, `cancel_title`, `cancel_armed_id`, `telemetry_age`, `bare`; `data-step` / `data-step-state` with values `landed` / `underway` / `ahead` — used identically in Tasks 5–8.
