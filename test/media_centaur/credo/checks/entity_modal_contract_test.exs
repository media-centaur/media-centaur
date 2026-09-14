defmodule MediaCentaur.Credo.Checks.EntityModalContractTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.EntityModalContract

  describe "the trait map" do
    test "names only traits that exist" do
      for {alias_path, _contexts} <- EntityModalContract.trait_subscribes() do
        module = Module.concat(alias_path)
        assert Code.ensure_loaded?(module), "#{inspect(module)} is in the MC0011 map but does not exist"
      end
    end
  end

  describe "clean code (negative cases)" do
    test "a host subscribing a context no trait owns is allowed" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use MediaCentaurWeb.Live.EntityModal

        def mount(_, _, socket) do
          if connected?(socket), do: WatchHistory.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(EntityModalContract)
      |> refute_issues()
    end

    test "a nested alias under an owned context is not the owned context" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use MediaCentaurWeb.Live.EntityModal

        def mount(_, _, socket) do
          if connected?(socket), do: Library.Views.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(EntityModalContract)
      |> refute_issues()
    end

    test "a file outside live/ is not checked" do
      ~S'''
      defmodule MediaCentaurWeb.Something do
        use MediaCentaurWeb.Live.EntityModal

        def mount(_, _, socket) do
          Library.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/something.ex")
      |> run_check(EntityModalContract)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "a short alias to an owned context is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use MediaCentaurWeb.Live.EntityModal

        def mount(_, _, socket) do
          if connected?(socket), do: Library.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(EntityModalContract)
      |> assert_issue()
    end

    test "a fully qualified call to an owned context is reported" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use MediaCentaurWeb.Live.EntityModal

        def mount(_, _, socket) do
          if connected?(socket), do: MediaCentaur.Library.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(EntityModalContract)
      |> assert_issue()
    end

    test "the title detail host owns ReleaseTracking" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use MediaCentaurWeb.Live.TitleDetailHost

        def mount(_, _, socket) do
          if connected?(socket), do: ReleaseTracking.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(EntityModalContract)
      |> assert_issue()
    end

    test "the title detail host owns Discovery too" do
      ~S'''
      defmodule MediaCentaurWeb.MyLive do
        use MediaCentaurWeb.Live.TitleDetailHost

        def mount(_, _, socket) do
          if connected?(socket), do: Discovery.subscribe()
          {:ok, socket}
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/my_live.ex")
      |> run_check(EntityModalContract)
      |> assert_issue()
    end
  end
end
