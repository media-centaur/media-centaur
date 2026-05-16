defmodule MediaCentarr.Library.Progress.Events do
  @moduledoc """
  Typed payloads broadcast on the `library:progress` topic
  (Library Schema v2 Phase 3 Task D, ADR-041).

  `MediaCentarr.Library.Progress.Worker` is the sole publisher; every
  message flows through `broadcast/1` to keep the topic's contract
  enforceable. Consumers subscribe via `MediaCentarr.Topics.library_progress/0`
  and pattern-match on the tagged tuples described below.

  ## Why this exists

  `playback:events` carries playback *runtime* events (state changes,
  failures, position broadcasts from MpvSession) — that topic is
  owned by the Playback context. Progress-flush events come from the
  Library context (the new Pillar-2 source-of-truth for watch
  progress) and would create a cross-context dependency direction
  inversion if published on `playback:events`. Splitting the
  progress-projection events onto a Library-owned topic keeps the
  boundary direction clean.
  """

  alias MediaCentarr.Topics

  defmodule ProgressTicked do
    @moduledoc """
    Hot-path position tick from `Library.Progress.record/3`. Carries
    the `playable_item_id` and current `position_seconds` so
    projections that only need to refresh on activity (Continue
    Watching, Detail) can react in microseconds without preloading
    the full entity.
    """
    @enforce_keys [:playable_item_id, :position_seconds]
    defstruct [:playable_item_id, :position_seconds]

    @type t :: %__MODULE__{
            playable_item_id: String.t(),
            position_seconds: float()
          }
  end

  defmodule ProgressFlushed do
    @moduledoc """
    The `Library.Progress.Worker` flushed the dirty row for
    `playable_item_id` to `library_watch_progress`. Deterministic
    sync hook for tests and for projections that want to react only
    after persistence.
    """
    @enforce_keys [:playable_item_id]
    defstruct [:playable_item_id]

    @type t :: %__MODULE__{playable_item_id: String.t()}
  end

  defmodule ProgressHydrated do
    @moduledoc """
    The `Library.Progress.Worker` finished hydrating its in-memory
    table from `library_watch_progress` on `init/1`. Deterministic
    boot-order hook for tests; `count` is the number of in-progress
    rows loaded.
    """
    @enforce_keys [:count]
    defstruct [:count]

    @type t :: %__MODULE__{count: non_neg_integer()}
  end

  @doc """
  Broadcast a typed Library.Progress event on the `library:progress`
  topic. Each clause pairs a struct with the tagged-tuple shape
  subscribers pattern-match against — this is the only place where
  the topic is published to.
  """
  @spec broadcast(ProgressTicked.t() | ProgressFlushed.t() | ProgressHydrated.t()) ::
          :ok | {:error, term()}
  def broadcast(%ProgressTicked{} = event), do: do_broadcast({:progress_ticked, event})
  def broadcast(%ProgressFlushed{} = event), do: do_broadcast({:progress_flushed, event})
  def broadcast(%ProgressHydrated{} = event), do: do_broadcast({:progress_hydrated, event})

  defp do_broadcast(message) do
    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.library_progress(), message)
  end
end
