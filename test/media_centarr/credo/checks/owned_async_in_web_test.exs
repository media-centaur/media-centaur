defmodule MediaCentarr.Credo.Checks.OwnedAsyncInWebTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.OwnedAsyncInWeb

  describe "clean code (negative cases)" do
    test "start_async in a web LiveView is allowed (owned async)" do
      ~S'''
      defmodule MediaCentarrWeb.NewLive do
        def ensure_loaded(socket) do
          start_async(socket, :load, fn -> expensive_load() end)
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/new_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> refute_issues()
    end

    test "fire-and-forget start_child in the context layer is allowed (not web)" do
      ~S'''
      defmodule MediaCentarr.Watcher do
        def scan do
          Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn -> work() end)
        end
      end
      '''
      |> to_source_file("lib/media_centarr/watcher.ex")
      |> run_check(OwnedAsyncInWeb)
      |> refute_issues()
    end

    test "grandfathered web file is not flagged (rollout backlog)" do
      ~S'''
      defmodule MediaCentarrWeb.SettingsLive do
        def handle_event(_, _, socket) do
          Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn -> work() end)
          {:noreply, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/settings_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "fire-and-forget start_child in a new web LiveView is reported" do
      ~S'''
      defmodule MediaCentarrWeb.NewLive do
        def handle_event(_, _, socket) do
          Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
            result = expensive_load()
            send(self(), {:loaded, result})
          end)

          {:noreply, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/new_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end

    test "fire-and-forget start_child in a web component is reported" do
      ~S'''
      defmodule MediaCentarrWeb.Components.Thing do
        def load do
          Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn -> work() end)
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/thing.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end
  end
end
