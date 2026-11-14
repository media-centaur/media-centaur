defmodule MediaCentaur.Playback.ResolverTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.Resolver

  defp mark_completed(progress, nil) do
    Library.ProgressRecords.mark_completed!(progress, nil)
  end

  describe "resolve/2 with Entity UUID" do
    test "movie entity resolves with resume when partially watched" do
      movie =
        create_entity(%{type: :movie, name: "Sample Movie", content_url: "/movies/sample.mkv"})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 1200.0,
        duration_seconds: 7200.0
      })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), movie.id)
      assert params.entry.entity_id == movie.id
      assert params.entry.entity_name == "Sample Movie"
      assert params.entry.content_url == "/movies/sample.mkv"
      assert params.entry.start_position == 1200.0
    end

    test "movie entity plays from beginning when unwatched" do
      movie =
        create_entity(%{type: :movie, name: "Other Movie", content_url: "/movies/other.mkv"})

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), movie.id)
      assert params.entry.content_url == "/movies/other.mkv"
      assert params.entry.start_position == 0.0
    end

    test "tv_series entity resolves to the first episode without a watched mark" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      ep1 =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/show/s01e01.mkv"
        })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Episode Two",
        content_url: "/tv/show/s01e02.mkv"
      })

      # Mark episode 1 as completed
      mark_completed(
        create_watch_progress(%{
          episode_id: ep1.id,
          position_seconds: 3000.0,
          duration_seconds: 3100.0
        }),
        nil
      )

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), tv_series.id)
      assert params.entry.content_url == "/tv/show/s01e02.mkv"
      assert params.entry.start_position == 0.0
    end

    test "movie_series entity resolves to its first movie" do
      movie_series = create_entity(%{type: :movie_series, name: "Sample Movie Series"})

      create_movie(%{
        movie_series_id: movie_series.id,
        name: "Sample Movie One",
        content_url: "/movies/movie1.mkv",
        position: 0
      })

      create_movie(%{
        movie_series_id: movie_series.id,
        name: "Sample Movie Two",
        content_url: "/movies/movie2.mkv",
        position: 1
      })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), movie_series.id)
      assert params.entry.content_url == "/movies/movie1.mkv"
    end

    test "entity with no content returns error" do
      movie = create_entity(%{type: :movie, name: "No Content"})

      assert {:error, :no_playable_content} = Resolver.resolve(owner_profile_id(), movie.id)
    end
  end

  describe "resolve/2 reads the profile's own row" do
    test "resume position comes from the session's profile, not another's" do
      movie = create_entity(%{type: :movie, name: "Sample Movie", content_url: "/movies/sample.mkv"})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id

      create_watch_progress(%{
        profile_id: ana,
        movie_id: movie.id,
        position_seconds: 600.0,
        duration_seconds: 7200.0
      })

      assert {:ok, %{entry: %{start_position: 600.0}}} = Resolver.resolve(ana, movie.id)
      assert {:ok, %{entry: %{start_position: start}}} = Resolver.resolve(me, movie.id)
      assert start == 0.0
    end
  end

  describe "resolve/2 reads the title progress" do
    setup do
      profile_id = owner_profile_id()
      series = create_entity(%{type: :tv_series, name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      episodes =
        for number <- 1..3 do
          create_episode(%{
            season_id: season.id,
            episode_number: number,
            name: "Episode #{number}",
            content_url: "/tv/sample-show/s01e0#{number}.mkv"
          })
        end

      %{profile_id: profile_id, series: series, episodes: episodes}
    end

    defp mark_all_and_finish(profile_id, episodes, finished) do
      rows =
        for episode <- episodes do
          create_watch_progress(%{profile_id: profile_id, episode_id: episode.id, completed: true})
        end

      row = Enum.at(rows, finished - 1)
      create_series_watch_position(%{profile_id: profile_id, playable_item_id: row.playable_item_id})
    end

    test "a fully watched series continues after the series watch position", context do
      mark_all_and_finish(context.profile_id, context.episodes, 1)

      assert {:ok, %{entry: entry}} = Resolver.resolve(context.profile_id, context.series.id)

      assert %{season_number: 1, episode_number: 2, episode_name: "Episode 2", start_position: +0.0} =
               entry

      assert entry.episode_id == Enum.at(context.episodes, 1).id
    end

    test "a complete series plays its first episode from the start", context do
      mark_all_and_finish(context.profile_id, context.episodes, 3)

      assert {:ok, %{entry: %{episode_number: 1, start_position: +0.0}}} =
               Resolver.resolve(context.profile_id, context.series.id)
    end

    test "the next episode starts at its own viewing when it has one that counts", context do
      [_first, second, _third] = context.episodes
      mark_all_and_finish(context.profile_id, context.episodes, 1)

      create_watch_progress(%{
        profile_id: context.profile_id,
        episode_id: second.id,
        completed: true,
        position_seconds: 600.0,
        duration_seconds: 1300.0
      })

      assert {:ok, %{entry: %{episode_number: 2, episode_name: "Episode 2", start_position: 600.0}}} =
               Resolver.resolve(context.profile_id, context.series.id)
    end

    test "a series whose rows were marked by hand, without a timestamp, resolves", context do
      [first, second, _third] = context.episodes
      actor = MediaCentaur.Profiles.Actor.new(context.profile_id)

      for episode <- [first, second] do
        {:ok, %{last_watched_at: nil}} =
          Library.ProgressRecords.toggle_watched(actor, :episode, episode.id)
      end

      assert {:ok, %{entry: %{episode_number: 3, start_position: +0.0}}} =
               Resolver.resolve(context.profile_id, context.series.id)
    end

    test "an episode played directly resumes only a viewing that counts", context do
      [short, long, watched] = context.episodes

      create_watch_progress(%{
        profile_id: context.profile_id,
        episode_id: short.id,
        position_seconds: 30.0,
        duration_seconds: 1300.0
      })

      create_watch_progress(%{
        profile_id: context.profile_id,
        episode_id: long.id,
        position_seconds: 600.0,
        duration_seconds: 1300.0
      })

      create_watch_progress(%{
        profile_id: context.profile_id,
        episode_id: watched.id,
        completed: true,
        position_seconds: 700.0,
        duration_seconds: 1300.0
      })

      assert {:ok, %{entry: %{start_position: +0.0}}} = Resolver.resolve(context.profile_id, short.id)
      assert {:ok, %{entry: %{start_position: 600.0}}} = Resolver.resolve(context.profile_id, long.id)
      assert {:ok, %{entry: %{start_position: 700.0}}} = Resolver.resolve(context.profile_id, watched.id)
    end

    test "a collection movie played directly resumes only a viewing that counts", context do
      collection = create_entity(%{type: :movie_series, name: "Sample Collection"})

      [short, watched] =
        for {name, position} <- [{"Movie A", 0}, {"Movie B", 1}] do
          create_movie(%{
            movie_series_id: collection.id,
            name: name,
            content_url: "/movies/sample-collection-#{position}.mkv",
            position: position
          })
        end

      create_watch_progress(%{
        profile_id: context.profile_id,
        movie_id: short.id,
        position_seconds: 30.0,
        duration_seconds: 5400.0
      })

      create_watch_progress(%{
        profile_id: context.profile_id,
        movie_id: watched.id,
        completed: true,
        position_seconds: 900.0,
        duration_seconds: 5400.0
      })

      assert {:ok, %{entry: %{start_position: +0.0}}} = Resolver.resolve(context.profile_id, short.id)
      assert {:ok, %{entry: %{start_position: 900.0}}} = Resolver.resolve(context.profile_id, watched.id)
    end

    test "an extra resumes only a viewing that counts", context do
      movie = create_entity(%{type: :movie, name: "Movie A", content_url: "/movies/movie-a.mkv"})

      [short, long] =
        for name <- ["Featurette A", "Featurette B"] do
          create_extra(%{movie_id: movie.id, name: name, content_url: "/movies/extras/#{name}.mkv"})
        end

      for {extra, position} <- [{short, 30.0}, {long, 240.0}] do
        Library.ProgressRecords.find_or_create_for_extra!(%{
          profile_id: context.profile_id,
          extra_id: extra.id,
          position_seconds: position,
          duration_seconds: 600.0
        })
      end

      assert {:ok, %{entry: %{start_position: +0.0}}} = Resolver.resolve(context.profile_id, short.id)
      assert {:ok, %{entry: %{start_position: 240.0}}} = Resolver.resolve(context.profile_id, long.id)
    end
  end

  describe "resolve/2 with Episode UUID" do
    test "episode resolves with resume when partially watched" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 3,
          name: "Episode Three",
          content_url: "/tv/show/s01e03.mkv"
        })

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 600.0,
        duration_seconds: 3200.0
      })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), episode.id)
      assert params.entry.entity_id == tv_series.id
      assert params.entry.entity_name == "Sample Show"

      assert params.entry.season_number == 1
      assert params.entry.episode_number == 3
      assert params.entry.episode_name == "Episode Three"
      assert params.entry.content_url == "/tv/show/s01e03.mkv"
      assert params.entry.start_position == 600.0
    end

    test "episode plays from beginning when unwatched" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 2})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Season Two Pilot",
          content_url: "/tv/show/s02e01.mkv"
        })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), episode.id)
      assert params.entry.content_url == "/tv/show/s02e01.mkv"
      assert params.entry.start_position == 0.0
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

      assert {:error, :no_playable_content} = Resolver.resolve(owner_profile_id(), episode.id)
    end
  end

  describe "resolve/2 with Movie (child) UUID" do
    test "child movie resolves with resume when partially watched" do
      movie_series = create_entity(%{type: :movie_series, name: "Sample Movie Series"})

      movie =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Sample Movie One",
          content_url: "/movies/movie1.mkv",
          position: 0
        })

      # Movie ordinal is 1 (1-based)
      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 2400.0,
        duration_seconds: 7000.0
      })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), movie.id)
      assert params.entry.entity_id == movie_series.id
      assert params.entry.entity_name == "Sample Movie Series"
      assert params.entry.season_number == 0
      assert params.entry.episode_number == 1
      assert params.entry.episode_name == "Sample Movie One"
      assert params.entry.content_url == "/movies/movie1.mkv"
      assert params.entry.start_position == 2400.0
    end

    test "child movie plays from beginning when unwatched" do
      movie_series = create_entity(%{type: :movie_series, name: "Sample Movie Series"})

      movie =
        create_movie(%{
          movie_series_id: movie_series.id,
          name: "Sample Movie Two",
          content_url: "/movies/movie2.mkv",
          position: 1
        })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), movie.id)
      assert params.entry.content_url == "/movies/movie2.mkv"
      assert params.entry.start_position == 0.0
    end

    test "child movie with nil content_url returns error" do
      movie_series = create_entity(%{type: :movie_series, name: "Incomplete"})
      movie = create_movie(%{movie_series_id: movie_series.id, name: "No File", position: 0})

      assert {:error, :no_playable_content} = Resolver.resolve(owner_profile_id(), movie.id)
    end
  end

  describe "resolve/2 with Extra UUID" do
    test "extra resolves, plays from beginning" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Making Of",
          content_url: "/extras/making_of.mkv"
        })

      assert {:ok, params} = Resolver.resolve(owner_profile_id(), extra.id)
      assert params.entry.entity_id == movie.id
      assert params.entry.entity_name == "Sample Movie"
      assert params.entry.episode_name == "Making Of"
      assert params.entry.content_url == "/extras/making_of.mkv"
      assert params.entry.start_position == 0.0
    end

    test "extra with nil content_url returns error" do
      movie = create_entity(%{type: :movie, name: "Broken Extra"})
      extra = create_extra(%{movie_id: movie.id, name: "Missing", content_url: nil})

      assert {:error, :no_playable_content} = Resolver.resolve(owner_profile_id(), extra.id)
    end
  end

  describe "resolve/2 with unknown UUID" do
    test "returns not_found" do
      assert {:error, :not_found} = Resolver.resolve(owner_profile_id(), Ecto.UUID.generate())
    end
  end
end
