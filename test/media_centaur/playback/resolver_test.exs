defmodule MediaCentaur.Playback.ResolverTest do
  use MediaCentaur.DataCase

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.Resolver

  defp mark_completed(progress) do
    Library.mark_watch_completed!(progress)
  end

  describe "resolve/1 with Entity UUID" do
    test "movie entity resolves with resume when partially watched" do
      entity = create_entity(%{type: :movie, name: "Sample Movie", content_url: "/movies/br.mkv"})

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 0,
        episode_number: 0,
        position_seconds: 1200.0,
        duration_seconds: 7200.0
      })

      assert {:ok, params} = Resolver.resolve(entity.id)
      assert params.action == :resume
      assert params.entity_id == entity.id
      assert params.entity_name == "Sample Movie"
      assert params.content_url == "/movies/br.mkv"
      assert params.start_position == 1200.0
    end

    test "movie entity plays from beginning when unwatched" do
      entity = create_entity(%{type: :movie, name: "Sample Movie Fourteen", content_url: "/movies/arrival.mkv"})

      assert {:ok, params} = Resolver.resolve(entity.id)
      assert params.action == :play_next
      assert params.content_url == "/movies/arrival.mkv"
      assert params.start_position == 0.0
    end

    test "tv_series entity resolves via Resume algorithm" do
      entity = create_entity(%{type: :tv_series, name: "Severance"})
      season = create_season(%{entity_id: entity.id, season_number: 1})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Good News About Hell",
        content_url: "/tv/sev/s01e01.mkv"
      })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Half Loop",
        content_url: "/tv/sev/s01e02.mkv"
      })

      # Mark episode 1 as completed
      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 3000.0,
        duration_seconds: 3100.0
      })
      |> mark_completed()

      assert {:ok, params} = Resolver.resolve(entity.id)
      assert params.action == :play_next
      assert params.content_url == "/tv/sev/s01e02.mkv"
      assert params.start_position == 0.0
    end

    test "movie_series entity resolves via Resume algorithm" do
      entity = create_entity(%{type: :movie_series, name: "Alien Collection"})

      create_movie(%{
        entity_id: entity.id,
        name: "Alien",
        content_url: "/movies/alien.mkv",
        position: 0
      })

      create_movie(%{
        entity_id: entity.id,
        name: "Aliens",
        content_url: "/movies/aliens.mkv",
        position: 1
      })

      assert {:ok, params} = Resolver.resolve(entity.id)
      assert params.action == :play_next
      assert params.content_url == "/movies/alien.mkv"
    end

    test "entity with no content returns error" do
      entity = create_entity(%{type: :movie, name: "No Content"})

      assert {:error, :no_playable_content} = Resolver.resolve(entity.id)
    end
  end

  describe "resolve/1 with Episode UUID" do
    test "episode resolves with resume when partially watched" do
      entity = create_entity(%{type: :tv_series, name: "Severance"})
      season = create_season(%{entity_id: entity.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 3,
          name: "Who Is Alive?",
          content_url: "/tv/sev/s01e03.mkv"
        })

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 3,
        position_seconds: 600.0,
        duration_seconds: 3200.0
      })

      assert {:ok, params} = Resolver.resolve(episode.id)
      assert params.action == :resume
      assert params.entity_id == entity.id
      assert params.entity_name == "Severance"
      assert params.season_number == 1
      assert params.episode_number == 3
      assert params.episode_name == "Who Is Alive?"
      assert params.content_url == "/tv/sev/s01e03.mkv"
      assert params.start_position == 600.0
    end

    test "episode plays from beginning when unwatched" do
      entity = create_entity(%{type: :tv_series, name: "Severance"})
      season = create_season(%{entity_id: entity.id, season_number: 2})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Hello, Ms. Cobel",
          content_url: "/tv/sev/s02e01.mkv"
        })

      assert {:ok, params} = Resolver.resolve(episode.id)
      assert params.action == :play_episode
      assert params.content_url == "/tv/sev/s02e01.mkv"
      assert params.start_position == 0.0
    end

    test "episode with nil content_url returns error" do
      entity = create_entity(%{type: :tv_series, name: "Missing Files"})
      season = create_season(%{entity_id: entity.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "No File"
        })

      assert {:error, :no_playable_content} = Resolver.resolve(episode.id)
    end
  end

  describe "resolve/1 with Movie (child) UUID" do
    test "child movie resolves with resume when partially watched" do
      entity = create_entity(%{type: :movie_series, name: "Alien Collection"})

      movie =
        create_movie(%{
          entity_id: entity.id,
          name: "Alien",
          content_url: "/movies/alien.mkv",
          position: 0
        })

      # Movie ordinal is 1 (1-based), stored as season_number: 0, episode_number: 1
      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 0,
        episode_number: 1,
        position_seconds: 2400.0,
        duration_seconds: 7000.0
      })

      assert {:ok, params} = Resolver.resolve(movie.id)
      assert params.action == :resume
      assert params.entity_id == entity.id
      assert params.entity_name == "Alien Collection"
      assert params.season_number == 0
      assert params.episode_number == 1
      assert params.episode_name == "Alien"
      assert params.content_url == "/movies/alien.mkv"
      assert params.start_position == 2400.0
    end

    test "child movie plays from beginning when unwatched" do
      entity = create_entity(%{type: :movie_series, name: "Alien Collection"})

      movie =
        create_movie(%{
          entity_id: entity.id,
          name: "Aliens",
          content_url: "/movies/aliens.mkv",
          position: 1
        })

      assert {:ok, params} = Resolver.resolve(movie.id)
      assert params.action == :play_movie
      assert params.content_url == "/movies/aliens.mkv"
      assert params.start_position == 0.0
    end

    test "child movie with nil content_url returns error" do
      entity = create_entity(%{type: :movie_series, name: "Incomplete"})
      movie = create_movie(%{entity_id: entity.id, name: "No File", position: 0})

      assert {:error, :no_playable_content} = Resolver.resolve(movie.id)
    end
  end

  describe "resolve/1 with Extra UUID" do
    test "extra resolves, plays from beginning" do
      entity = create_entity(%{type: :movie, name: "Sample Movie One"})

      extra =
        create_extra(%{
          entity_id: entity.id,
          name: "Making Of",
          content_url: "/extras/making_of.mkv"
        })

      assert {:ok, params} = Resolver.resolve(extra.id)
      assert params.action == :play_extra
      assert params.entity_id == entity.id
      assert params.entity_name == "Sample Movie One"
      assert params.episode_name == "Making Of"
      assert params.content_url == "/extras/making_of.mkv"
      assert params.start_position == 0.0
    end

    test "extra with nil content_url returns error" do
      entity = create_entity(%{type: :movie, name: "Broken Extra"})
      extra = create_extra(%{entity_id: entity.id, name: "Missing", content_url: nil})

      assert {:error, :no_playable_content} = Resolver.resolve(extra.id)
    end
  end

  describe "resolve/1 with unknown UUID" do
    test "returns not_found" do
      assert {:error, :not_found} = Resolver.resolve(Ash.UUID.generate())
    end
  end
end
