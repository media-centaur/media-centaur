defmodule MediaCentaur.NewReleases.RefreshJob do
  @moduledoc """
  The daily shelf refresh (`MediaCentaur.NewReleases.refresh/1`), also run
  once at boot (`@reboot`) so a shelf that fell behind while the app was
  off fills then rather than at the next daily run. Held while TMDB is
  unavailable like every metered job — but held as a snooze at the probe's
  cadence, not completed: the boot run lands seconds after start, before
  the capability cache is warm, and a daily job that gave up there would
  leave the shelf empty for a day. Nothing is lost either way, because
  the membership is a stored fact. Cron: daily before the retention sweep.
  Unique across available, scheduled and executing, so the boot run beside
  the cron, or beside a snoozing run, is one run.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.NewReleases
  alias MediaCentaur.TMDB.ProbeJob

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if IntegrationAvailability.available?(:tmdb) do
      with {:ok, _count} <- NewReleases.refresh(Date.utc_today()), do: :ok
    else
      Log.debug(:tmdb, "new releases refresh held — TMDB is unavailable")
      {:snooze, ProbeJob.cadence_seconds()}
    end
  end
end
