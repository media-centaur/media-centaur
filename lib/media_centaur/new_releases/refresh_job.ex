defmodule MediaCentaur.NewReleases.RefreshJob do
  @moduledoc """
  The daily shelf refresh (`MediaCentaur.NewReleases.refresh/1`). Does
  nothing while the Discovery feature is off (ADR-081: cron is fixed at
  boot, so the job is where the flag is asked), and is held while TMDB is
  unavailable like every metered job: the next run tries again, and
  nothing is lost because the membership is a stored fact. Cron: daily
  before the retention sweep; also enqueued by `Kickoff` when the
  feature's runtime starts. Unique, so a kickoff landing beside the cron
  is one run.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.NewReleases

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cond do
      not Features.enabled?(:discovery) ->
        :ok

      not IntegrationAvailability.available?(:tmdb) ->
        Log.debug(:tmdb, "new releases refresh held — TMDB is unavailable")
        :ok

      true ->
        with {:ok, _count} <- NewReleases.refresh(Date.utc_today()), do: :ok
    end
  end
end
