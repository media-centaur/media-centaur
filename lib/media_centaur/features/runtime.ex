defmodule MediaCentaur.Features.Runtime do
  @moduledoc """
  Starts and stops each feature's processes as its flag changes
  (`MediaCentaur.Features`, ADR-081), so a feature that is off runs nothing.

  Started by `MediaCentaur.Application` with `runtimes:` — a map from
  feature id to the children that are that feature's runtime (the
  application composes the lists; this module knows no feature by name).
  Each feature is one `MediaCentaur.FlagSupervisor` under this Supervisor,
  its flag `Features.enabled?/1`, its cue the `{:setting_changed, _, _}`
  broadcast of its own key; the FlagSupervisor reads the flag at start and
  on each cue, the same mechanism the service start flags use.

  `reconcile/1` re-reads every flag now, for a caller that needs the tree
  settled before it continues. `reset/1` puts every runtime at the
  registry's default **without reading the flag**: the test sandbox's
  check-in, where the database has been rolled back to the baseline and may
  not be read, calls it so a test that turned a feature off leaves the tree
  as it found it.

  An Oban job of a feature cannot be stopped this way — cron is fixed at
  boot — so it asks `Features.enabled?/1` at the top of `perform/1` and
  returns `:ok` while its feature is off.
  """

  use Supervisor

  alias MediaCentaur.Features
  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Settings

  @type runtimes :: %{optional(atom()) => [Supervisor.child_spec() | module() | {module(), term()}]}

  @doc """
  `runtimes:` the feature → children map; `name:` the registered name
  (`#{inspect(__MODULE__)}` by default; tests start their own).
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    children =
      for {id, children} <- Keyword.get(opts, :runtimes, %{}) do
        key = Features.key(id)

        Supervisor.child_spec(
          {FlagSupervisor,
           flag: fn -> Features.enabled?(id) end,
           subscribe: &Settings.subscribe/0,
           relevant?: &match?({:setting_changed, ^key, _value}, &1),
           children: children,
           label: "the #{id} feature's processes"},
          id: id
        )
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Re-reads every feature's flag and starts or stops its runtime to match."
  @spec reconcile(Supervisor.supervisor()) :: :ok
  def reconcile(server \\ __MODULE__) do
    Enum.each(features(server), fn {_id, pid} -> FlagSupervisor.reconcile(pid) end)
  end

  @doc "Puts every feature's runtime at the registry default, reading no flag."
  @spec reset(Supervisor.supervisor()) :: :ok
  def reset(server \\ __MODULE__) do
    Enum.each(features(server), fn {id, pid} -> FlagSupervisor.force(pid, Features.get(id).default) end)
  end

  @doc "Whether the feature's runtime is up."
  @spec running?(Supervisor.supervisor(), atom()) :: boolean()
  def running?(server \\ __MODULE__, id) do
    case List.keyfind(features(server), id, 0) do
      {^id, pid} -> FlagSupervisor.running?(pid)
      nil -> false
    end
  end

  defp features(server) do
    for {id, pid, :supervisor, _modules} <- Supervisor.which_children(server), is_pid(pid), do: {id, pid}
  end
end
