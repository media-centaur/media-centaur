defmodule MediaCentaur.GlobalStateSandboxTest do
  # Writes process-global state on purpose — owns the machine.
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Console.Buffer
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Buckets
  alias MediaCentaur.GlobalStateSandbox
  alias MediaCentaur.GlobalStateSandbox.Leak
  alias MediaCentaur.GlobalStateSandbox.Snapshot
  alias MediaCentaurWeb.IncomingLive.SearchSession

  @config_key {MediaCentaur.Settings.Config, :config}

  describe "checkin/0 — restorable state is put back" do
    test "an app-owned :persistent_term a test changed" do
      pristine = :persistent_term.get(@config_key)
      :persistent_term.put(@config_key, Map.put(pristine, :port, 65_432))

      GlobalStateSandbox.checkin()

      assert :persistent_term.get(@config_key) == pristine
    end

    test "an app-owned :persistent_term that did not exist at capture is erased" do
      # Deliberately a module that does not exist: the baseline is derived
      # from the namespace, not from a list of known caches.
      key = {MediaCentaur.SomeCacheAddedTomorrow, :state}
      :persistent_term.put(key, :leaked)

      GlobalStateSandbox.checkin()

      assert :persistent_term.get(key, :__unset) == :__unset
    end

    test "a :persistent_term this application does not own is left alone" do
      key = {:some_dependency, :config}
      :persistent_term.put(key, :not_ours)
      on_exit(fn -> :persistent_term.erase(key) end)

      GlobalStateSandbox.checkin()

      assert :persistent_term.get(key) == :not_ours
    end

    test "an application-env key a test changed, and one it added" do
      original = Application.get_env(:media_centaur, :environment)
      Application.put_env(:media_centaur, :environment, :prod)
      Application.put_env(:media_centaur, :key_added_by_a_test, :leaked)

      GlobalStateSandbox.checkin()

      assert Application.get_env(:media_centaur, :environment) == original
      assert Application.get_env(:media_centaur, :key_added_by_a_test, :__unset) == :__unset
    end

    test "the Console ring buffer is emptied" do
      Buffer.append(entry(:info, "a line from an earlier test"))
      Buffer.flush()
      assert Buffer.recent(nil) != []

      GlobalStateSandbox.checkin()

      assert Buffer.recent(nil) == []
    end

    test "the incident bucket cache is emptied" do
      # The Status board reads the globally named cache, so a LiveView test
      # that wants an incident on the board has to ingest into this instance.
      Buckets.ingest(entry(:error, "an incident from an earlier test"))
      assert Buckets.list_buckets() != []

      GlobalStateSandbox.checkin()

      assert Buckets.list_buckets() == []
    end

    test "the acquisition search session is reset" do
      SearchSession.set_query_preview("a query from an earlier test")
      assert SearchSession.current().query != ""

      GlobalStateSandbox.checkin()

      assert SearchSession.current().query == ""
    end
  end

  describe "checkin/0 — verified state fails the test that left it" do
    test "a registered app process the test started and did not stop" do
      name = MediaCentaur.LeakedByATest
      {:ok, pid} = Agent.start(fn -> :leaked end, name: name)
      Process.unlink(pid)

      error = assert_raise(Leak, &GlobalStateSandbox.checkin/0)

      assert Exception.message(error) =~ inspect(name)
      # Contained, so the next test starts clean rather than failing too.
      refute Process.alive?(pid)
    end

    test "a child a test added to the app supervisor is stopped through the supervisor, not killed" do
      # Killing a supervised child only has the supervisor restart it, and
      # enough restarts stop the application under every later test.
      {:ok, pid} = Supervisor.start_child(MediaCentaur.Supervisor, MediaCentaur.Review.Intake)

      error = assert_raise(Leak, &GlobalStateSandbox.checkin/0)

      assert Exception.message(error) =~ "MediaCentaur.Review.Intake"
      refute Process.alive?(pid)

      refute Enum.any?(
               Supervisor.which_children(MediaCentaur.Supervisor),
               &match?({MediaCentaur.Review.Intake, _, _, _}, &1)
             )

      assert Process.alive?(Process.whereis(MediaCentaur.Supervisor))
    end

    test "a named ETS table owned by an app process that outlives the test" do
      {:ok, owner} =
        Agent.start(fn -> :ets.new(:media_centaur_leaked_table, [:named_table, :public]) end)

      Process.unlink(owner)
      assert :ets.whereis(:media_centaur_leaked_table) != :undefined

      # The owner is an app process by its initial call, not its name.
      error = assert_raise(Leak, &GlobalStateSandbox.checkin/0)

      assert Exception.message(error) =~ ":media_centaur_leaked_table"
      assert :ets.whereis(:media_centaur_leaked_table) == :undefined
    end

    test "a named ETS table the test process itself created is not a leak" do
      # It dies with the test process, before check-in ever runs; creating
      # it here and checking in from the same process is the closest a test
      # can get, and the table's owner is not an app process.
      :ets.new(:some_dependency_table, [:named_table, :public])

      assert GlobalStateSandbox.checkin() == :ok
    end

    test "a supervised task still running at check-in" do
      {:ok, pid} =
        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          Process.sleep(:infinity)
        end)

      error = assert_raise(Leak, &GlobalStateSandbox.checkin/0)

      assert Exception.message(error) =~ "MediaCentaur.TaskSupervisor"
      refute Process.alive?(pid)
    end

    test "a request no stub could answer, logged from a process that then died" do
      # A task that outlives its owner's stubs dies of the stub loss, usually
      # before check-in can see it as a live child; a request for a stub that
      # was never installed dies the same way. The crash report is recorded
      # where it is logged.
      {:ok, pid} =
        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          Req.get!(Req.new(plug: {Req.Test, :tmdb}, url: "http://stub.test/"))
        end)

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

      error = assert_raise(Leak, &GlobalStateSandbox.checkin/0)

      assert Exception.message(error) =~ "no mock or stub for :tmdb"
      # Contained: the record is cleared, so the next check-in is clean.
      assert GlobalStateSandbox.checkin() == :ok
    end

    test "a process that is still shutting down is waited for, not reported" do
      # Exit signals propagate asynchronously; check-in gives verified state a
      # moment to settle and returns the instant it is clean.
      name = MediaCentaur.ShuttingDownAfterATest
      {:ok, pid} = Agent.start(fn -> :ok end, name: name)
      Process.unlink(pid)
      spawn(fn -> Process.sleep(50) && Agent.stop(pid) end)

      assert GlobalStateSandbox.checkin() == :ok
    end
  end

  describe "checkout/1" do
    test "a checkout after a clean check-in takes the machine on trust" do
      key = {MediaCentaur.SomeCacheAddedTomorrow, :state}
      :persistent_term.put(key, :written_between_tests_by_nothing)
      :ets.insert(:media_centaur_global_state_sandbox, {:verified_clean, true})

      assert GlobalStateSandbox.checkout(%{async: false}) == :ok
    end

    test "an async test neither restores nor verifies anything" do
      # Async tests run concurrently, so a reset in one of them clears state
      # its peers installed for themselves.
      key = {MediaCentaur.SomeCacheAddedTomorrow, :state}
      :persistent_term.put(key, :installed_by_a_peer)
      on_exit(fn -> :persistent_term.erase(key) end)

      assert GlobalStateSandbox.checkout(%{async: true}) == :ok

      assert :persistent_term.get(key, :__unset) == :installed_by_a_peer
    end

    test "a sync test that begins off the baseline fails, naming the async phase, and is restored" do
      key = {MediaCentaur.SomeCacheAddedTomorrow, :state}
      :persistent_term.put(key, :left_by_the_async_phase)
      # Checkout trusts a check-in that verified clean; before the first
      # sync test there has been none.
      :ets.insert(:media_centaur_global_state_sandbox, {:verified_clean, false})

      error = assert_raise(Leak, fn -> GlobalStateSandbox.checkout(%{async: false}) end)

      assert Exception.message(error) =~ "async phase"
      assert Exception.message(error) =~ inspect(key)
      assert :persistent_term.get(key, :__unset) == :__unset
    end
  end

  describe "the supervision tree's inventory" do
    test "every long-lived child is classified" do
      unclassified =
        MediaCentaur.Supervisor
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)
        |> Enum.reject(&Map.has_key?(GlobalStateSandbox.dispositions(), &1))

      assert unclassified == [],
             """
             These supervision-tree children carry state across the whole
             test run and nothing says what happens to it between tests:

                 #{inspect(unclassified)}

             Add each to `MediaCentaur.GlobalStateSandbox.dispositions/0`:
             :sandboxed, :unobservable, {:reset, mfa} or {:probe, mfa}.
             """
    end

    test "every reset and probe names a function that exists" do
      for {id, disposition} <- GlobalStateSandbox.dispositions(),
          {kind, {module, function, args}, _why} <- [disposition],
          kind in [:reset, :probe] do
        assert function_exported?(module, function, length(args)),
               "#{inspect(id)} is #{kind} through #{inspect(module)}.#{function}/#{length(args)}, which does not exist"
      end
    end

    test "every probe reads its baseline value on a clean machine" do
      # A probe that drifts on its own would fail every sync test; this is
      # the claim behind each `{:probe, mfa}` line, checked at rest.
      assert Snapshot.verified_diff(GlobalStateSandbox.baseline(), GlobalStateSandbox.snapshot()) == []
    end
  end

  defp entry(level, message) do
    Entry.new(
      id: 1,
      timestamp: DateTime.utc_now(),
      level: level,
      component: :tmdb,
      message: message
    )
  end
end
