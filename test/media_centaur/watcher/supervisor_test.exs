defmodule MediaCentaur.Watcher.SupervisorTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.ServiceFlags
  alias MediaCentaur.Watcher
  alias MediaCentaur.Watcher.Supervisor, as: WatcherSupervisor

  import MediaCentaur.Eventually
  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  setup do
    # Start a sandbox owner in shared mode so watcher Tasks can access the DB.
    # Using start_owner! (not checkout) creates a separate process that stays
    # alive through on_exit, unlike the test process which dies before on_exit.
    sandbox_owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    tmp_dir = Path.join(System.tmp_dir!(), "watcher_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    # Watching follows its flag; the config override points media_dirs at
    # the temp dir before the flag's children read it.
    ServiceFlags.enable_background_services()
    original_config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    updated_config = Map.put(original_config, :media_dirs, [tmp_dir])
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, updated_config)

    ServiceFlags.turn_on(:start_watchers, Watcher.FlagSupervisor)
    eventually(fn -> WatcherSupervisor.statuses() != [] end)

    on_exit(fn ->
      await_supervised_tasks()
      Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_owner)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "suspend/1" do
    test "stops watchers, runs the function, then restarts them" do
      assert [%{dir: _, state: _}] = WatcherSupervisor.statuses()

      result =
        WatcherSupervisor.suspend(fn ->
          assert [] = WatcherSupervisor.statuses()
          :callback_result
        end)

      assert result == :callback_result

      eventually(fn -> WatcherSupervisor.statuses() != [] end)
      assert [%{dir: _, state: _}] = WatcherSupervisor.statuses()
    end

    test "restarts watchers even if the function raises" do
      assert_raise RuntimeError, "boom", fn ->
        WatcherSupervisor.suspend(fn ->
          raise "boom"
        end)
      end

      eventually(fn -> WatcherSupervisor.statuses() != [] end)
      assert [%{dir: _, state: _}] = WatcherSupervisor.statuses()
    end
  end
end
