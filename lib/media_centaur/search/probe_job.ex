defmodule MediaCentaur.Search.ProbeJob do
  @moduledoc """
  Keeps a down integration's availability fresh with free requests.

  Enqueued by `MediaCentaur.Search.ProwlarrAvailability` on a transition
  to down, one job per integration (`unique` on `integration`). Each run
  probes — the indexer roster read for `"prowlarr"`,
  `downloadclient/testall` for `"handoff"` — which reports through the
  same observers real requests use, then snoozes at the cadence while
  still down and completes on up. While up nothing probes: real requests
  are the evidence. For a blind Prowlarr the snooze waits for Prowlarr's
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

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Search.ProwlarrAvailability

  @cadence_seconds 60
  @max_snooze_seconds 60 * 60
  @slots [:usenet, :torrent]

  @doc "Seconds between probes while down; also the snooze of held work."
  @spec cadence_seconds() :: pos_integer()
  def cadence_seconds, do: @cadence_seconds

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"integration" => "prowlarr"}}) do
    _health = IndexerHealth.check()

    case IntegrationAvailability.status(:prowlarr) do
      %{state: :up} ->
        :ok

      %{state: {:down, _since, _reason}, retry_at: retry_at} ->
        {:snooze, snooze_for(retry_at, DateTime.utc_now())}
    end
  end

  def perform(%Oban.Job{args: %{"integration" => "handoff"}}) do
    _outcome = ProwlarrAvailability.probe_handoff()

    if Enum.all?(@slots, &IntegrationAvailability.up?({:handoff, &1})),
      do: :ok,
      else: {:snooze, @cadence_seconds}
  end

  @doc "The next probe delay: the cadence, or Prowlarr's own retry time when later, capped."
  @spec snooze_for(DateTime.t() | nil, DateTime.t()) :: pos_integer()
  def snooze_for(nil, _now), do: @cadence_seconds

  def snooze_for(%DateTime{} = retry_at, %DateTime{} = now) do
    retry_at |> DateTime.diff(now, :second) |> max(@cadence_seconds) |> min(@max_snooze_seconds)
  end
end
