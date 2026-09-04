defmodule MediaCentaur.Credo.Checks.OwnedAsyncInWebTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.OwnedAsyncInWeb

  describe "clean code (negative cases)" do
    test "start_async in a web LiveView is allowed (owned async)" do
      ~S'''
      defmodule MediaCentaurWeb.NewLive do
        def ensure_loaded(socket) do
          start_async(socket, :load, fn -> expensive_load() end)
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/new_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> refute_issues()
    end

    test "fire-and-forget start_child in the context layer is allowed (not web)" do
      ~S'''
      defmodule MediaCentaur.Watcher do
        def scan do
          Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> work() end)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/watcher.ex")
      |> run_check(OwnedAsyncInWeb)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "fire-and-forget start_child in a new web LiveView is reported" do
      ~S'''
      defmodule MediaCentaurWeb.NewLive do
        def handle_event(_, _, socket) do
          Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
            result = expensive_load()
            send(self(), {:loaded, result})
          end)

          {:noreply, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/new_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end

    test "fire-and-forget start_child in a web component is reported" do
      ~S'''
      defmodule MediaCentaurWeb.Components.Thing do
        def load do
          Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> work() end)
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/thing.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end

    test "async_nolink in a web LiveView is reported" do
      ~S'''
      defmodule MediaCentaurWeb.NewLive do
        def handle_event(_, _, socket) do
          Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn ->
            expensive_load()
          end)

          {:noreply, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/new_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end

    test "async_stream_nolink in a web LiveView is reported" do
      ~S'''
      defmodule MediaCentaurWeb.NewLive do
        def handle_event(_, _, socket) do
          MediaCentaur.TaskSupervisor
          |> Task.Supervisor.async_stream_nolink(paths, &probe/1)
          |> Enum.to_list()

          {:noreply, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/new_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end

    # The rollout is complete and the grandfather list is empty — no web
    # LiveView is exempt anymore (regression guard against re-adding one).
    test "previously-grandfathered LiveView is now enforced" do
      ~S'''
      defmodule MediaCentaurWeb.SettingsLive do
        def handle_event(_, _, socket) do
          Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> work() end)
          {:noreply, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/settings_live.ex")
      |> run_check(OwnedAsyncInWeb)
      |> assert_issue()
    end
  end
end
