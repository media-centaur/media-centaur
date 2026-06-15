defmodule MediaCentaur.Library.PresentableQueriesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.PresentableQueries
  alias MediaCentaur.Repo

  # Post-Phase-4 (library-presence-unification): `create_linked_file/1`
  # already auto-stamps a Library.FilePresence, so a linked file IS a
  # present file. The legacy `Watcher.FilePresence.record_file` no
  # longer participates in the presentable subquery.
  defp create_present_file(attrs), do: create_linked_file(attrs)

  # And "absent" is structurally "no WatchedFile" — there is no longer
  # a `linked but absent` row state to construct. Helper retained for
  # call-site readability.
  defp create_absent_file(_attrs), do: nil

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

  describe "present_movie_counts/1" do
    test "counts present children per movie_series" do
      multi = create_movie_series(%{name: "Multi"})
      m1 = create_movie(%{name: "M1", movie_series_id: multi.id})
      m2 = create_movie(%{name: "M2", movie_series_id: multi.id})
      _f1 = create_present_file(%{movie_id: m1.id})
      _f2 = create_present_file(%{movie_id: m2.id})

      single = create_movie_series(%{name: "Single"})
      s1 = create_movie(%{name: "S1", movie_series_id: single.id})
      _f3 = create_present_file(%{movie_id: s1.id})

      counts =
        [multi.id, single.id]
        |> PresentableQueries.present_movie_counts()
        |> Repo.all()
        |> Map.new()

      assert counts[multi.id] == 2
      assert counts[single.id] == 1
    end

    test "omits movie_series with no present children" do
      ms = create_movie_series(%{name: "All Absent"})
      _m = create_movie(%{name: "A1", movie_series_id: ms.id})

      assert Repo.all(PresentableQueries.present_movie_counts([ms.id])) == []
    end

    test "returns no rows for an empty id list" do
      assert Repo.all(PresentableQueries.present_movie_counts([])) == []
    end
  end
end
