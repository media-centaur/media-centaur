defmodule MediaCentarr.Library.EntityTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library

  describe "create" do
    test "id is a UUID and survives a round-trip read" do
      movie = create_entity(%{type: :movie, name: "Round Trip"})

      {:ok, found} = Library.fetch_movie(movie.id)
      assert found.id == movie.id
    end

    test "creates a movie with all fields" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          description: "A sample movie description.",
          date_published: "2017-10-06",
          genres: ["Science Fiction", "Drama"],
          url: "https://www.themoviedb.org/movie/335984",
          duration: "PT2H44M",
          director: "A. Director",
          content_rating: "R",
          aggregate_rating_value: 7.5
        })

      assert movie.name == "Sample Movie"
      assert movie.description == "A sample movie description."
      assert movie.date_published == "2017-10-06"
      assert movie.genres == ["Science Fiction", "Drama"]
      assert movie.url == "https://www.themoviedb.org/movie/335984"
      assert movie.duration == "PT2H44M"
      assert movie.director == "A. Director"
      assert movie.content_rating == "R"
      assert movie.aggregate_rating_value == 7.5
    end

    test "creates with minimal required fields only" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})

      assert tv_series.name == "Sample Show"
      assert tv_series.description == nil
      assert tv_series.genres == nil
      assert tv_series.date_published == nil
    end

    test "movie type round-trips correctly" do
      movie = create_entity(%{type: :movie, name: "Movie Entity"})
      {:ok, found} = Library.fetch_movie(movie.id)
      assert found.name == "Movie Entity"
    end

    test "tv_series type round-trips correctly" do
      tv_series = create_entity(%{type: :tv_series, name: "TV Entity"})
      {:ok, found} = Library.fetch_tv_series(tv_series.id)
      assert found.name == "TV Entity"
    end

    test "movie_series type round-trips correctly" do
      movie_series = create_entity(%{type: :movie_series, name: "Movie Series Entity"})
      {:ok, found} = Library.fetch_movie_series(movie_series.id)
      assert found.name == "Movie Series Entity"
    end
  end

  describe "set_content_url" do
    test "updates content_url on an existing movie" do
      movie = create_entity(%{type: :movie, name: "Direct Play"})
      assert movie.content_url == nil

      {:ok, updated} =
        Library.set_movie_content_url(movie, %{content_url: "/media/movies/test.mkv"})

      assert updated.content_url == "/media/movies/test.mkv"
    end
  end

  describe "with_associations" do
    test "preloads images" do
      movie = create_entity(%{type: :movie, name: "With Images"})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      {:ok, loaded} = Library.fetch_movie_with_associations(movie.id)

      assert length(loaded.images) == 1
      assert hd(loaded.images).role == "poster"
    end

    test "preloads external_ids" do
      movie = create_entity(%{type: :movie, name: "With External IDs"})

      create_external_id(%{
        movie_id: movie.id,
        source: "tmdb",
        external_id: "335984"
      })

      {:ok, loaded} = Library.fetch_movie_with_associations(movie.id)

      assert length(loaded.external_ids) == 1
      assert hd(loaded.external_ids).source == "tmdb"
      assert hd(loaded.external_ids).external_id == "335984"
    end

    test "preloads seasons with episodes" do
      tv_series = create_entity(%{type: :tv_series, name: "With Seasons"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1, name: "Season 1"})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/tv/show/S01/S01E01.mkv"
      })

      {:ok, loaded} = Library.fetch_tv_series_with_associations(tv_series.id)

      assert length(loaded.seasons) == 1
      assert hd(loaded.seasons).season_number == 1
      assert length(hd(loaded.seasons).episodes) == 1
      assert hd(hd(loaded.seasons).episodes).name == "Pilot"
    end

    test "preloads watch_progress" do
      movie = create_entity(%{type: :movie, name: "With Progress"})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 600.0,
        duration_seconds: 7200.0
      })

      {:ok, loaded} = Library.fetch_movie_with_associations(movie.id)

      assert loaded.watch_progress != nil
      assert loaded.watch_progress.position_seconds == 600.0
    end
  end
end
