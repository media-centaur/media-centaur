defmodule MediaCentaur.Acquisition.Pursuits.StatusContext do
  @moduledoc """
  The page-level facts every pursuit's status is derived against.

  Deriving one pursuit's status needs facts that are properties of the
  *system*, not of the pursuit: the clock, the hand-off window, whether an
  integration is holding all work, the download client's queue and whether
  that queue can be trusted, and which files are sitting in review. Reading
  them per row would mean a Settings query, a review-queue scan, an
  availability check and two `:persistent_term` reads for every card on the
  page.

  `load/0` reads them once, and reads the download client's `%QueueState{}`
  once for both the items and the grade — they are two faces of one snapshot,
  and reading them separately is how a page ends up deciding that a client is
  answering while rendering the queue it had before it stopped.

  `PursuitStatus.derive/6` and `Pursuits.Stage.of/4` take the result, so their
  inputs are explicit rather than hidden behind module calls — which is what
  keeps them pure functions that tests can drive without a database or a
  running `QueueMonitor`.
  """

  alias MediaCentaur.Acquisition.Pursuits.Thresholds
  alias MediaCentaur.Downloads.{QueueItem, QueueMonitor, QueueState}
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Review

  @enforce_keys [:now, :handoff_window_minutes, :client_reachable?, :pending_file_paths]
  defstruct [
    :now,
    :handoff_window_minutes,
    :held_integration,
    :pending_file_paths,
    client_reachable?: true,
    queue_items: []
  ]

  @type t :: %__MODULE__{
          now: DateTime.t(),
          handoff_window_minutes: pos_integer(),
          held_integration: :prowlarr | nil,
          client_reachable?: boolean(),
          pending_file_paths: MapSet.t(String.t()),
          queue_items: [QueueItem.t()]
        }

  @doc """
  Reads every page-level fact once: one Settings query, one review-queue scan,
  one availability check, one queue snapshot.
  """
  @spec load() :: t()
  def load, do: from_queue_state(QueueMonitor.state())

  @doc """
  Builds a context around a `%QueueState{}` the caller already holds — the
  LiveView's queue tick, or a test that wants a known queue. Everything else
  is read as in `load/0`.
  """
  @spec from_queue_state(QueueState.t()) :: t()
  def from_queue_state(%QueueState{} = queue_state) do
    %__MODULE__{
      now: DateTime.utc_now(:second),
      handoff_window_minutes: Thresholds.load().handoff_window_minutes,
      held_integration: held_integration(),
      client_reachable?: QueueState.answering?(queue_state),
      pending_file_paths: Review.pending_file_paths(),
      queue_items: queue_state.items
    }
  end

  # A Prowlarr hold is global and leaves no trace on any target — no request,
  # no attempt, no stamp — so the view model has to be told. A hand-off hold is
  # per-pursuit and `Jobs.PursueTarget` records it on the target it holds; the
  # view model reads that stamp like any other outcome.
  defp held_integration do
    if !IntegrationAvailability.up?(:prowlarr), do: :prowlarr
  end
end
