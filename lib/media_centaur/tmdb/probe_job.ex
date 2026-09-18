defmodule MediaCentaur.TMDB.ProbeJob do
  @moduledoc """
  Keeps a down TMDB's availability fresh with one cheap request.

  Enqueued by `MediaCentaur.TMDB.Availability` on a transition to down.
  Each run asks `Client.configuration/1` — static image-CDN metadata,
  always reloaded past the response cache, the same call the "Test
  connection" button makes — which reports through
  `Availability.observe_request/1` like any other request. It then
  snoozes at the cadence while still down, and completes on up. A run
  also completes when TMDB is no longer configured: the probe cannot
  answer without a key, and a job that only ever snoozes would outlive
  the integration.

  TMDB is metered, so the probe is one request every five minutes — the
  one metered request this design spends so that the refresh cycle and
  the artwork warm spend none. While up nothing probes: real requests are
  the evidence.

  On the `:maintenance` queue (concurrency 1), `unique` so two never
  queue at once. Oban is the timer because it already is one; a snooze is
  a database write, free.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.Client

  @cadence_seconds 300

  @doc "Seconds between probes while down; also the wait of the work this holds."
  @spec cadence_seconds() :: pos_integer()
  def cadence_seconds, do: @cadence_seconds

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Re-read on every run: without this the job would snooze forever
    # after the user removes the key, with nothing left to answer it.
    if Capabilities.tmdb_ready?(), do: probe(), else: :ok
  end

  # A probe that breaks must not burn an attempt: three raises would
  # discard the job and leave a down integration with nothing watching
  # it, so held work would stall with no path back. Snooze instead.
  defp probe do
    _answer = Client.configuration()

    if IntegrationAvailability.up?(:tmdb), do: :ok, else: {:snooze, @cadence_seconds}
  rescue
    error ->
      Log.warning(:tmdb, "probe failed for tmdb — #{Exception.message(error)}", mc_incident: :skip)
      {:snooze, @cadence_seconds}
  catch
    :exit, reason ->
      Log.warning(:tmdb, "probe exited for tmdb — #{inspect(reason)}", mc_incident: :skip)
      {:snooze, @cadence_seconds}
  end
end
