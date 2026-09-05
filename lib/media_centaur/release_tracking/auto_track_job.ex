defmodule MediaCentaur.ReleaseTracking.AutoTrackJob do
  @moduledoc """
  Oban worker that runs `ReleaseTracking.AutoTrack` for a batch of
  library entity ids — the TMDB work an `entities_changed` broadcast
  implies, taken off the listener so an import never waits on the
  network.
  """
  use Oban.Worker, queue: :acquisition, max_attempts: 3

  alias MediaCentaur.ReleaseTracking.AutoTrack

  @doc "Schedules auto-tracking for `entity_ids`."
  @spec enqueue([Ecto.UUID.t()]) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(entity_ids) when is_list(entity_ids) do
    %{entity_ids: entity_ids}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entity_ids" => entity_ids}}) do
    AutoTrack.run(entity_ids)
  end
end
