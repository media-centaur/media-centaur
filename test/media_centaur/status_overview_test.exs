defmodule MediaCentaur.StatusOverviewTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Status
  alias MediaCentaur.Status.LibraryOverview

  describe "load_overview/0" do
    test "returns a zeroed overview for an empty library" do
      overview = Status.load_overview()

      assert %LibraryOverview{} = overview
      assert overview.movie_count == 0
      assert overview.show_count == 0
      assert overview.episode_count == 0
      assert overview.total_size_bytes == 0
      assert overview.recently_added == []
      assert overview.pending_review_count == 0
      assert overview.in_flight_count == 0
      assert overview.missing_metadata_count == 0
      assert overview.incomplete_season_count == 0
      assert is_integer(overview.missing_artwork_count)
    end

    test "reflects library counts, size and recency" do
      create_movie(%{name: "Present Movie", tmdb_id: "1", content_url: "/media/movie.mkv"})

      MediaCentaur.Library.FilePresence.stamp("/media/movie.mkv", "/media", DateTime.utc_now(),
        size: 4_096
      )

      series = create_tv_series(%{name: "A Show", tmdb_id: "2"})
      season = create_season(%{season_number: 1, tv_series_id: series.id})
      create_episode(%{episode_number: 1, season_id: season.id})

      overview = Status.load_overview()

      assert overview.movie_count == 1
      assert overview.show_count == 1
      assert overview.episode_count == 1
      assert overview.total_size_bytes == 4_096
      assert overview.recently_added != []
    end

    test "counts pending review files and metadata gaps" do
      create_pending_file(%{file_path: "/media/incoming/mystery.mkv"})
      create_movie(%{name: "Unmatched Movie"})

      overview = Status.load_overview()

      assert overview.pending_review_count == 1
      assert overview.missing_metadata_count == 1
    end
  end
end
