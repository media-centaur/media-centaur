defmodule MediaCentaur.Acquisition.Pursuits.LibraryReconcilerTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, LibraryReconciler, Pursuit}

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

  describe "reconcile_active/0 — prowlarr_query pursuits" do
    test "satisfies a prowlarr_query pursuit whose downloaded file is present in the library" do
      # The grabbed release downloads to a file named after the release; the
      # pipeline imports it (TMDB-matched), so the library file basename
      # matches the pursuit's release title even though the pursuit has no
      # tmdb_id of its own.
      _movie =
        create_movie(%{
          name: "Sample Movie",
          tmdb_id: "555",
          content_url: "/library/Sample.Movie.2024.1080p.BluRay.x264-GRP.mkv"
        })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          manual_query: "Sample Movie 2024",
          title: "Sample.Movie.2024.1080p.BluRay.x264-GRP",
          status: "acquired",
          release_title: "Sample.Movie.2024.1080p.BluRay.x264-GRP"
        })

      assert :ok = LibraryReconciler.reconcile_active()

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
      assert Enum.any?(pursuit_events(pursuit.id), &(&1.kind == "pursuit_satisfied"))
    end

    test "satisfies via release name when the title bakes the container as a trailing token" do
      # Some indexers name the release with the container extension as a
      # space-separated token ("... x264-FS mkv"). The landed file's leaf is
      # extension-stripped before indexing, so the normalized release name
      # (…x264fsmkv) only matches if the leaf is *also* indexed with its
      # extension. Without that, the one-token "mkv" drift orphans the
      # pursuit (the production Mortal Kombat II miss). content_path is nil
      # here — the download was gone before it could be captured — so this
      # exercises the path-less release-name safety net.
      _movie =
        create_movie(%{
          name: "Sample Movie",
          tmdb_id: "556",
          content_url: "/library/Sample.Movie.2026.1080p.DCPRip.x264-FS.mkv"
        })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          manual_query: "Sample Movie 2026",
          title: "Sample Movie 2026 1080p DCPRip x264-FS mkv",
          status: "acquired",
          release_title: "Sample Movie 2026 1080p DCPRip x264-FS mkv"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end

    test "leaves a prowlarr_query pursuit active when no library file matches its release" do
      _movie =
        create_movie(%{
          name: "Other Movie",
          tmdb_id: "999",
          content_url: "/library/Other.Movie.2019.720p.WEB-DL-XYZ.mkv"
        })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          manual_query: "Sample Movie 2024",
          title: "Sample.Movie.2024.1080p.BluRay.x264-GRP",
          status: "acquired",
          release_title: "Sample.Movie.2024.1080p.BluRay.x264-GRP"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end
  end

  describe "reconcile_active/0 — multi-file pack (prowlarr_query)" do
    test "satisfies a pack pursuit by matching the release-folder ancestor, not the leaf basename" do
      # A complete-series pack downloads as one torrent whose top-level
      # folder is named after the release; the pipeline imports the
      # individual episode files in place, preserving that folder as an
      # ancestor of every episode path. The pursuit carries no tmdb_id
      # (manual grab) and its content_path is the stale *incomplete*
      # download dir — but the release-folder name survives as a path
      # segment, which is the only durable binding back to the library.
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "888"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})
      base = "/srv/media/Sample.Show.S01-S03.COMPLETE.SERIES.1080p.BluRay.x265-GRP"

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        content_url:
          "#{base}/Sample.Show.S01.1080p.BluRay.x265-GRP/Sample.Show.S01E01.1080p.BluRay.x265-GRP.mkv"
      })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        content_url:
          "#{base}/Sample.Show.S01.1080p.BluRay.x265-GRP/Sample.Show.S01E02.1080p.BluRay.x265-GRP.mkv"
      })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          manual_query: "Sample Show Complete Series",
          title: "Sample.Show.S01-S03.COMPLETE.SERIES.1080p.BluRay.x265-GRP",
          status: "acquired",
          release_title: "Sample Show S01-S03 COMPLETE SERIES 1080p BluRay x265-GRP",
          content_path: "/downloads/incomplete/Sample.Show.S01-S03.COMPLETE.SERIES.1080p.BluRay.x265-GRP"
        })

      assert :ok = LibraryReconciler.reconcile_active()

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
      assert Enum.any?(pursuit_events(pursuit.id), &(&1.kind == "pursuit_satisfied"))
    end

    test "leaves a pack pursuit active when its release folder is not present in the library" do
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "888"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        content_url:
          "/srv/media/Other.Show.S01.1080p.BluRay.x265-GRP/Other.Show.S01E01.1080p.BluRay.x265-GRP.mkv"
      })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          manual_query: "Sample Show Complete Series",
          title: "Sample.Show.S01-S03.COMPLETE.SERIES.1080p.BluRay.x265-GRP",
          status: "acquired",
          release_title: "Sample Show S01-S03 COMPLETE SERIES 1080p BluRay x265-GRP",
          content_path: "/downloads/incomplete/Sample.Show.S01-S03.COMPLETE.SERIES.1080p.BluRay.x265-GRP"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end
  end

  describe "reconcile_active/0 — content_path match" do
    test "satisfies via the target's content_path even when title + tmdb don't match" do
      _movie =
        create_movie(%{
          name: "Renamed Movie",
          content_url: "/library/Renamed.Movie.Different.Name.mkv"
        })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          title: "Original.Release.Name.2024-GRP",
          release_title: "Original.Release.Name.2024-GRP",
          content_path: "/library/Renamed.Movie.Different.Name.mkv"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end

    test "satisfies when the content_path is a directory containing the present file" do
      _movie =
        create_movie(%{
          name: "Folder Movie",
          content_url: "/downloads/Folder.Movie.2024-GRP/Folder.Movie.2024-GRP.mkv"
        })

      {pursuit, _target} =
        create_pursuit_with_target(%{
          recipe_type: "prowlarr_query",
          tmdb_id: nil,
          tmdb_type: nil,
          title: "Folder.Movie.2024-GRP",
          release_title: "no-title-match",
          content_path: "/downloads/Folder.Movie.2024-GRP"
        })

      assert :ok = LibraryReconciler.reconcile_active()
      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end
  end

  describe "reconcile_active/0 — scope" do
    test "leaves a prowlarr_query pursuit active when it has no matched release to look up" do
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
