defmodule MediaCentaur.Watcher.SupervisorTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Watcher.Supervisor, as: WatcherSupervisor

  setup do
    # Start a sandbox owner in shared mode so watcher Tasks can access the DB.
    # Using start_owner! (not checkout) creates a separate process that stays
    # alive through on_exit, unlike the test process which dies before on_exit.
    sandbox_owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    tmp_dir = Path.join(System.tmp_dir!(), "watcher_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    # Override config to point watch_dirs to our temp dir
    original_config = :persistent_term.get({MediaCentaur.Config, :config})
    updated_config = Map.put(original_config, :watch_dirs, [tmp_dir])
    :persistent_term.put({MediaCentaur.Config, :config}, updated_config)

    # Stop any existing watchers, then start fresh with our temp dir
    WatcherSupervisor.stop_watchers()
    WatcherSupervisor.start_watchers()
    wait_for_watchers()

    on_exit(fn ->
      WatcherSupervisor.stop_watchers()
      drain_task_supervisor()
      Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_owner)
      :persistent_term.put({MediaCentaur.Config, :config}, original_config)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "pause_during/1" do
    test "stops watchers, runs the function, then restarts them" do
      assert [%{dir: _, state: _}] = WatcherSupervisor.statuses()

      result =
        WatcherSupervisor.pause_during(fn ->
          assert [] = WatcherSupervisor.statuses()
          :callback_result
        end)

      assert result == :callback_result

      wait_for_watchers()
      assert [%{dir: _, state: _}] = WatcherSupervisor.statuses()
    end

    test "restarts watchers even if the function raises" do
      assert_raise RuntimeError, "boom", fn ->
        WatcherSupervisor.pause_during(fn ->
          raise "boom"
        end)
      end

      wait_for_watchers()
      assert [%{dir: _, state: _}] = WatcherSupervisor.statuses()
    end
  end

  defp wait_for_watchers(attempts \\ 20) do
    if WatcherSupervisor.statuses() == [] and attempts > 0 do
      Process.sleep(50)
      wait_for_watchers(attempts - 1)
    end
  end

  # Wait for all tasks spawned by watchers to finish before revoking the sandbox.
  defp drain_task_supervisor(attempts \\ 20) do
    if Task.Supervisor.children(MediaCentaur.TaskSupervisor) != [] and attempts > 0 do
      Process.sleep(50)
      drain_task_supervisor(attempts - 1)
    end
  end
end
