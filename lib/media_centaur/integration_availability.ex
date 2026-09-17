defmodule MediaCentaur.IntegrationAvailability do
  use Boundary, deps: [MediaCentaur.Capabilities], exports: [Status]

  @moduledoc """
  Whether a metered integration can do its job right now.

  Every metered outbound request is preceded by a free question — is
  the integration up? — answered here. One `Status` per integration lives
  in `:persistent_term`, runtime-only: a restart starts everything up
  and the first request or probe corrects it. Free probes keep a down
  integration's status current (`MediaCentaur.Search.ProbeJob`); while
  up, real requests are the evidence.

  **One writer per integration.** The module that owns the client calls
  `report/3` — `MediaCentaur.Search.ProwlarrAvailability` for `:prowlarr`
  and both hand-offs. Everyone else reads.

  `available?/1` is the gate callers use: configured (`Capabilities`,
  the durable half — credentials present and the last "Test connection"
  passed) **and** up (this module, the runtime half). Neither half is
  folded into the other: one is settings, the other observation.

  Writes happen on a transition and on every down observation (so
  `observed_at` says when a down integration was last probed); an up
  observation on an up integration writes nothing — `:persistent_term`
  updates cost a global scan, and Prowlarr answers many times a minute.
  An integration nobody has observed yet has no `observed_at` at all.
  Transitions broadcast `{:integration_availability_changed, integration, state}`
  on `Topics.integration_availability_updates/0`.
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.Topics

  @integrations [:prowlarr, {:handoff, :usenet}, {:handoff, :torrent}, :tmdb]

  @doc """
  The download-client protocols the hand-off is tracked per — one
  `{:handoff, slot}` integration each. The writer and the probe both
  fold over this list.
  """
  @spec handoff_slots() :: [:usenet | :torrent]
  def handoff_slots, do: [:usenet, :torrent]

  @spec status(Status.integration()) :: Status.t()
  def status(integration) when integration in @integrations do
    case :persistent_term.get(key(integration), :unobserved) do
      :unobserved -> Status.initial(integration)
      %Status{} = status -> status
    end
  end

  @spec up?(Status.integration()) :: boolean()
  def up?(integration), do: integration |> status() |> Status.up?()

  @doc "Configured and up. The gate before a metered request."
  @spec available?(Status.integration()) :: boolean()
  def available?(:prowlarr), do: Capabilities.prowlarr_ready?() and up?(:prowlarr)

  def available?({:handoff, slot} = integration),
    do: Capabilities.prowlarr_ready?() and Capabilities.client_ready?(slot) and up?(integration)

  def available?(:tmdb), do: Capabilities.tmdb_ready?() and up?(:tmdb)

  @doc """
  Folds one observation in. `opts`: `:now` (tests), `:retry_at` (kept
  on a down status). Returns `{:changed, state}` on a transition,
  `:unchanged` otherwise.
  """
  @spec report(Status.integration(), Status.observation(), keyword()) ::
          :unchanged | {:changed, Status.state()}
  def report(integration, observation, opts \\ []) when integration in @integrations do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    {verdict, next} = Status.fold(status(integration), observation, now, opts)

    case {verdict, next.state} do
      {:unchanged, :up} ->
        :unchanged

      {:unchanged, _down} ->
        :persistent_term.put(key(integration), next)
        :unchanged

      {:changed, state} ->
        :persistent_term.put(key(integration), next)

        Topics.publish(
          Topics.integration_availability_updates(),
          {:integration_availability_changed, integration, state}
        )

        {:changed, state}
    end
  end

  defp key(integration), do: {__MODULE__, integration}
end
