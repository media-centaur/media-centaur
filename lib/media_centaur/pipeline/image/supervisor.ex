defmodule MediaCentaur.Pipeline.Image.Supervisor do
  @moduledoc """
  The artwork pipeline's supervisor, `:rest_for_one`:

    1. `Pipeline.Image.Stats` — a crash restarts everything below it (clean
       telemetry re-attach);
    2. `MediaCentaur.Pipeline.Image.FlagSupervisor` — the
       `start_image_pipeline` flag's children, `Pipeline.Image` (Broadway)
       and `Pipeline.Image.RetryScheduler`. Absent while the flag is off.

  The flag (`Settings.Services.start?(:start_image_pipeline)`) is the one
  owner of "artwork downloads are on"; `pipeline_running?/0` is the tree's
  answer. `set_enabled/1` is what the Settings toggle does.
  """
  use Supervisor

  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Services

  @flag :start_image_pipeline
  @flag_supervisor MediaCentaur.Pipeline.Image.FlagSupervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    flag_key = Services.key(@flag)

    children = [
      MediaCentaur.Pipeline.Image.Stats,
      {FlagSupervisor,
       name: @flag_supervisor,
       flag: fn -> Services.start?(@flag) end,
       subscribe: &Settings.subscribe/0,
       relevant?: &match?({:setting_changed, ^flag_key, _value}, &1),
       children: [MediaCentaur.Pipeline.Image, MediaCentaur.Pipeline.Image.RetryScheduler],
       label: "the artwork pipeline",
       component: :pipeline}
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end

  @doc """
  Turns artwork downloads on or off now and for every later boot: persists
  the start flag (`Settings.Services`) and reconciles the flag's children at
  once. What the Settings toggle does.
  """
  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled?) when is_boolean(enabled?) do
    Services.set(@flag, enabled?)
    FlagSupervisor.reconcile(@flag_supervisor)
  end

  @doc "Whether artwork downloads are on: the Broadway process is running."
  @spec pipeline_running?() :: boolean()
  def pipeline_running?, do: FlagSupervisor.running?(@flag_supervisor)
end
