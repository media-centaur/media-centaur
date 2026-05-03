defmodule MediaCentarr.Library.PresentableQueriesTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.PresentableQueries
  alias MediaCentarr.Repo
  alias MediaCentarr.Watcher.FilePresence

  # Mirrors the helper in browser_test.exs: link a file via the Library context,
  # then register it as :present in watcher_files so the EXISTS subquery hits.
  defp create_present_file(attrs) do
    file = create_linked_file(attrs)
    FilePresence.record_file(file.file_path, file.watch_dir)
    file
  end

  defp create_absent_file(attrs) do
    file = create_linked_file(attrs)
    FilePresence.record_file(file.file_path, file.watch_dir)
    FilePresence.mark_files_absent([file.file_path])
    file
  end

  describe "multi_child_movie_series/0" do
    test "returns movie_series with 2+ present children" do
      ms = create_movie_series(%{name: "Multi Collection"})
      m1 = create_movie(%{name: "M1", movie_series_id: ms.id})
      m2 = create_movie(%{name: "M2", movie_series_id: ms.id})
      _f1 = create_present_file(%{movie_id: m1.id})
      _f2 = create_present_file(%{movie_id: m2.id})

      results = Repo.all(PresentableQueries.multi_child_movie_series())

      assert Enum.map(results, & &1.id) == [ms.id]
    end

    test "excludes movie_series with exactly 1 present child" do
      ms = create_movie_series(%{name: "Singleton Collection"})
      m1 = create_movie(%{name: "Only", movie_series_id: ms.id})
      _f = create_present_file(%{movie_id: m1.id})

      assert Repo.all(PresentableQueries.multi_child_movie_series()) == []
    end

    test "excludes movie_series whose extra children are absent" do
      ms = create_movie_series(%{name: "One Present One Absent"})
      m1 = create_movie(%{name: "Present", movie_series_id: ms.id})
      m2 = create_movie(%{name: "Absent", movie_series_id: ms.id})
      _present = create_present_file(%{movie_id: m1.id})
      _absent = create_absent_file(%{movie_id: m2.id})

      assert Repo.all(PresentableQueries.multi_child_movie_series()) == []
    end
  end

  describe "singleton_collection_movies/0" do
    test "returns the child movie of a movie_series with exactly 1 present child" do
      ms = create_movie_series(%{name: "Mascot Collection"})
      child = create_movie(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _f = create_present_file(%{movie_id: child.id})

      results = Repo.all(PresentableQueries.singleton_collection_movies())

      assert Enum.map(results, & &1.id) == [child.id]
    end

    test "excludes child movies whose movie_series has 2+ present children" do
      ms = create_movie_series(%{name: "Trilogy"})
      m1 = create_movie(%{name: "M1", movie_series_id: ms.id})
      m2 = create_movie(%{name: "M2", movie_series_id: ms.id})
      _f1 = create_present_file(%{movie_id: m1.id})
      _f2 = create_present_file(%{movie_id: m2.id})

      assert Repo.all(PresentableQueries.singleton_collection_movies()) == []
    end

    test "excludes standalone movies (no movie_series_id)" do
      standalone = create_standalone_movie(%{name: "Standalone"})
      _f = create_present_file(%{movie_id: standalone.id})

      assert Repo.all(PresentableQueries.singleton_collection_movies()) == []
    end
  end

  describe "standalone_movies/0" do
    test "returns movies without a movie_series_id and with present files" do
      m = create_standalone_movie(%{name: "Lonely Movie"})
      _f = create_present_file(%{movie_id: m.id})

      results = Repo.all(PresentableQueries.standalone_movies())
      assert Enum.map(results, & &1.id) == [m.id]
    end

    test "excludes movies belonging to a collection" do
      ms = create_movie_series(%{name: "Collection"})
      m = create_movie(%{name: "Inside Collection", movie_series_id: ms.id})
      _f = create_present_file(%{movie_id: m.id})

      assert Repo.all(PresentableQueries.standalone_movies()) == []
    end

    test "excludes standalone movies with only absent files" do
      m = create_standalone_movie(%{name: "Gone"})
      _f = create_absent_file(%{movie_id: m.id})

      assert Repo.all(PresentableQueries.standalone_movies()) == []
    end
  end

  describe "standalone_movies_by_record_count/0" do
    test "returns standalone movies regardless of file presence" do
      m = create_standalone_movie(%{name: "Lonely Movie"})
      _f = create_present_file(%{movie_id: m.id})

      results = Repo.all(PresentableQueries.standalone_movies_by_record_count())
      assert Enum.map(results, & &1.id) == [m.id]
    end

    test "excludes movies belonging to a collection" do
      ms = create_movie_series(%{name: "Collection"})
      m = create_movie(%{name: "Inside Collection", movie_series_id: ms.id})
      _f = create_present_file(%{movie_id: m.id})

      assert Repo.all(PresentableQueries.standalone_movies_by_record_count()) == []
    end

    test "includes standalone movies whose only file is absent" do
      m = create_standalone_movie(%{name: "Gone But Watched"})
      _f = create_absent_file(%{movie_id: m.id})

      results = Repo.all(PresentableQueries.standalone_movies_by_record_count())
      assert Enum.map(results, & &1.id) == [m.id]
    end

    test "includes standalone movies with no files at all" do
      m = create_standalone_movie(%{name: "Never Imported"})

      results = Repo.all(PresentableQueries.standalone_movies_by_record_count())
      assert Enum.map(results, & &1.id) == [m.id]
    end
  end

  describe "singleton_collection_movies_by_record_count/0" do
    test "returns the child movie of a movie_series with exactly 1 child Movie record" do
      ms = create_movie_series(%{name: "Mascot Collection"})
      child = create_movie(%{name: "Mascot Cosmos", movie_series_id: ms.id})
      _f = create_present_file(%{movie_id: child.id})

      results = Repo.all(PresentableQueries.singleton_collection_movies_by_record_count())

      assert Enum.map(results, & &1.id) == [child.id]
    end

    test "excludes child movies whose movie_series has 2+ child Movie records" do
      ms = create_movie_series(%{name: "Trilogy"})
      m1 = create_movie(%{name: "M1", movie_series_id: ms.id})
      m2 = create_movie(%{name: "M2", movie_series_id: ms.id})
      _f1 = create_present_file(%{movie_id: m1.id})
      _f2 = create_present_file(%{movie_id: m2.id})

      assert Repo.all(PresentableQueries.singleton_collection_movies_by_record_count()) == []
    end

    test "excludes standalone movies (no movie_series_id)" do
      standalone = create_standalone_movie(%{name: "Standalone"})
      _f = create_present_file(%{movie_id: standalone.id})

      assert Repo.all(PresentableQueries.singleton_collection_movies_by_record_count()) == []
    end

    test "includes a singleton-collection child whose file is absent" do
      ms = create_movie_series(%{name: "Solo Collection"})
      child = create_movie(%{name: "Only Movie", movie_series_id: ms.id})
      _f = create_absent_file(%{movie_id: child.id})

      results = Repo.all(PresentableQueries.singleton_collection_movies_by_record_count())
      assert Enum.map(results, & &1.id) == [child.id]
    end
  end

  describe "multi_child_movie_series_by_record_count/0" do
    test "returns movie_series with 2+ child Movie records" do
      ms = create_movie_series(%{name: "Multi Collection"})
      m1 = create_movie(%{name: "M1", movie_series_id: ms.id})
      m2 = create_movie(%{name: "M2", movie_series_id: ms.id})
      _f1 = create_present_file(%{movie_id: m1.id})
      _f2 = create_present_file(%{movie_id: m2.id})

      results = Repo.all(PresentableQueries.multi_child_movie_series_by_record_count())

      assert Enum.map(results, & &1.id) == [ms.id]
    end

    test "excludes movie_series with exactly 1 child Movie record" do
      ms = create_movie_series(%{name: "Singleton Collection"})
      m1 = create_movie(%{name: "Only", movie_series_id: ms.id})
      _f = create_present_file(%{movie_id: m1.id})

      assert Repo.all(PresentableQueries.multi_child_movie_series_by_record_count()) == []
    end

    test "excludes movie_series with 0 child Movie records" do
      _ms = create_movie_series(%{name: "Empty Collection"})

      assert Repo.all(PresentableQueries.multi_child_movie_series_by_record_count()) == []
    end

    test "includes movie_series with 2+ children even when all files are absent" do
      ms = create_movie_series(%{name: "Both Absent"})
      m1 = create_movie(%{name: "Absent 1", movie_series_id: ms.id})
      m2 = create_movie(%{name: "Absent 2", movie_series_id: ms.id})
      _f1 = create_absent_file(%{movie_id: m1.id})
      _f2 = create_absent_file(%{movie_id: m2.id})

      results = Repo.all(PresentableQueries.multi_child_movie_series_by_record_count())
      assert Enum.map(results, & &1.id) == [ms.id]
    end
  end
end
