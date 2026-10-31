defmodule MediaCentaur.Features.Runtime do
  @moduledoc """
  Starts and stops each feature's processes as its flag changes
  (`MediaCentaur.Features`, ADR-081), so a feature that is off runs nothing.

  Started by `MediaCentaur.Application` with `runtimes:` — a map from
  feature id to the children that are that feature's runtime (the
  application composes the lists; this module knows no feature by name).
  Each feature with children gets a one-for-one supervisor of them under
  this process's own `DynamicSupervisor`, started while the flag is on and
  terminated when it goes off. The controller reconciles at init and on
  every `{:setting_changed, "feature:<id>", _}` broadcast, the same way the
  Services toggles stop the pipeline and start the watchers live.

  `reconcile/1` is the synchronous form of the same pass, for a caller that
  needs the tree settled before it continues. `reset/1` puts every runtime
  at the registry's default **without reading the flag**: the test
  sandbox's check-in, where the database has been rolled back to the
  baseline and may not be read, calls it so a test that turned a feature
  off leaves the tree as it found it.

  An Oban job of a feature cannot be stopped this way — cron is fixed at
  boot — so it asks `Features.enabled?/1` at the top of `perform/1` and
  returns `:ok` while its feature is off.
  """

  use GenServer

  alias MediaCentaur.Features
  alias MediaCentaur.Settings

  @type runtimes :: %{optional(atom()) => [Supervisor.child_spec() | module() | {module(), term()}]}

  @doc """
  `runtimes:` the feature → children map; `name:` the registered name
  (`#{inspect(__MODULE__)}` by default; tests start their own).
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Starts and stops runtimes to match every flag, and returns once the tree is settled."
  @spec reconcile(GenServer.server()) :: :ok
  def reconcile(server \\ __MODULE__), do: GenServer.call(server, :reconcile)

  @doc "Starts and stops runtimes to match the registry defaults, reading no flag."
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset)

  @doc "Whether the feature's runtime is up."
  @spec running?(GenServer.server(), atom()) :: boolean()
  def running?(server \\ __MODULE__, id), do: GenServer.call(server, {:running?, id})

  @impl true
  def init(opts) do
    runtimes = Keyword.get(opts, :runtimes, %{})
    # Linked, so the supervisor and its features go down with this process.
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    :ok = Settings.subscribe()

    state = %{supervisor: supervisor, runtimes: runtimes, running: %{}}
    {:ok, apply_flags(state, &Features.enabled?/1)}
  end

  @impl true
  def handle_call(:reconcile, _from, state), do: {:reply, :ok, apply_flags(state, &Features.enabled?/1)}

  def handle_call(:reset, _from, state) do
    {:reply, :ok, apply_flags(state, fn id -> Features.get(id).default end)}
  end

  def handle_call({:running?, id}, _from, state) do
    {:reply, Map.has_key?(state.running, id), state}
  end

  @impl true
  def handle_info({:setting_changed, key, _value}, state) do
    if Features.feature_key?(key),
      do: {:noreply, apply_flags(state, &Features.enabled?/1)},
      else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # One pass over the map: start what should run and does not, stop what
  # runs and should not. `wanted?` is the flag, or the default on a reset.
  defp apply_flags(state, wanted?) do
    Enum.reduce(state.runtimes, state, fn {id, children}, state ->
      case {wanted?.(id), Map.fetch(state.running, id)} do
        {true, :error} -> start_feature(state, id, children)
        {false, {:ok, pid}} -> stop_feature(state, id, pid)
        _settled -> state
      end
    end)
  end

  defp start_feature(state, id, children) do
    spec = %{
      id: id,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor,
      restart: :permanent
    }

    {:ok, pid} = DynamicSupervisor.start_child(state.supervisor, spec)
    put_in(state.running[id], pid)
  end

  defp stop_feature(state, id, pid) do
    # A child already gone is already stopped.
    _ = DynamicSupervisor.terminate_child(state.supervisor, pid)
    %{state | running: Map.delete(state.running, id)}
  end
end
