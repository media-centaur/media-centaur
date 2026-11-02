defmodule MediaCentaur.NewReleases.RefreshJob do
  @moduledoc """
  The shelf refresh (`MediaCentaur.NewReleases.refresh/1`), enqueued by
  `Scheduler` — the Discovery feature's runtime child — when the runtime
  starts and daily at 04:03 UTC after that, never by Oban's cron: with the
  feature off nothing inserts it (ADR-081). It still asks the flag, for a
  run already waiting when the flag flipped off. Held while TMDB is
  unavailable like every metered job — but held as a snooze at the probe's
  cadence, not completed: the start's run lands seconds after boot, before
  the capability cache is warm, and a run that gave up there would leave
  the shelf empty for a day. Nothing is lost either way, because the
  membership is a stored fact. Unique across available, scheduled and
  executing, so a start beside a scheduled run, or beside a snoozing one,
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
