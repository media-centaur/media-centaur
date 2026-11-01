defmodule MediaCentaur.NewReleases.RefreshJob do
  @moduledoc """
  The daily shelf refresh (`MediaCentaur.NewReleases.refresh/1`). Does
  nothing while the Discovery feature is off (ADR-081: cron is fixed at
  boot, so the job is where the flag is asked). Held while TMDB is
  unavailable like every metered job — but held as a snooze at the probe's
  cadence, not completed: the kickoff's run lands seconds after boot,
  before the capability cache is warm, and a daily job that gave up there
  would leave the shelf empty for a day. Nothing is lost either way,
  because the membership is a stored fact. Cron: daily before the
  retention sweep; also enqueued by `Kickoff` when the feature's runtime
  starts. Unique across available, scheduled and executing, so a kickoff
  beside the cron, or beside a snoozing run, is one run.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.NewReleases
  alias MediaCentaur.TMDB.ProbeJob

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cond do
      not Features.enabled?(:discovery) ->
        :ok

      not IntegrationAvailability.available?(:tmdb) ->
        Log.debug(:tmdb, "new releases refresh held — TMDB is unavailable")
        {:snooze, ProbeJob.cadence_seconds()}

      true ->
        with {:ok, _count} <- NewReleases.refresh(Date.utc_today()), do: :ok
    end
  end
end
