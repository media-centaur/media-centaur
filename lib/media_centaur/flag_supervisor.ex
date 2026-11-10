defmodule MediaCentaur.FlagSupervisor do
  use Boundary, deps: []

  @moduledoc """
  A supervisor whose children run while a flag is on and are absent from
  the tree while it is off.

  The flag is a fact Settings holds — a feature flag (`feature:<id>`,
  ADR-081) or a service start flag (`Settings.Services`). This module reads
  it and never stores it: whether the children run is read back from the
  tree (`running?/1`), so the flag and the tree can never disagree for
  longer than one reconcile. A setting decides whether a child is
  *started*; nothing here (or anywhere) stops a started child to express a
  setting, and `Supervisor.terminate_child/2` / `Supervisor.restart_child/2`
  are not used.

  Shape: this Supervisor runs a `DynamicSupervisor` and a controller under
  `:rest_for_one`. The controller reads the flag in `init/1`, starts the
  children as one `:one_for_one` group under the DynamicSupervisor when it
  is on, subscribes through `subscribe:` and reconciles on every message it
  then receives (a reconcile is one flag read and at most one start or stop,
  so no per-mechanism message filter). A group whose start fails — a child
  raising in `init/1` — is logged under `component:` and leaves the children
  not running; no supervisor retries a first start, and the house rule that
  `init/1` does no database write and no network is what keeps starts from
  failing.

  ## Options

    * `:flag` — zero-arity function returning the boolean. Required.
    * `:children` — the child specs that are the flag's children. Required.
    * `:subscribe` — zero-arity function the controller calls in `init/1`
      to subscribe to the flag's changes. Optional; without it only
      `reconcile/1` re-reads the flag.
    * `:relevant?` — one-arity predicate on a received message: true for a
      change of this flag. Default accepts every message; pass one whenever
      the subscription carries other changes too, since each cue costs a
      flag read.
    * `:label` — how log lines name the children, e.g. `"watchers"`.
      Required.
    * `:component` — the `MediaCentaur.Log` component (default `:system`).
    * `:name` — the supervisor's registered name. Optional; every function
      takes the pid or the name.

  ## API

  `running?/1` is the tree's answer. `reconcile/1` re-reads the flag now.
  `force/2` runs or stops the children regardless of the flag until the
  next reconcile — the test harness's override (`Features.Runtime.reset/1`
  puts every feature at the registry default without reading a flag the
  sandbox has rolled back). `suspend/2` stops the children, runs the
  function in the caller's process, and re-reads the flag afterwards even
  when the function raises; a flag message that arrives meanwhile is
  ignored, the flag is read once at resume.
  """

  use Supervisor

  alias MediaCentaur.FlagSupervisor.Controller

  @type server :: Supervisor.supervisor()

  @doc false
  # Returns once the flag has been read and, when it is on, the children
  # are up: a parent that lists a FlagSupervisor before a child that needs
  # the flag's children can rely on start order.
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    sup_opts = if name, do: [name: name], else: []

    with {:ok, pid} <- Supervisor.start_link(__MODULE__, opts, sup_opts) do
      :ok = reconcile(pid)
      {:ok, pid}
    end
  end

  @impl true
  def init(opts) do
    controller_opts =
      opts
      |> Keyword.take([:flag, :relevant?, :children, :subscribe, :label, :component])
      |> Keyword.put(:supervisor, self())

    children = [
      Supervisor.child_spec({DynamicSupervisor, strategy: :one_for_one}, id: :children_supervisor),
      Supervisor.child_spec({Controller, controller_opts}, id: :controller)
    ]

    # If the DynamicSupervisor goes (its group exhausted its restarts), the
    # controller restarts after it and reads the flag again.
    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Whether the flag's children are running: the tree's answer, not a stored one."
  @spec running?(server()) :: boolean()
  def running?(server), do: GenServer.call(controller(server), :running?)

  @doc "The pids of the flag's children, in child-spec order; `[]` while they are not running."
  @spec children(server()) :: [pid()]
  def children(server), do: GenServer.call(controller(server), :children)

  @doc "Reads the flag now and starts or stops the children to match."
  @spec reconcile(server()) :: :ok
  def reconcile(server), do: GenServer.call(controller(server), :reconcile)

  @doc "Runs or stops the children regardless of the flag, until the next reconcile."
  @spec force(server(), boolean()) :: :ok
  def force(server, wanted?) when is_boolean(wanted?),
    do: GenServer.call(controller(server), {:force, wanted?})

  @doc """
  Stops the children, runs `fun` in the calling process, then reads the
  flag again — also when `fun` raises. Returns what `fun` returns.
  """
  @spec suspend(server(), (-> result)) :: result when result: term()
  def suspend(server, fun) when is_function(fun, 0) do
    controller = controller(server)
    :ok = GenServer.call(controller, :suspend)

    try do
      fun.()
    after
      :ok = GenServer.call(controller, :resume)
    end
  end

  @doc false
  def children_supervisor(server), do: child(server, :children_supervisor)

  defp controller(server), do: child(server, :controller)

  defp child(server, id) do
    {^id, pid, _type, _modules} =
      server
      |> Supervisor.which_children()
      |> Enum.find(fn {child_id, _pid, _type, _modules} -> child_id == id end)

    pid
  end
end
