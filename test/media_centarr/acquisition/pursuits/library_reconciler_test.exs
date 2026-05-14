defmodule MediaCentarr.Acquisition.Pursuits.LibraryReconcilerTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.{Event, LibraryReconciler, Pursuit}

  defp insert_active_pursuit(overrides) do
    {pursuit, _target} =
      create_pursuit_with_target(Map.merge(%{recipe_type: "tmdb"}, overrides))

    pursuit
  end

  defp pursuit_events(pursuit_id) do
    Event
    |> Ecto.Query.where(pursuit_id: ^pursuit_id)
    |> Repo.all()
  end

  describe "reconcile_active/0 — TV pursuits" do
    test "satisfies an active TV pursuit whose episode is present in the library" do
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "777"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 2})

      _episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 5,
          name: "Sample Episode",
          content_url: "/library/Sample.Show.S02E05.mkv"
        })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 5
        })

      assert :ok = LibraryReconciler.reconcile_active()

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
      assert Enum.any?(pursuit_events(pursuit.id), &(&1.kind == "pursuit_satisfied"))
    end

    test "leaves an active TV pursuit untouched when no matching library episode exists" do
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "777"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 2})

      create_episode(%{
        season_id: season.id,
        episode_number: 3,
        content_url: "/library/Sample.Show.S02E03.mkv"
      })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 5
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end

    test "leaves an active TV pursuit untouched when the library episode has no file (content_url nil)" do
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "777"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 2})

      create_episode(%{
        season_id: season.id,
        episode_number: 5,
        content_url: nil
      })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 5
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end
  end

  describe "reconcile_active/0 — movie pursuits" do
    test "satisfies an active movie pursuit whose movie is present in the library" do
      _movie =
        create_movie(%{
          name: "Sample Movie",
          tmdb_id: "555",
          content_url: "/library/Sample.Movie.2024.mkv"
        })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "555",
          tmdb_type: "movie",
          title: "Sample Movie"
        })

      assert :ok = LibraryReconciler.reconcile_active()

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
      assert Enum.any?(pursuit_events(pursuit.id), &(&1.kind == "pursuit_satisfied"))
    end

    test "leaves an active movie pursuit untouched when the library movie has no file" do
      _movie =
        create_movie(%{
          name: "Sample Movie",
          tmdb_id: "555",
          content_url: nil
        })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "555",
          tmdb_type: "movie",
          title: "Sample Movie"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end
  end

  describe "reconcile_active/0 — scope" do
    test "ignores prowlarr_query pursuits (no TMDB recipe to match against the library)" do
      pursuit =
        insert_active_pursuit(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          title: "Some manual query",
          manual_query: "Some manual query"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end

    test "ignores terminal-state pursuits even when a library match exists" do
      _movie =
        create_movie(%{
          name: "Sample Movie",
          tmdb_id: "555",
          content_url: "/library/Sample.Movie.2024.mkv"
        })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "555",
          tmdb_type: "movie",
          title: "Sample Movie"
        })

      pursuit
      |> Ecto.Changeset.change(state: "cancelled")
      |> Repo.update!()

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "cancelled"
    end

    test "is idempotent — running twice on a satisfied pursuit is a no-op" do
      _movie =
        create_movie(%{
          name: "Sample Movie",
          tmdb_id: "555",
          content_url: "/library/Sample.Movie.2024.mkv"
        })

      pursuit =
        insert_active_pursuit(%{
          tmdb_id: "555",
          tmdb_type: "movie",
          title: "Sample Movie"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert :ok = LibraryReconciler.reconcile_active()

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"

      satisfied_events = Enum.filter(pursuit_events(pursuit.id), &(&1.kind == "pursuit_satisfied"))

      assert length(satisfied_events) == 1
    end
  end
end
