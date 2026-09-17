defmodule MediaCentaur.Search.ProbeJob do
  @moduledoc """
  Keeps a down integration's availability fresh with free requests.

  Enqueued by `MediaCentaur.Search.ProwlarrAvailability` on a transition
  to down, one job per integration (`unique` on `integration`). Each run
  probes — the indexer roster read for `"prowlarr"`,
  `downloadclient/testall` for `"handoff"` — which reports through the
  same observers real requests use, then snoozes at the cadence while
  still down and completes on up. A hand-off run also completes when
  Prowlarr is no longer configured: the probe cannot answer without it,
  and a job that only ever snoozes would outlive the integration.

  While up nothing probes: real requests are the evidence. For a blind Prowlarr the snooze waits for Prowlarr's
  own `retry_at` when that is later, capped at an hour so a stale time
  never silences probing.

  Oban is the timer because it already is one; a snooze is a database
  write, free. On the `:maintenance` queue (concurrency 1): a probe is
  milliseconds, and two at once would serialise harmlessly.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:integration],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Search.ProwlarrAvailability

  @cadence_seconds 60
  @max_snooze_seconds 60 * 60

  @doc "Seconds between probes while down; also the snooze of held work."
  @spec cadence_seconds() :: pos_integer()
  def cadence_seconds, do: @cadence_seconds

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"integration" => "prowlarr"}}) do
    probe("prowlarr", fn ->
      _health = IndexerHealth.check()

      case IntegrationAvailability.status(:prowlarr) do
        %{state: :up} ->
          :ok

        %{state: {:down, _since, _reason}, retry_at: retry_at} ->
          {:snooze, snooze_for(retry_at, DateTime.utc_now())}
      end
    end)
  end

  def perform(%Oban.Job{args: %{"integration" => "handoff"}}) do
    probe("handoff", fn ->
      # Re-read on every run: a hand-off probe can only ever be
      # inconclusive once the user removes Prowlarr, so without this the
      # job would snooze forever with nothing left to answer it.
      if Capabilities.prowlarr_ready?() do
        _outcome = ProwlarrAvailability.probe_handoff()

        if Enum.all?(
             IntegrationAvailability.handoff_slots(),
             &IntegrationAvailability.up?({:handoff, &1})
           ),
           do: :ok,
           else: {:snooze, @cadence_seconds}
      else
        :ok
      end
    end)
  end

  # A probe that breaks must not burn an attempt: three raises would
  # discard the job and leave a down integration with nothing watching
  # it, so held work would stall with no path back. Snooze instead.
  defp probe(integration, fun) do
    fun.()
  rescue
    error ->
      Log.warning(:acquisition, "probe failed for #{integration} — #{Exception.message(error)}",
        mc_incident: :skip
      )

      {:snooze, @cadence_seconds}
  catch
    :exit, reason ->
      Log.warning(:acquisition, "probe exited for #{integration} — #{inspect(reason)}",
        mc_incident: :skip
      )

      {:snooze, @cadence_seconds}
  end

  @doc "The next probe delay: the cadence, or Prowlarr's own retry time when later, capped."
  @spec snooze_for(DateTime.t() | nil, DateTime.t()) :: pos_integer()
  def snooze_for(nil, _now), do: @cadence_seconds

  def snooze_for(%DateTime{} = retry_at, %DateTime{} = now) do
    retry_at |> DateTime.diff(now, :second) |> max(@cadence_seconds) |> min(@max_snooze_seconds)
  end
end
