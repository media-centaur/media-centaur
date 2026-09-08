defmodule MediaCentaur.GlobalStateSandbox do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  A sync test checks the machine out and checks it back in.

  `Ecto.Adapters.SQL.Sandbox` is airtight for rows and knows nothing about
  the rest of the machine: `:persistent_term`, the application env, named
  ETS tables, registered processes, supervised tasks, and the state of the
  singletons under `MediaCentaur.Supervisor`. Every one of those survives
  the test that wrote it. This module owns that remainder, on one rule:

  > Everything global is either **returned by the harness** or **proven
  > untouched** at check-in. There is no third category.

  ## The edges

  `MediaCentaur.Case` calls `checkout/1` in `setup` for every test.

  * An `async: true` test is not checked out. Concurrent tests share the
    machine, so nothing may be reset for one of them, and nothing may be
    written by one of them — that half is a Credo check.
  * An `async: false` test is checked out: its entry is verified against
    the **baseline** (the snapshot `capture_baseline!/0` took at the end of
    `test_helper.exs`), and `checkin/0` is registered to run in `on_exit`.

  `checkin/0` restores the restorable stores and runs every `{:reset, mfa}`
  disposition, then verifies the rest. A difference it cannot put back is
  contained — the process killed, the table deleted — and raised as
  `MediaCentaur.GlobalStateSandbox.Leak`, so the failure lands on the test
  that made the leak rather than the test that would have read it. A live
  child of `MediaCentaur.TaskSupervisor` at check-in is such a leak: a test
  drives its async work to completion (ADR-049,
  `MediaCentaur.TaskAwaits`), and a grace window would only turn the leak
  into a load-dependent flake.

  Async modules run before any sync module, so a sync test that finds the
  machine off the baseline at checkout has found the async phase's leak. It
  fails — with a message naming the phase — after restoring, so nothing
  cascades.

  ## Dispositions are executable

  `dispositions/0` names every child of `MediaCentaur.Supervisor` and what
  contains its state between tests:

  * `{:sandboxed, why}` — returned by a mechanism that already exists (the
    SQL sandbox; the `:persistent_term` restore; the task store).
  * `{:unobservable, why}` — has no public read, so no test can depend on
    it. The reason names the absence.
  * `{:reset, mfa, why}` — has a public read; `mfa` returns it to the
    baseline at every check-in.
  * `{:probe, mfa, why}` — has a public read and cannot be reset; `mfa` is
    read at check-in and must equal what it read at baseline.

  The inventory test fails when the tree grows a child that is not here,
  and when a reset or probe names a function that does not exist. There is
  no disposition whose truth rests on a sentence.

  ## What is derived and what is listed

  The app's share of each store is derived by namespace — see
  `MediaCentaur.GlobalStateSandbox.Snapshot`. Only the dispositions are a
  list, because a singleton's observable state has no namespace.
  """

  alias MediaCentaur.GlobalStateSandbox.Leak
  alias MediaCentaur.GlobalStateSandbox.Snapshot

  @settle_ms 500
  @settle_interval_ms 10

  # Harness bookkeeping — the baseline and whether the last check-in
  # verified clean — lives in a table owned by the process that runs
  # `test_helper.exs`, which outlives every test. It is not an app process,
  # so the snapshot's ETS scan ignores the table.
  @table :media_centaur_global_state_sandbox

  @dispositions %{
    MediaCentaur.Repo => {:sandboxed, "Ecto SQL sandbox, per-test owner"},
    MediaCentaur.Library.Availability =>
      {:sandboxed, "the per-dir map lives only in :persistent_term, which check-in restores"},
    MediaCentaur.TaskSupervisor => {:sandboxed, "live children are a verified store — see checkin/0"},
    MediaCentaur.Console.Buffer =>
      {:reset, {MediaCentaur.Console.Buffer, :clear, []},
       "ring buffer; unscoped log assertions false-match"},
    MediaCentaurWeb.IncomingLive.SearchSession =>
      {:reset, {MediaCentaurWeb.IncomingLive.SearchSession, :clear, []},
       "singleton search session, rendered by /incoming on mount"},
    MediaCentaur.ErrorReports.Buckets =>
      {:reset, {MediaCentaur.ErrorReports.Buckets, :clear, []},
       "Status-board tests ingest into this named process; the board reads only it"},
    MediaCentaur.TMDB.RateLimiter =>
      {:reset, {MediaCentaur.TMDB.RateLimiter, :reset, []},
       "a sliding window every TMDB call fills; status/0 reads it and a full window delays the next test"},
    MediaCentaur.TMDB.MetadataStats =>
      {:reset, {MediaCentaur.TMDB.MetadataStats, :reset, []},
       "the Status page reads the singleton's snapshot; enrichment telemetry from any test fills it"},
    MediaCentaur.Watcher.Supervisor =>
      {:reset, {MediaCentaur.Watcher.Supervisor, :stop_watchers, []},
       "a test that calls start_watchers/0 leaves watcher children running; the flag is a :persistent_term"},
    MediaCentaur.SelfUpdate.Updater =>
      {:probe, {MediaCentaur.SelfUpdate.Updater, :status, []},
       "download/apply state the Settings page reads; tests drive named instances, so the singleton stays at rest"},
    MediaCentaurWeb.Endpoint => {:unobservable, "config only"},
    MediaCentaurWeb.Telemetry => {:unobservable, "poller"},
    Phoenix.PubSub.Supervisor => {:unobservable, "message transport"},
    Oban => {:unobservable, "testing: :inline — no queues run"},
    MediaCentaur.Playback.Supervisor =>
      {:unobservable, "supervisor; sessions are temporary and registry-deregistered"},
    MediaCentaur.Pipeline.Supervisor =>
      {:reset, {MediaCentaur.Pipeline.Discovery.InflightSet, :clear, []},
       "Broadway state is per-message, but the discovery in-flight set is a public ETS table with a read API"},
    MediaCentaur.Pipeline.Image.Supervisor => {:unobservable, "Broadway topology; state is per-message"},
    MediaCentaur.Social.Connections =>
      {:unobservable, "the relay-connection owner is not started under :test"},
    MediaCentaur.Activities.Sync => {:unobservable, "not started under :test; sync_test starts its own"},
    MediaCentaur.Console.JournalSource => {:unobservable, "reads journald; no public read"},
    MediaCentaur.Library.BroadcastCoalescer => {:unobservable, "enqueue/1 is its only public function"},
    MediaCentaur.Library.FileEventHandler => {:unobservable, "debounce timers only; no public read"},
    MediaCentaur.Library.AbsenceSweeper =>
      {:unobservable, "a sweep schedule; its reads go to the DB and :persistent_term"},
    MediaCentaur.HttpClient.Supervisor =>
      {:unobservable, "response cache and HTTP stats are not started under :test"},
    MediaCentaur.SelfUpdate.AutoApply =>
      {:unobservable, "a check schedule; its public functions are pure"},
    :init_services => {:unobservable, "one-shot temporary task; gone before the first test"}
  }

  @doc """
  Captures the baseline. Called once from `test_helper.exs`, after every
  priming write it makes — the baseline is whatever state priming leaves.
  """
  @spec capture_baseline!() :: :ok
  def capture_baseline! do
    :ets.new(@table, [:named_table, :public, :set])
    :ets.insert(@table, [{:baseline, snapshot()}, {:verified_clean, false}])
    :ok
  end

  @doc "The baseline every sync test starts from and returns to."
  @spec baseline() :: Snapshot.t()
  def baseline, do: :ets.lookup_element(@table, :baseline, 2)

  @doc "The machine's global state now, as `MediaCentaur.GlobalStateSandbox.Snapshot` sees it."
  @spec snapshot() :: Snapshot.t()
  def snapshot, do: Snapshot.take(probes())

  @doc """
  Checks the machine out for a test, given its tags. A no-op for
  `async: true`. For a sync test: registers `checkin/0` in `on_exit` and,
  unless the previous check-in verified the machine clean, verifies the
  baseline — raising `Leak` (after restoring) if the machine was already
  off it. That verification fires on the first sync test, where the async
  phase's leak shows, and after a check-in that could not contain a leak.
  """
  @spec checkout(map()) :: :ok
  def checkout(%{async: true}), do: :ok

  def checkout(_tags) do
    ExUnit.Callbacks.on_exit(&checkin/0)

    if verified_clean?() do
      :ok
    else
      baseline = baseline()
      now = snapshot()
      restorable = Snapshot.restorable_diff(baseline, now)
      verified = Snapshot.verified_diff(baseline, now)

      if restorable == [] and verified == [] do
        :ok
      else
        Snapshot.restore(baseline, now)
        Snapshot.contain(verified)
        raise Leak, phase: :checkout, leaks: restorable ++ verified
      end
    end
  end

  @doc """
  Checks the machine back in: runs every reset, restores the restorable
  stores (after the resets, so a reset that writes a flag is itself
  restored), then verifies the rest. Waits up to #{@settle_ms}ms for
  verified state to settle — exit signals propagate asynchronously — and
  returns the instant it is clean. Runs in `on_exit`, so it must not
  touch the DB.
  """
  @spec checkin() :: :ok
  def checkin do
    baseline = baseline()
    Enum.each(resets(), fn {module, function, args} -> apply(module, function, args) end)
    now = snapshot()
    Snapshot.restore(baseline, now)
    deadline = System.monotonic_time(:millisecond) + @settle_ms

    case settle(baseline, Snapshot.verified_diff(baseline, now), deadline) do
      [] ->
        :ets.insert(@table, {:verified_clean, true})
        :ok

      leaks ->
        :ets.insert(@table, {:verified_clean, false})
        Snapshot.contain(leaks)
        raise Leak, phase: :checkin, leaks: leaks
    end
  end

  @doc "The supervision-tree inventory. See the moduledoc for the vocabulary."
  @spec dispositions() :: %{atom() => tuple()}
  def dispositions, do: @dispositions

  defp resets, do: for({_id, {:reset, mfa, _why}} <- @dispositions, do: mfa)
  defp probes, do: for({id, {:probe, mfa, _why}} <- @dispositions, into: %{}, do: {id, mfa})

  defp verified_clean?, do: :ets.lookup_element(@table, :verified_clean, 2)

  # Waits for verified state to settle, starting from a diff already taken;
  # a clean first diff costs no second snapshot.
  defp settle(_baseline, [], _deadline), do: []

  defp settle(baseline, leaks, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      leaks
    else
      Process.sleep(@settle_interval_ms)
      settle(baseline, Snapshot.verified_diff(baseline, snapshot()), deadline)
    end
  end
end
