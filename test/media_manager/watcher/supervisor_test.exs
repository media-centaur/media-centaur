defmodule MediaManager.Watcher.SupervisorTest do
  use ExUnit.Case, async: false

  alias MediaManager.Watcher.Supervisor, as: WatcherSupervisor

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "watcher_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    # Override config to point watch_dirs to our temp dir
    original_config = :persistent_term.get({MediaManager.Config, :config})
    updated_config = Map.put(original_config, :watch_dirs, [tmp_dir])
    :persistent_term.put({MediaManager.Config, :config}, updated_config)

    # Start the supervisor (disabled in test config) — ExUnit handles cleanup
    start_supervised!(WatcherSupervisor)
    WatcherSupervisor.start_watchers()
    wait_for_watchers()

    on_exit(fn ->
      :persistent_term.put({MediaManager.Config, :config}, original_config)
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
end
