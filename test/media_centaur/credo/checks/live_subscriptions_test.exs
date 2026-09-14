defmodule MediaCentaur.Credo.Checks.LiveSubscriptionsTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.LiveSubscriptions

  describe "clean code (negative cases)" do
    test "subscribing through the door is allowed" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView
        alias MediaCentaurWeb.Live.Subscriptions

        def mount(_, _, socket) do
          socket =
            socket
            |> Subscriptions.subscribe(MediaCentaur.Library)
            |> Subscriptions.subscribe({MediaCentaur.Acquisition, :subscribe_queue})

          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(LiveSubscriptions)
      |> refute_issues()
    end

    test "a module under live/ that defines subscribe/0 is a facade and may subscribe through Topics" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive.SearchSession do
        alias MediaCentaur.Topics

        def subscribe, do: Topics.subscribe(Topics.acquisition_search())
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live/search_session.ex")
      |> run_check(LiveSubscriptions)
      |> refute_issues()
    end

    test "the door itself calls the context" do
      ~S'''
      defmodule MediaCentaurWeb.Live.Subscriptions do
        def subscribe(socket, module) do
          module.subscribe()
          socket
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/subscriptions.ex")
      |> run_check(LiveSubscriptions)
      |> refute_issues()
    end

    test "a file outside live/ is not checked" do
      ~S'''
      defmodule MediaCentaur.Something do
        def go, do: Library.subscribe()
      end
      '''
      |> to_source_file("lib/media_centaur/something.ex")
      |> run_check(LiveSubscriptions)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "a context's subscribe/0 called directly is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView

        def mount(_, _, socket) do
          if connected?(socket), do: WatchHistory.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(LiveSubscriptions)
      |> assert_issue()
    end

    test "a fully qualified call is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView

        def mount(_, _, socket) do
          if connected?(socket), do: MediaCentaur.Library.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(LiveSubscriptions)
      |> assert_issue()
    end

    test "Topics.subscribe/1 in a LiveView is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView
        alias MediaCentaur.Topics

        def mount(_, _, socket) do
          if connected?(socket), do: Topics.subscribe(Topics.pipeline_stats())
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(LiveSubscriptions)
      |> assert_issue()
    end

    test "a trait under live/ is held to the same rule" do
      ~S'''
      defmodule MediaCentaurWeb.Live.SomethingAware do
        def on_mount(:default, _, _, socket) do
          if Phoenix.LiveView.connected?(socket), do: Settings.subscribe()
          {:cont, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/something_aware.ex")
      |> run_check(LiveSubscriptions)
      |> assert_issue()
    end
  end
end
