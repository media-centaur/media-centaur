defmodule MediaCentaur.Availability do
  use Boundary, deps: [MediaCentaur.Capabilities], exports: [Status]

  @moduledoc """
  Whether a metered dependency can do its job right now.

  Every metered outbound request is preceded by a free question — is
  the dependency up? — answered here. One `Status` per dependency lives
  in `:persistent_term`, runtime-only: a restart starts everything up
  and the first request or probe corrects it. Free probes keep a down
  dependency's status current (`MediaCentaur.Search.ProbeJob`); while
  up, real requests are the evidence.

  **One writer per dependency.** The module that owns the client calls
  `report/3` — `MediaCentaur.Search.ProwlarrAvailability` for `:prowlarr`
  and both hand-offs. Everyone else reads.

  `available?/1` is the gate callers use: configured (`Capabilities`,
  the durable half — credentials present and the last "Test connection"
  passed) **and** up (this module, the runtime half). Neither half is
  folded into the other: one is settings, the other observation.

  Writes happen on a transition and on every down observation (so
  `observed_at` says when a down dependency was last probed); an up
  observation on an up dependency writes nothing — `:persistent_term`
  updates cost a global scan, and Prowlarr answers many times a minute.
  Transitions broadcast `{:availability_changed, dependency, state}` on
  `Topics.availability_updates/0`.
  """

  alias MediaCentaur.Availability.Status
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Topics

  @dependencies [:prowlarr, {:handoff, :usenet}, {:handoff, :torrent}, :tmdb]

  @doc "Every dependency this module tracks."
  @spec dependencies() :: [Status.dependency()]
  def dependencies, do: @dependencies

  @spec status(Status.dependency()) :: Status.t()
  def status(dependency) when dependency in @dependencies do
    :persistent_term.get(key(dependency), nil) || Status.initial(dependency, DateTime.utc_now())
  end

  @spec up?(Status.dependency()) :: boolean()
  def up?(dependency), do: dependency |> status() |> Status.up?()

  @doc "Configured and up. The gate before a metered request."
  @spec available?(Status.dependency()) :: boolean()
  def available?(:prowlarr), do: Capabilities.prowlarr_ready?() and up?(:prowlarr)

  def available?({:handoff, slot} = dependency),
    do: Capabilities.prowlarr_ready?() and Capabilities.client_ready?(slot) and up?(dependency)

  def available?(:tmdb), do: Capabilities.tmdb_ready?() and up?(:tmdb)

  @doc """
  Folds one observation in. `opts`: `:now` (tests), `:retry_at` (kept
  on a down status). Returns `{:changed, state}` on a transition,
  `:unchanged` otherwise.
  """
  @spec report(Status.dependency(), Status.observation(), keyword()) ::
          :unchanged | {:changed, Status.state()}
  def report(dependency, observation, opts \\ []) when dependency in @dependencies do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    {verdict, next} = Status.fold(status(dependency), observation, now, opts)

    case {verdict, next.state} do
      {:unchanged, :up} ->
        :unchanged

      {:unchanged, _down} ->
        :persistent_term.put(key(dependency), next)
        :unchanged

      {:changed, state} ->
        :persistent_term.put(key(dependency), next)
        Topics.publish(Topics.availability_updates(), {:availability_changed, dependency, state})
        {:changed, state}
    end
  end

  defp key(dependency), do: {__MODULE__, dependency}
end
