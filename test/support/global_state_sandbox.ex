defmodule MediaCentaur.GlobalStateSandbox do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Resets the global state the Ecto sandbox has no opinion about, before
  every `DataCase` / `ConnCase` test.

  `Ecto.Adapters.SQL.Sandbox` is airtight for rows and knows nothing about
  `:persistent_term` or long-lived processes. Every context-owned cache of
  the `:persistent_term` flavour (see `MediaCentaur.Cache`) therefore
  survives the test that wrote it, and a later test reads a value produced
  by a transaction that no longer exists.

  ## The worked example

  `Downloads.QueueMonitor` caches its merged `%QueueState{}` in
  `:persistent_term` on every poll. The monitor itself is not started under
  `:test` (`Application.pubsub_listeners/1`), so it looked contained — but
  `queue_monitor_test.exs` starts its own against stubbed clients, and the
  three items that poll produces stay in the term store for the rest of the
  run. `IncomingLive` reads that cache at mount and matches it against the
  (correctly empty) pursuit rows, so all three become orphans and the
  Activity tab stops rendering its "Nothing in flight" empty state. The
  test that fails is in a file that touches none of this:

      mix test test/media_centaur/downloads/queue_monitor_test.exs \\
               test/media_centaur_web/live/incoming_live_test.exs:1701 --seed 0

  ## The baseline is derived, not listed

  `capture_pristine!/0` snapshots every `:persistent_term` key this
  application owns — anything namespaced under `MediaCentaur*` — after
  `test_helper.exs` has finished priming. `restore!/0` puts that snapshot
  back before each test: values that changed are rewritten, keys added
  since are erased, and terms owned by dependencies are left alone. A cache
  added tomorrow is covered without editing this module, which is the
  point — the previous mechanism restored one hand-named key
  (`{MediaCentaur.Settings.Config, :config}`) and could only ever cover the leak
  someone had already been bitten by.

  ## Processes are classified, not guessed

  Stores can be swept by namespace; processes cannot. `dispositions/0`
  names every child of `MediaCentaur.Supervisor` and what contains its
  state, and `global_state_sandbox_test.exs` fails when the supervision
  tree grows a child that isn't there. A new stateful singleton is caught
  rather than remembered.

  ## Only a test that owns the machine may reset it

  `restore!/1` is a **no-op for `async: true` tests**, and that is not a
  gap — it is the only correct behaviour. Async tests run concurrently, so
  clearing shared state in one test's setup clears it underneath its peers.
  This was measured the expensive way: an unconditional reset erased the
  stubbed TMDB client that `fetch_metadata_test.exs` (`async: true`) had
  installed for itself, and the stage fell through to the real API and came
  back with a 401.

  The same condition already governs the SQL sandbox one line below
  (`shared: not tags[:async]`), for the same reason. Async tests share the
  machine and so must not touch anything shared — which is exactly why the
  writers this module exists to contain are all `async: false`. ExUnit runs
  every async module before the first sync one, so a sync test's reset can
  never race an async test.
  """

  alias MediaCentaur.Console.Buffer
  alias MediaCentaurWeb.IncomingLive.SearchSession

  @snapshot_key {__MODULE__, :pristine}

  @resets [
    {Buffer, :clear},
    {SearchSession, :clear}
  ]

  # Every child of MediaCentaur.Supervisor, and what contains its state
  # between tests:
  #
  #   :sandboxed — rolled back by a mechanism that already exists
  #   :stateless — holds nothing a later test can read
  #   :reset     — cleared here, every test, through its public API
  #   :accepted  — carries state across tests and is deliberately not
  #                reset; the reason says why that is safe today
  @dispositions %{
    MediaCentaur.Repo => {:sandboxed, "Ecto SQL sandbox, per-test owner"},
    MediaCentaur.Library.Availability =>
      {:sandboxed, "state lives in :persistent_term — restored by restore!/0"},
    MediaCentaur.TaskSupervisor => {:sandboxed, "orphans drained in DataCase teardown"},
    MediaCentaur.Console.Buffer => {:reset, "ring buffer; unscoped log assertions false-match"},
    MediaCentaurWeb.IncomingLive.SearchSession =>
      {:reset, "singleton search session, rendered by /incoming on mount"},
    MediaCentaurWeb.Endpoint => {:stateless, "config only"},
    MediaCentaurWeb.Telemetry => {:stateless, "poller"},
    Phoenix.PubSub.Supervisor => {:stateless, "message transport"},
    Oban => {:stateless, "testing: :inline — no queues run"},
    MediaCentaur.Playback.Supervisor =>
      {:stateless, "supervisor; sessions are temporary and registry-deregistered"},
    MediaCentaur.Pipeline.Supervisor => {:stateless, "Broadway topology; state is per-message"},
    MediaCentaur.Pipeline.Image.Supervisor => {:stateless, "Broadway topology; state is per-message"},
    MediaCentaur.Watcher.Supervisor => {:stateless, "watchers are not started under :test"},
    MediaCentaur.Social.Connections =>
      {:stateless, "the relay-connection owner is not started under :test"},
    MediaCentaur.Recommendations.Sync =>
      {:stateless, "not started under :test; sync_test starts its own"},
    MediaCentaur.Console.JournalSource => {:stateless, "reads journald; no test asserts on it"},
    MediaCentaur.Library.BroadcastCoalescer =>
      {:accepted, "pending entity ids for one ~100ms flush window, then empty"},
    MediaCentaur.Library.FileEventHandler => {:accepted, "debounce timers only, no read API"},
    MediaCentaur.Library.AbsenceSweeper => {:accepted, "sweep schedule only, no read API"},
    MediaCentaur.HttpClient.Supervisor =>
      {:stateless, "response cache and HTTP stats are not started under :test"},
    MediaCentaur.TMDB.RateLimiter =>
      {:accepted, "sliding window; a leaked window delays a call, it cannot change an assertion"},
    MediaCentaur.TMDB.MetadataStats =>
      {:accepted,
       "enrichment stats accumulate from telemetry; no reset API, and status_live_test " <>
         "deliberately asserts on its own rows rather than this singleton"},
    MediaCentaur.ErrorReports.Buckets =>
      {:accepted, "the durable log handler is off under :test; bucket tests drive named instances"},
    MediaCentaur.SelfUpdate.Updater =>
      {:accepted, "download/apply state; tests drive UpdateChecker and the release stubs instead"},
    MediaCentaur.SelfUpdate.AutoApply => {:accepted, "check schedule only, no read API"},
    :init_services => {:stateless, "one-shot temporary task; gone before the first test"}
  }

  @doc """
  Captures the pristine `:persistent_term` baseline. Called once from
  `test_helper.exs`, after every priming write it makes.
  """
  @spec capture_pristine!() :: :ok
  def capture_pristine! do
    :persistent_term.put(@snapshot_key, owned_terms())
  end

  @doc """
  Restores the captured baseline and clears the shared singletons a test
  can perturb, for a test that owns the machine.

  Called from `MediaCentaur.DataCase.setup_sandbox/1` with the test's tags,
  before the test's own `setup` blocks run. `async: true` tests are skipped
  — see the moduledoc; resetting shared state from one of several
  concurrently running tests corrupts the others.
  """
  @spec restore!(map()) :: :ok
  def restore!(tags \\ %{})
  def restore!(%{async: true}), do: :ok

  def restore!(_tags) do
    pristine = :persistent_term.get(@snapshot_key)
    current = owned_terms()

    for {key, _value} <- current, not is_map_key(pristine, key), do: :persistent_term.erase(key)
    for {key, value} <- pristine, Map.get(current, key) != value, do: :persistent_term.put(key, value)

    Enum.each(@resets, fn {module, fun} -> apply(module, fun, []) end)
  end

  @doc "The supervision-tree inventory. See the moduledoc for the vocabulary."
  @spec dispositions() :: %{atom() => {atom(), String.t()}}
  def dispositions, do: @dispositions

  @doc "The singletons `restore!/0` clears, as `{module, function}` pairs."
  @spec resets() :: [{module(), atom()}]
  def resets, do: @resets

  defp owned_terms do
    for {key, value} <- :persistent_term.get(), ours?(key), into: %{}, do: {key, value}
  end

  # The snapshot itself is not part of the baseline it describes.
  defp ours?(@snapshot_key), do: false
  defp ours?({module, _sub_key}) when is_atom(module), do: app_module?(module)
  defp ours?(module) when is_atom(module), do: app_module?(module)
  defp ours?(_other), do: false

  defp app_module?(module) do
    case Atom.to_string(module) do
      "Elixir.MediaCentaur" <> _rest -> true
      _other -> false
    end
  end
end
