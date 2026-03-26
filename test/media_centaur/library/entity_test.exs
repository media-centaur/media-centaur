defmodule MediaCentaur.Library.EntityTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "create" do
    test "id is a UUID and survives a round-trip read" do
      entity = create_entity(%{type: :movie, name: "Round Trip"})

      assert {:ok, [found]} = Library.list_entities()
      assert found.id == entity.id
    end

    test "creates a movie with all fields" do
      entity =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          description: "A young blade runner discovers a secret.",
          date_published: "2017-10-06",
          genres: ["Science Fiction", "Drama"],
          url: "https://www.themoviedb.org/movie/335984",
          duration: "PT2H44M",
          director: "Denis Villeneuve",
          content_rating: "R",
          aggregate_rating_value: 7.5
        })

      assert entity.type == :movie
      assert entity.name == "Sample Movie"
      assert entity.description == "A young blade runner discovers a secret."
      assert entity.date_published == "2017-10-06"
      assert entity.genres == ["Science Fiction", "Drama"]
      assert entity.url == "https://www.themoviedb.org/movie/335984"
      assert entity.duration == "PT2H44M"
      assert entity.director == "Denis Villeneuve"
      assert entity.content_rating == "R"
      assert entity.aggregate_rating_value == 7.5
    end

    test "creates with minimal required fields only" do
      entity = create_entity(%{type: :tv_series, name: "Severance"})

      assert entity.type == :tv_series
      assert entity.name == "Severance"
      assert entity.description == nil
      assert entity.genres == nil
      assert entity.date_published == nil
    end

    test "movie type round-trips correctly" do
      entity = create_entity(%{type: :movie, name: "Movie Entity"})
      assert entity.type == :movie
    end

    test "tv_series type round-trips correctly" do
      entity = create_entity(%{type: :tv_series, name: "TV Entity"})
      assert entity.type == :tv_series
    end

    test "movie_series type round-trips correctly" do
      entity = create_entity(%{type: :movie_series, name: "Movie Series Entity"})
      assert entity.type == :movie_series
    end
  end

  describe "set_content_url" do
    test "updates content_url on an existing entity" do
      entity = create_entity(%{type: :movie, name: "Direct Play"})
      assert entity.content_url == nil

      updated = Library.set_entity_content_url!(entity, %{content_url: "/media/movies/test.mkv"})

      assert updated.content_url == "/media/movies/test.mkv"
    end
  end

  describe "with_associations" do
    test "preloads images" do
      entity = create_entity(%{type: :movie, name: "With Images"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        content_url: "#{entity.id}/poster.jpg",
        extension: "jpg"
      })

      {:ok, [loaded]} = Library.list_entities_with_associations()

      assert length(loaded.images) == 1
      assert hd(loaded.images).role == "poster"
    end

    test "preloads identifiers" do
      entity = create_entity(%{type: :movie, name: "With Identifiers"})

      create_identifier(%{
        entity_id: entity.id,
        property_id: "tmdb",
        value: "335984"
      })

      {:ok, [loaded]} = Library.list_entities_with_associations()

      assert length(loaded.identifiers) == 1
      assert hd(loaded.identifiers).property_id == "tmdb"
      assert hd(loaded.identifiers).value == "335984"
    end

    test "preloads seasons with episodes" do
      entity = create_entity(%{type: :tv_series, name: "With Seasons"})
      season = create_season(%{entity_id: entity.id, season_number: 1, name: "Season 1"})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/tv/show/S01/S01E01.mkv"
      })

      {:ok, [loaded]} = Library.list_entities_with_associations()

      assert length(loaded.seasons) == 1
      assert hd(loaded.seasons).season_number == 1
      assert length(hd(loaded.seasons).episodes) == 1
      assert hd(hd(loaded.seasons).episodes).name == "Pilot"
    end

    test "preloads watch_progress" do
      entity = create_entity(%{type: :movie, name: "With Progress"})

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 600.0,
        duration_seconds: 7200.0
      })

      {:ok, [loaded]} = Library.list_entities_with_associations()

      assert length(loaded.watch_progress) == 1
      assert hd(loaded.watch_progress).position_seconds == 600.0
    end
  end
end
