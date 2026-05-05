defmodule MediaCentarr.Credo.Checks.DestructiveFileQueryTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.DestructiveFileQuery

  describe "flags destructive queries on file-presence tables (positive cases)" do
    test "Repo.delete_all on KnownFile without :watch_dir filter" do
      ~S'''
      defmodule Naive do
        import Ecto.Query

        def purge(ids) do
          Repo.delete_all(from(k in KnownFile, where: k.id in ^ids))
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> assert_issue()
    end

    test "Repo.delete_all on WatchedFile without :watch_dir filter" do
      ~S'''
      defmodule Naive do
        import Ecto.Query

        def purge(ids) do
          Repo.delete_all(from(w in WatchedFile, where: w.id in ^ids))
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> assert_issue()
    end

    test "fully-qualified schema reference is flagged the same way" do
      ~S'''
      defmodule Naive do
        import Ecto.Query

        def purge(ids) do
          Repo.delete_all(
            from(k in MediaCentarr.Watcher.KnownFile, where: k.id in ^ids)
          )
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> assert_issue()
    end
  end

  describe "allows destructive queries with availability filter (negative cases)" do
    test "KnownFile delete with :watch_dir in available_dirs is allowed" do
      ~S'''
      defmodule Safe do
        import Ecto.Query

        def purge(available) do
          Repo.delete_all(
            from(k in KnownFile,
              where: k.state == :absent and k.watch_dir in ^available
            )
          )
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> refute_issues()
    end

    test "WatchedFile delete that joins on :watch_dir is allowed" do
      ~S'''
      defmodule Safe do
        import Ecto.Query

        def purge(dir) do
          Repo.delete_all(from(w in WatchedFile, where: w.watch_dir == ^dir))
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> refute_issues()
    end
  end

  describe "leaves out-of-scope schemas alone" do
    test "Repo.delete_all on a non-target schema is not flagged" do
      ~S'''
      defmodule Other do
        import Ecto.Query

        def purge(ids) do
          Repo.delete_all(from(c in ChangeEntry, where: c.id in ^ids))
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> refute_issues()
    end

    test "Repo.delete_all with a dynamic schema variable is not flagged" do
      # The check can't know what schema the variable points to;
      # rather than false-positive, defer to the author. The
      # entity-cascade and clear-database paths look like this and
      # carry their own override comments at the call site.
      ~S'''
      defmodule Cascade do
        import Ecto.Query

        def purge(schema, ids) do
          Repo.delete_all(from(r in schema, where: r.id in ^ids))
        end
      end
      '''
      |> to_source_file()
      |> run_check(DestructiveFileQuery)
      |> refute_issues()
    end
  end
end
