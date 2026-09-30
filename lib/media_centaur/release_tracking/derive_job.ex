defmodule MediaCentaur.ReleaseTracking.DeriveJob do
  @moduledoc """
  Derives a title's release-tracking machinery from its rung
  (`ReleaseTracking.derive_from_rung/3`). `ReleaseTracking.set_rung/3`
  inserts it in the transaction that writes the rung, so a stored rung
  always has its derivation owed (ADR-077); it used to run on a
  fire-and-forget task, which a crash lost — leaving Follow with no tracked
  title, for good (campaign durable-work, F7).

  The job reads the rung when it runs, so the latest of several quick
  changes is the one derived. A TMDB failure fetching the calendar returns
  an error, and Oban asks again.
  """

  # One derivation per title among jobs not yet started (ADR-077, rule 6):
  # the waiting one reads the latest rung.
  use Oban.Worker,
    queue: :maintenance,
    unique: [
      period: :infinity,
      keys: [:tmdb_id, :media_type],
      states: [:available, :scheduled, :retryable]
    ]

  alias MediaCentaur.ReleaseTracking

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    ReleaseTracking.derive_from_rung(args["tmdb_id"], media_type(args["media_type"]), %{
      start_season: args["start_season"],
      start_episode: args["start_episode"]
    })
  end

  defp media_type("movie"), do: :movie
  defp media_type("tv_series"), do: :tv_series
end
