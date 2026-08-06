defmodule MediaCentaur.Credo.Checks.LookupNamingContractTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.LookupNamingContract

  describe "violations" do
    test "fetch_* returning a bare Repo.get_by is flagged" do
      ~S'''
      defmodule MediaCentaur.Library.ProgressRecords do
        def fetch_for_extra(extra_id), do: Repo.get_by(ExtraProgress, extra_id: extra_id)
      end
      '''
      |> to_source_file("lib/media_centaur/library/progress_records.ex")
      |> run_check(LookupNamingContract)
      |> assert_issue(fn issue ->
        assert issue.trigger == "fetch_for_extra"
        assert issue.message =~ "nil"
      end)
    end

    test "fetch_* returning a bare Repo.get is flagged" do
      ~S'''
      defmodule Some.Context do
        def fetch_item(id) do
          Repo.get(Item, id)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/some/context.ex")
      |> run_check(LookupNamingContract)
      |> assert_issue()
    end

    test "get_* returning an ok/error tuple is flagged" do
      ~S'''
      defmodule MediaCentaur.Review do
        def get_pending_file(id) do
          case Repo.get(PendingFile, id) do
            nil -> {:error, :not_found}
            file -> {:ok, file}
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/review.ex")
      |> run_check(LookupNamingContract)
      |> assert_issue(fn issue ->
        assert issue.trigger == "get_pending_file"
        assert issue.message =~ "fetch"
      end)
    end

    test "bare get/1 returning an ok/error tuple is flagged" do
      ~S'''
      defmodule MediaCentaur.Acquisition.Pursuits do
        def get(id) do
          case Repo.get(Pursuit, id) do
            nil -> {:error, :not_found}
            %Pursuit{} = pursuit -> {:ok, pursuit}
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/acquisition/pursuits.ex")
      |> run_check(LookupNamingContract)
      |> assert_issue()
    end

    test "a bang lookup that returns nil instead of raising is flagged" do
      ~S'''
      defmodule Some.Context do
        def get_item!(id) do
          Repo.get(Item, id)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/some/context.ex")
      |> run_check(LookupNamingContract)
      |> assert_issue()
    end
  end

  describe "conforming code" do
    test "fetch_* returning an ok/error tuple is allowed" do
      ~S'''
      defmodule MediaCentaur.Library.Containers do
        def fetch(type, id) do
          case Repo.get(schema(type), id) do
            nil -> {:error, :not_found}
            record -> {:ok, record}
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/library/containers.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "get_* returning a nil-able Repo lookup is allowed" do
      ~S'''
      defmodule MediaCentaur.ReleaseTracking do
        def get_item(id), do: Repo.get(Item, id)
      end
      '''
      |> to_source_file("lib/media_centaur/release_tracking.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "get_* backed by Map.get or Enum.find is allowed" do
      ~S'''
      defmodule MediaCentaur.Controls.Catalog do
        def get(id), do: Enum.find(@bindings, &(&1.id == id))
        def get_config(key), do: Map.get(:persistent_term.get({__MODULE__, :config}), key)
      end
      '''
      |> to_source_file("lib/media_centaur/controls/catalog.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "an HTTP client get_* is not second-guessed (shape not determinable)" do
      ~S'''
      defmodule MediaCentaur.TMDB.Client do
        def get_movie(tmdb_id, client \\ default_client()) do
          request(client, "/movie/#{tmdb_id}")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/tmdb/client.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "a cache-then-database get_* is not second-guessed" do
      ~S'''
      defmodule MediaCentaur.Settings do
        def get_by_key(key) do
          case :persistent_term.get(@cache_key, :__unset) do
            :__unset -> Repo.get_by(Entry, key: key)
            entries -> Map.get(entries, key)
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/settings.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "a bang lookup backed by Repo.get! is allowed" do
      ~S'''
      defmodule MediaCentaur.Library.Containers do
        def get_with_associations!(type, id) do
          preload_full(type, Repo.get!(schema(type), id))
        end
      end
      '''
      |> to_source_file("lib/media_centaur/library/containers.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "plural fetch_* collection readers are not lookups" do
      ~S'''
      defmodule MediaCentaur.ReleaseTracking.Helpers do
        def fetch_movie_releases(response) do
          Enum.map(response["results"], &extract/1)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/release_tracking/helpers.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "unrelated function names are ignored" do
      ~S'''
      defmodule Some.Context do
        def forget_item(id), do: Repo.get(Item, id)
      end
      '''
      |> to_source_file("lib/media_centaur/some/context.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "private functions are outside the public contract" do
      ~S'''
      defmodule Some.Context do
        defp fetch_item(id), do: Repo.get(Item, id)
      end
      '''
      |> to_source_file("lib/media_centaur/some/context.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end

    test "test-support helpers are not held to the contract" do
      ~S'''
      defmodule MediaCentaur.TestFactory do
        def fetch_item(id), do: Repo.get(Item, id)
      end
      '''
      |> to_source_file("test/support/factory.ex")
      |> run_check(LookupNamingContract)
      |> refute_issues()
    end
  end
end
