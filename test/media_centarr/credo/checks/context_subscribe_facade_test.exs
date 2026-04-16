defmodule MediaCentarr.Credo.Checks.ContextSubscribeFacadeTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.ContextSubscribeFacade

  describe "clean code (negative cases)" do
    test "context facade calls are allowed in LiveViews" do
      ~S'''
      defmodule MediaCentarrWeb.MyLive do
        use Phoenix.LiveView

        def mount(_, _, socket) do
          if connected?(socket) do
            MediaCentarr.Library.subscribe()
            MediaCentarr.Playback.subscribe()
          end

          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/my_live.ex")
      |> run_check(ContextSubscribeFacade)
      |> refute_issues()
    end

    test "direct PubSub.subscribe is allowed in context modules themselves" do
      ~S'''
      defmodule MediaCentarr.Library do
        def subscribe do
          Phoenix.PubSub.subscribe(MediaCentarr.PubSub, "library:updates")
        end
      end
      '''
      |> to_source_file("lib/media_centarr/library.ex")
      |> run_check(ContextSubscribeFacade)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "direct PubSub.subscribe in a LiveView is reported" do
      ~S'''
      defmodule MediaCentarrWeb.MyLive do
        use Phoenix.LiveView

        def mount(_, _, socket) do
          if connected?(socket) do
            Phoenix.PubSub.subscribe(MediaCentarr.PubSub, "library:updates")
          end

          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/my_live.ex")
      |> run_check(ContextSubscribeFacade)
      |> assert_issue()
    end

    test "aliased PubSub.subscribe in a LiveView is reported" do
      ~S'''
      defmodule MediaCentarrWeb.MyLive do
        use Phoenix.LiveView
        alias Phoenix.PubSub

        def mount(_, _, socket) do
          PubSub.subscribe(MediaCentarr.PubSub, "library:updates")
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/my_live.ex")
      |> run_check(ContextSubscribeFacade)
      |> assert_issue()
    end
  end
end
