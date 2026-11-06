defmodule MediaCentaur.Acquisition.Jobs.PlanGrab do
  @moduledoc """
  Plans a title's open wants shortly after a person raises it to Grab
  (`DropPlanner.run_for/2`), instead of leaving its backlog for the next
  tracking sweep. `Reactor.Handlers.rung_changed/1` schedules it
  twenty seconds out, so a Grab clicked by accident and moved back inside
  that window plans nothing: the job reads the rung when it runs.

  A lost job costs only the wait — the sweep plans the same wants on its
  next pass (`DropPlanner.run_tick/1`) — so it is scheduled from the
  rung-change broadcast rather than in the rung's transaction (ADR-076).

  Unique per title among jobs that have not started; a second raise
  inside the window moves the waiting job to the later time.
  """

  use Oban.Worker,
    queue: :acquisition,
    unique: [
      period: :infinity,
      keys: [:tmdb_id, :media_type],
      states: [:available, :scheduled, :retryable]
    ],
    replace: [scheduled: [:scheduled_at]]

  alias MediaCentaur.Acquisition.DropPlanner

  @delay_seconds 20

  @doc "The job for a title just raised to Grab, scheduled #{@delay_seconds} seconds out."
  @spec for_title(integer(), :movie | :tv_series) :: Oban.Job.changeset()
  def for_title(tmdb_id, media_type) do
    new(%{"tmdb_id" => tmdb_id, "media_type" => Atom.to_string(media_type)},
      schedule_in: @delay_seconds
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tmdb_id" => tmdb_id, "media_type" => media_type}}) do
    DropPlanner.run_for(tmdb_id, media_type(media_type))
  end

  defp media_type("movie"), do: :movie
  defp media_type("tv_series"), do: :tv_series
end
