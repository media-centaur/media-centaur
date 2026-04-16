defmodule MediaCentarr.Playback.ResolverTest do
  use MediaCentarr.DataCase

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.Playback.Resolver

  defp mark_completed(progress) do
    Library.mark_watch_completed!(progress)
  end

  describe "resolve/1 with Entity UUID" do
    test "movie entity resolves with resume when partially watched" do
      movie =
        create_entity(%{type: :movie, name: "Sample Movie", content_url: "/movies/br.mkv"})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 1200.0,
        duration_seconds: 7200.0
      })

      assert {:ok, params} = Resolver.resolve(movie.id)
      assert params.action == :resume
      assert params.entity_id == movie.id
      assert params.entity_name == "Sample Movie"
      assert params.content_url == "/movies/br.mkv"
      assert params.start_position == 1200.0
    end

    test "movie entity plays from beginning when unwatched" do
      movie =
        create_entity(%{type: :movie, name: "Sample Movie Fourteen", content_url: "/movies/arrival.mkv"})

      assert {:ok, params} = Resolver.resolve(movie.id)
      assert params.action == :play_next
      assert params.content_url == "/movies/arrival.mkv"
      assert params.start_position == 0.0
    end

    test "tv_series entity resolves via Resume algorithm" do
      tv_series = create_entity(%{type: :tv_series, name: "Severance"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      ep1 =
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
        episode_id: ep1.id,
        position_seconds: 3000.0,
        duration_seconds: 3100.0
      })
      |> mark_completed()

      assert {:ok, params} = Resolver.resolve(tv_series.id)
      assert params.action == :play_next
      assert params.content_url == "/tv/sev/s01e02.mkv"
      assert params.start_position == 0.0
    end

    test "movie_series entity resolves via Resume algorithm" do
      movie_series = create_entity(%{type: :movie_series, name: "Alien Collection"})

      create_movie(%{
        movie_series_id: movie_series.id,
        name: "Alien",
        content_url: "/movies/alien.mkv",
        position: 0
      })

      create_movie(%{
        movie_series_id: movie_series.id,
        name: "Aliens",
        content_url: "/movies/aliens.mkv",
        position: 1
      })

      assert {:ok, params} = Resolver.resolve(movie_series.id)
      assert params.action == :play_next
      assert params.content_url == "/movies/alien.mkv"
    end

    test "entity with no content returns error" do
      movie = create_entity(%{type: :movie, name: "No Content"})

      assert {:error, :no_playable_content} = Resolver.resolve(movie.id)
    end
  end

  describe "resolve/1 with Episode UUID" do
    test "episode resolves with resume when partially watched" do
      tv_series = create_entity(%{type: :tv_series, name: "Severance"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 3,
          name: "Who Is Alive?",
          content_url: "/tv/sev/s01e03.mkv"
        })

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 600.0,
        duration_seconds: 3200.0
      })

      assert {:ok, params} = Resolver.resolve(episode.id)
      assert params.action == :resume
      assert params.entity_id == tv_series.id
      assert params.entity_name == "Severance"
      assert params.season_number == 1
      assert params.episode_number == 3
      assert params.episode_name == "Who Is Alive?"
      assert params.content_url == "/tv/sev/s01e03.mkv"
      assert params.start_position == 600.0
    end

    test "episode plays from beginning when unwatched" do
      tv_series = create_entity(%{type: :tv_series, name: "Severance"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 2})

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
      tv_series = create_entity(%{type: :tv_series, name: "Missing Files"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

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
      movie_series = create_entity(%{type: :movie_series, name: "Alien Collection"})

      movie =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Alien",
          content_url: "/movies/alien.mkv",
          position: 0
        })

      # Movie ordinal is 1 (1-based)
      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 2400.0,
        duration_seconds: 7000.0
      })

      assert {:ok, params} = Resolver.resolve(movie.id)
      assert params.action == :resume
      assert params.entity_id == movie_series.id
      assert params.entity_name == "Alien Collection"
      assert params.season_number == 0
      assert params.episode_number == 1
      assert params.episode_name == "Alien"
      assert params.content_url == "/movies/alien.mkv"
      assert params.start_position == 2400.0
    end

    test "child movie plays from beginning when unwatched" do
      movie_series = create_entity(%{type: :movie_series, name: "Alien Collection"})

      movie =
        create_movie(%{
          movie_series_id: movie_series.id,
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
      movie_series = create_entity(%{type: :movie_series, name: "Incomplete"})
      movie = create_movie(%{movie_series_id: movie_series.id, name: "No File", position: 0})

      assert {:error, :no_playable_content} = Resolver.resolve(movie.id)
    end
  end

  describe "resolve/1 with Extra UUID" do
    test "extra resolves, plays from beginning" do
      movie = create_entity(%{type: :movie, name: "Sample Movie One"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Making Of",
          content_url: "/extras/making_of.mkv"
        })

      assert {:ok, params} = Resolver.resolve(extra.id)
      assert params.action == :play_extra
      assert params.entity_id == movie.id
      assert params.entity_name == "Sample Movie One"
      assert params.episode_name == "Making Of"
      assert params.content_url == "/extras/making_of.mkv"
      assert params.start_position == 0.0
    end

    test "extra with nil content_url returns error" do
      movie = create_entity(%{type: :movie, name: "Broken Extra"})
      extra = create_extra(%{movie_id: movie.id, name: "Missing", content_url: nil})

      assert {:error, :no_playable_content} = Resolver.resolve(extra.id)
    end
  end

  describe "resolve/1 with unknown UUID" do
    test "returns not_found" do
      assert {:error, :not_found} = Resolver.resolve(Ecto.UUID.generate())
    end
  end
end
