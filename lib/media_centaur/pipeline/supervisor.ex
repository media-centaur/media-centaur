defmodule MediaCentaur.Pipeline.Supervisor do
  @moduledoc """
  The import pipeline's supervisor, `:rest_for_one`:

    1. `Pipeline.Stats` — a crash restarts everything below it (clean
       telemetry re-attach);
    2. `Pipeline.Discovery.InflightSet` — owns the ETS dedup table; above
       the Broadway children so the table outlives a producer crash;
    3. `Pipeline.TmdbProjection`, in instances that run background
       services — the TMDB-store listener that re-derives library records;
    4. `MediaCentaur.Pipeline.FlagSupervisor` — the `start_pipeline` flag's
       children, `Pipeline.Discovery` and `Pipeline.Import`. Absent while
       the flag is off, so a Stats crash cannot start a pipeline the user
       turned off.

  The flag (`Settings.Services.start?(:start_pipeline)`) is the one owner of
  "the pipeline is on"; `pipeline_running?/0` is the tree's answer.
  `set_enabled/1` is what the Settings toggle does.
  """
  use Supervisor

  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Services

  @flag :start_pipeline
  @flag_supervisor MediaCentaur.Pipeline.FlagSupervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    flag_key = Services.key(@flag)

    projection =
      if MediaCentaur.Settings.Config.get(:background_services),
        do: [MediaCentaur.Pipeline.TmdbProjection],
        else: []

    children =
      [
        MediaCentaur.Pipeline.Stats,
        MediaCentaur.Pipeline.Discovery.InflightSet
      ] ++
        projection ++
        [
          {FlagSupervisor,
           name: @flag_supervisor,
           flag: fn -> Services.start?(@flag) end,
           subscribe: &Settings.subscribe/0,
           relevant?: &match?({:setting_changed, ^flag_key, _value}, &1),
           children: [MediaCentaur.Pipeline.Discovery, MediaCentaur.Pipeline.Import],
           label: "the import pipeline",
           component: :pipeline}
        ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end

  @doc """
  Turns the pipeline on or off now and for every later boot: persists the
  start flag (`Settings.Services`) and reconciles the flag's children at
  once. What the Settings toggle does.
  """
  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled?) when is_boolean(enabled?) do
    Services.set(@flag, enabled?)
    FlagSupervisor.reconcile(@flag_supervisor)
  end

  @doc "Whether the pipeline is on: both Broadway processes are running."
  @spec pipeline_running?() :: boolean()
  def pipeline_running?, do: FlagSupervisor.running?(@flag_supervisor)
end
