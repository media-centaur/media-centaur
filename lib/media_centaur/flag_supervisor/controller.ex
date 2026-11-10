defmodule MediaCentaur.FlagSupervisor.Controller do
  @moduledoc """
  `MediaCentaur.FlagSupervisor`'s controller: reads the flag, starts the
  children as one group under the sibling `DynamicSupervisor`, stops the
  group when the flag goes off. The group's pid is state here; whether the
  group runs is asked of the DynamicSupervisor, so a controller restart
  finds the group it did not start.
  """

  use GenServer

  require MediaCentaur.Log, as: Log

  defstruct [
    :supervisor,
    :children_supervisor,
    :flag,
    :relevant?,
    :children,
    :label,
    :component,
    suspended?: false
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    state = %__MODULE__{
      supervisor: Keyword.fetch!(opts, :supervisor),
      flag: Keyword.fetch!(opts, :flag),
      relevant?: Keyword.get(opts, :relevant?, fn _message -> true end),
      children: Keyword.fetch!(opts, :children),
      label: Keyword.fetch!(opts, :label),
      component: Keyword.get(opts, :component, :system)
    }

    case Keyword.get(opts, :subscribe) do
      nil -> :ok
      subscribe -> subscribe.()
    end

    # The sibling DynamicSupervisor is looked up once the parent has finished
    # starting its children: a call to the parent from inside `init/1` would
    # wait on a supervisor that is itself waiting on this start. The first
    # flag read is `FlagSupervisor.start_link/1`'s synchronous reconcile.
    {:ok, state, {:continue, :resolve}}
  end

  @impl true
  def handle_continue(:resolve, state) do
    {:noreply,
     %{state | children_supervisor: MediaCentaur.FlagSupervisor.children_supervisor(state.supervisor)}}
  end

  @impl true
  def handle_call(:running?, _from, state), do: {:reply, group(state) != nil, state}

  def handle_call(:children, _from, state) do
    pids =
      case group(state) do
        nil ->
          []

        group ->
          group
          |> Supervisor.which_children()
          |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
          |> Enum.reverse()
      end

    {:reply, pids, state}
  end

  def handle_call(:reconcile, _from, %{suspended?: true} = state), do: {:reply, :ok, state}
  def handle_call(:reconcile, _from, state), do: {:reply, :ok, apply_wanted(state, state.flag.())}

  def handle_call({:force, wanted?}, _from, state), do: {:reply, :ok, apply_wanted(state, wanted?)}

  def handle_call(:suspend, _from, state) do
    {:reply, :ok, %{apply_wanted(state, false) | suspended?: true}}
  end

  def handle_call(:resume, _from, state) do
    state = %{state | suspended?: false}
    {:reply, :ok, apply_wanted(state, state.flag.())}
  end

  # A message the flag's owner broadcasts for something else is not a cue:
  # reading the flag can cost a database read, and under the test sandbox a
  # read from this process for a test that did not write the flag has no
  # connection to use.
  @impl true
  def handle_info(_message, %{suspended?: true} = state), do: {:noreply, state}

  def handle_info(message, state) do
    if state.relevant?.(message),
      do: {:noreply, apply_wanted(state, state.flag.())},
      else: {:noreply, state}
  end

  defp apply_wanted(state, wanted?) do
    case {wanted?, group(state)} do
      {true, nil} -> start_group(state)
      {false, group} when is_pid(group) -> stop_group(state, group)
      _settled -> state
    end
  end

  # The one child of the DynamicSupervisor is the group, a one_for_one
  # Supervisor of the flag's children.
  defp group(state) do
    case DynamicSupervisor.which_children(state.children_supervisor) do
      [{_id, pid, :supervisor, _modules}] when is_pid(pid) -> pid
      _none -> nil
    end
  end

  defp start_group(state) do
    spec = %{
      id: :group,
      start: {Supervisor, :start_link, [state.children, [strategy: :one_for_one]]},
      type: :supervisor,
      restart: :permanent
    }

    case DynamicSupervisor.start_child(state.children_supervisor, spec) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Log.warning(state.component, "could not start #{state.label}: #{inspect(reason)}")
    end

    state
  end

  defp stop_group(state, group) do
    _ = DynamicSupervisor.terminate_child(state.children_supervisor, group)
    state
  end
end
