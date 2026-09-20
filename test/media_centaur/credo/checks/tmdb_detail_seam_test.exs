defmodule MediaCentaur.Credo.Checks.TmdbDetailSeamTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.TmdbDetailSeam

  @collection_callers [
    "lib/media_centaur/pipeline/stages/fetch_metadata.ex",
    "lib/media_centaur/pipeline/image_refresh.ex",
    "lib/media_centaur/pipeline/image_repair.ex"
  ]

  describe "clean code (negative cases)" do
    test "the store may call detail/2" do
      ~S'''
      defmodule MediaCentaur.TMDB.Store do
        alias MediaCentaur.TMDB.Client

        def first_contact(ref), do: Client.detail(ref)
      end
      '''
      |> to_source_file("lib/media_centaur/tmdb/store.ex")
      |> run_check(TmdbDetailSeam)
      |> refute_issues()
    end

    test "the import stage and the artwork paths may fetch a collection" do
      for path <- @collection_callers do
        ~S'''
        defmodule MediaCentaur.Pipeline.Something do
          def collection(id), do: MediaCentaur.TMDB.Client.get_collection(id)
        end
        '''
        |> to_source_file(path)
        |> run_check(TmdbDetailSeam)
        |> refute_issues()
      end
    end

    test "a test file is exempt" do
      ~S'''
      defmodule MediaCentaur.SomeTest do
        def probe, do: MediaCentaur.TMDB.Client.detail({1, :movie})
      end
      '''
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(TmdbDetailSeam)
      |> refute_issues()
    end

    test "reading the store is not a fetch" do
      ~S'''
      defmodule MediaCentaur.Acquisition.Targeting do
        alias MediaCentaur.TMDB.Store

        def universe(id), do: Store.ensure({id, :tv_series})
      end
      '''
      |> to_source_file("lib/media_centaur/acquisition/targeting.ex")
      |> run_check(TmdbDetailSeam)
      |> refute_issues()
    end
  end

  describe "violations" do
    test "detail/2 outside the store, under every spelling of the client" do
      ~S'''
      defmodule MediaCentaur.Acquisition.Targeting do
        alias MediaCentaur.TMDB
        alias MediaCentaur.TMDB.Client

        def one(ref), do: Client.detail(ref)
        def two(ref), do: TMDB.Client.detail(ref, [])
        def three(ref), do: MediaCentaur.TMDB.Client.detail(ref)
      end
      '''
      |> to_source_file("lib/media_centaur/acquisition/targeting.ex")
      |> run_check(TmdbDetailSeam)
      |> assert_issues(fn issues -> assert length(issues) == 3 end)
    end

    test "a collection fetch outside its three callers" do
      ~S'''
      defmodule MediaCentaur.Discovery do
        alias MediaCentaur.TMDB.Client

        def parts(id), do: Client.get_collection(id)
      end
      '''
      |> to_source_file("lib/media_centaur/discovery.ex")
      |> run_check(TmdbDetailSeam)
      |> assert_issue(fn issue -> assert issue.trigger == "get_collection" end)
    end
  end
end
