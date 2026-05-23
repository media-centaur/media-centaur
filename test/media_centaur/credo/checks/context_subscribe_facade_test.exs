defmodule MediaCentaur.Credo.Checks.ContextSubscribeFacadeTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ContextSubscribeFacade

  describe "clean code (negative cases)" do
    test "context facade calls are allowed in LiveViews" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView

        def mount(_, _, socket) do
          if connected?(socket) do
            MediaCentaur.Library.subscribe()
            MediaCentaur.Playback.subscribe()
          end

          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(ContextSubscribeFacade)
      |> refute_issues()
    end

    test "direct PubSub.subscribe is allowed in context modules themselves" do
      ~S'''
      defmodule MediaCentaur.Library do
        def subscribe do
          Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/library.ex")
      |> run_check(ContextSubscribeFacade)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "direct PubSub.subscribe in a LiveView is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView

        def mount(_, _, socket) do
          if connected?(socket) do
            Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
          end

          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(ContextSubscribeFacade)
      |> assert_issue()
    end

    test "aliased PubSub.subscribe in a LiveView is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use Phoenix.LiveView
        alias Phoenix.PubSub

        def mount(_, _, socket) do
          PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(ContextSubscribeFacade)
      |> assert_issue()
    end
  end
end
