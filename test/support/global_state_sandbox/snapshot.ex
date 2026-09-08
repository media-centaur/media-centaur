defmodule MediaCentaur.GlobalStateSandbox.Snapshot do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The value `MediaCentaur.GlobalStateSandbox` compares and restores: the
  machine's global state, as far as a test can observe it, at one instant.

  Two kinds of store, by what the harness can do about a difference:

  * **restorable** — `persistent_term` and `application_env`. A difference
    from the baseline is put back at check-in without comment.
  * **verified** — `registered`, `ets`, `tasks`, `stub_orphans` and
    `probes`. The harness cannot put these back, so a difference fails the
    test that made it.

  The app's share of each store is derived, never listed: `:persistent_term`
  keys and registered names under the `MediaCentaur` namespace, the
  `:media_centaur` application env, named ETS tables owned by an app
  process (registered under the namespace, or started from a module in
  it), every child of `MediaCentaur.TaskSupervisor`, and every
  `cannot find mock/stub` crash logged since the last check-in
  (`MediaCentaur.GlobalStateSandbox.StubOrphans`). Probes are the one
  listed part — the `{:probe, mfa}` dispositions — because a singleton's
  observable state has no namespace to derive it from.
  """

  @type store ::
          :persistent_term | :application_env | :registered | :ets | :tasks | :stub_orphans | :probe
  @type leak :: {store(), key :: term(), baseline :: term(), now :: term()}
  @type t :: %__MODULE__{
          persistent_term: %{term() => term()},
          application_env: %{atom() => term()},
          registered: %{atom() => pid()},
          ets: %{atom() => non_neg_integer()},
          tasks: [pid()],
          stub_orphans: [String.t()],
          probes: %{atom() => term()}
        }

  defstruct persistent_term: %{},
            application_env: %{},
            registered: %{},
            ets: %{},
            tasks: [],
            stub_orphans: [],
            probes: %{}

  @namespace "Elixir.MediaCentaur"

  @doc "Takes a snapshot now. `probes` maps a disposition id to the mfa that reads it."
  @spec take(%{atom() => mfa()}) :: t()
  def take(probes) do
    %__MODULE__{
      persistent_term: owned_terms(),
      application_env: Map.new(Application.get_all_env(:media_centaur)),
      registered: registered_names(),
      ets: owned_tables(),
      tasks: Task.Supervisor.children(MediaCentaur.TaskSupervisor),
      stub_orphans: MediaCentaur.GlobalStateSandbox.StubOrphans.list(),
      probes:
        Map.new(probes, fn {id, {module, function, args}} -> {id, apply(module, function, args)} end)
    }
  end

  @doc "Differences in the stores the harness can put back."
  @spec restorable_diff(t(), t()) :: [leak()]
  def restorable_diff(baseline, now) do
    map_diff(:persistent_term, baseline.persistent_term, now.persistent_term) ++
      map_diff(:application_env, baseline.application_env, now.application_env)
  end

  @doc "Differences in the stores the harness can only report."
  @spec verified_diff(t(), t()) :: [leak()]
  def verified_diff(baseline, now) do
    map_diff(:registered, baseline.registered, now.registered) ++
      map_diff(:ets, baseline.ets, now.ets) ++
      tasks_diff(baseline.tasks, now.tasks) ++
      list_diff(:stub_orphans, now.stub_orphans) ++
      map_diff(:probe, baseline.probes, now.probes)
  end

  @doc "Puts the restorable stores back to `baseline`, touching only what differs."
  @spec restore(t(), t()) :: :ok
  def restore(baseline, now) do
    for {:persistent_term, key, to, _from} <- restorable_diff(baseline, now) do
      if to == :absent, do: :persistent_term.erase(key), else: :persistent_term.put(key, to)
    end

    for {:application_env, key, to, _from} <- restorable_diff(baseline, now) do
      if to == :absent,
        do: Application.delete_env(:media_centaur, key),
        else: Application.put_env(:media_centaur, key, to)
    end

    :ok
  end

  @doc """
  Removes what a verified leak left behind, so the next test's checkout
  finds the baseline: a leaked task is killed, a leaked table is deleted,
  and a leaked process is stopped the way it was started — through the
  app supervisor it was added to, or killed when nothing supervises it.
  Killing a supervised child would only have its supervisor restart it,
  and enough restarts stop the application. Probes are the exception:
  their state belongs to a supervised singleton, and a wrong value is a
  fact about that singleton that the failure reports and the next test's
  checkout sees again.
  """
  @spec contain([leak()]) :: :ok
  def contain(leaks) do
    Enum.each(leaks, &contain_one/1)
  end

  defp contain_one({:registered, name, _from, _to}) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> stop_process(pid, app_supervisor_of(pid))
    end
  end

  defp contain_one({:tasks, pids, _from, _to}), do: Enum.each(pids, &Process.exit(&1, :kill))

  defp contain_one({:stub_orphans, _messages, _from, _to}),
    do: MediaCentaur.GlobalStateSandbox.StubOrphans.clear()

  # A table that appeared is deleted; a baseline table whose size changed is
  # emptied (baseline app tables are empty at boot); a baseline table that
  # vanished cannot be brought back — the failure reports it and every later
  # checkout will see it until the process that owns it is restarted.
  defp contain_one({:ets, _table, _from, :absent}), do: :ok
  defp contain_one({:ets, table, :absent, _to}), do: drop_or_kill_owner(table, &:ets.delete/1)
  defp contain_one({:ets, table, _from, _to}), do: drop_or_kill_owner(table, &:ets.delete_all_objects/1)
  defp contain_one({:probe, _id, _from, _to}), do: :ok

  defp drop_or_kill_owner(table, public_action) do
    case :ets.info(table, :owner) do
      :undefined ->
        :ok

      owner when is_pid(owner) ->
        if :ets.info(table, :protection) == :public,
          do: public_action.(table),
          else: Process.exit(owner, :kill)
    end

    :ok
  end

  defp stop_process(pid, nil), do: Process.exit(pid, :kill)

  defp stop_process(pid, supervisor) do
    case Enum.find(Supervisor.which_children(supervisor), fn {_id, child, _type, _modules} ->
           child == pid
         end) do
      {id, _pid, _type, _modules} ->
        Supervisor.terminate_child(supervisor, id)
        Supervisor.delete_child(supervisor, id)
        :ok

      nil ->
        Process.exit(pid, :kill)
    end
  end

  # The immediate ancestor of an OTP process is the supervisor that
  # started it, by registered name when it has one.
  defp app_supervisor_of(pid) do
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary),
         [supervisor | _rest] <- Keyword.get(dictionary, :"$ancestors", []),
         true <- is_atom(supervisor) and namespaced?(supervisor),
         true <- Process.whereis(supervisor) != nil do
      supervisor
    else
      _other -> nil
    end
  end

  # --- the app's share of each store ---

  defp owned_terms do
    for {key, value} <- :persistent_term.get(), owned_key?(key), into: %{}, do: {key, value}
  end

  defp owned_key?({module, _sub_key}) when is_atom(module), do: namespaced?(module)
  defp owned_key?(module) when is_atom(module), do: namespaced?(module)
  defp owned_key?(_other), do: false

  defp registered_names do
    for name <- Process.registered(),
        namespaced?(name),
        pid = Process.whereis(name),
        into: %{},
        do: {name, pid}
  end

  defp owned_tables do
    for table <- :ets.all(), is_atom(table), app_process?(:ets.info(table, :owner)), into: %{} do
      {table, :ets.info(table, :size)}
    end
  end

  # A registered process is judged by its name; only an unregistered one
  # pays for the dictionary read that finds its initial call.
  defp app_process?(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) and name != nil -> namespaced?(name)
      {:registered_name, []} -> app_initial_call?(initial_call(pid))
      nil -> false
    end
  end

  defp app_process?(_other), do: false

  defp initial_call(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, :"$initial_call")
      nil -> nil
    end
  end

  defp app_initial_call?({module, _function, _arity}) when is_atom(module), do: namespaced?(module)
  defp app_initial_call?(_other), do: false

  defp namespaced?(atom) when is_atom(atom), do: String.starts_with?(Atom.to_string(atom), @namespace)

  # --- diffs ---

  defp map_diff(store, baseline, now) do
    added = for {key, value} <- now, not is_map_key(baseline, key), do: {store, key, :absent, value}
    removed = for {key, value} <- baseline, not is_map_key(now, key), do: {store, key, value, :absent}

    changed =
      for {key, value} <- now,
          is_map_key(baseline, key),
          Map.fetch!(baseline, key) != value,
          do: {store, key, Map.fetch!(baseline, key), value}

    added ++ removed ++ changed
  end

  defp list_diff(_store, []), do: []
  defp list_diff(store, items), do: [{store, items, [], items}]

  defp tasks_diff(_baseline, []), do: []
  defp tasks_diff(baseline, now), do: [{:tasks, now, baseline, now}]
end
