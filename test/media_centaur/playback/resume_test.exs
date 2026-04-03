defmodule MediaCentaur.Playback.ResumeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.Resume

  # Helper to build a minimal entity map
  defp movie(url) do
    %{type: :movie, content_url: url, seasons: nil, movies: nil}
  end

  defp tv_series(seasons) do
    %{type: :tv_series, content_url: nil, seasons: seasons, movies: nil}
  end

  defp season(number, episodes) do
    %{season_number: number, episodes: episodes}
  end

  defp episode(number, url) do
    %{id: Ecto.UUID.generate(), episode_number: number, content_url: url}
  end

  defp movie_series(movies) do
    %{type: :movie_series, content_url: nil, seasons: nil, movies: movies}
  end

  defp child_movie(url, position) do
    %{
      id: Ecto.UUID.generate(),
      name: "Movie #{position + 1}",
      content_url: url,
      position: position,
      date_published: nil
    }
  end

  defp progress(opts) do
    %{
      episode_id: Keyword.get(opts, :episode_id),
      movie_id: Keyword.get(opts, :movie_id),
      position_seconds: Keyword.get(opts, :position, 0.0),
      duration_seconds: Keyword.get(opts, :duration, 0.0),
      completed: Keyword.get(opts, :completed, false),
      last_watched_at: Keyword.get(opts, :last_watched_at, ~U[2026-01-01 00:00:00Z])
    }
  end

  describe "Movie" do
    test "no progress → play_next" do
      entity = movie("/videos/blade-runner.mkv")
      assert {:play_next, "/videos/blade-runner.mkv", position} = Resume.resolve(entity, [])
      assert position == 0.0
    end

    test "partial progress → resume" do
      entity = movie("/videos/blade-runner.mkv")
      records = [progress(position: 1200.5, duration: 3200.0)]

      assert {:resume, "/videos/blade-runner.mkv", 1200.5} = Resume.resolve(entity, records)
    end

    test "completed → play_next (replay from start)" do
      entity = movie("/videos/blade-runner.mkv")
      records = [progress(position: 3100.0, duration: 3200.0, completed: true)]

      assert {:play_next, "/videos/blade-runner.mkv", position} =
               Resume.resolve(entity, records)

      assert position == 0.0
    end
  end

  describe "TVSeries" do
    test "no progress → play_next first episode" do
      entity =
        tv_series([
          season(1, [
            episode(1, "/tv/show/S01E01.mkv"),
            episode(2, "/tv/show/S01E02.mkv")
          ])
        ])

      assert {:play_next, "/tv/show/S01E01.mkv", position} = Resume.resolve(entity, [])
      assert position == 0.0
    end

    test "partial episode → resume" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      entity = tv_series([season(1, [ep1, ep2])])

      records = [
        progress(
          episode_id: ep1.id,
          position: 500.0,
          duration: 2800.0,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:resume, "/tv/show/S01E01.mkv", 500.0} = Resume.resolve(entity, records)
    end

    test "completed mid-season → play_next episode" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      ep3 = episode(3, "/tv/show/S01E03.mkv")
      entity = tv_series([season(1, [ep1, ep2, ep3])])

      records = [
        progress(
          episode_id: ep1.id,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          episode_id: ep2.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/tv/show/S01E03.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "season boundary → play_next first episode of next season" do
      s1e1 = episode(1, "/tv/show/S01E01.mkv")
      s1e2 = episode(2, "/tv/show/S01E02.mkv")
      s2e1 = episode(1, "/tv/show/S02E01.mkv")
      entity = tv_series([season(1, [s1e1, s1e2]), season(2, [s2e1])])

      records = [
        progress(
          episode_id: s1e1.id,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          episode_id: s1e2.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/tv/show/S02E01.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "all episodes completed → restart from first" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      entity = tv_series([season(1, [ep1, ep2])])

      records = [
        progress(
          episode_id: ep1.id,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          episode_id: ep2.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:restart, "/tv/show/S01E01.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "skip episodes missing content_url" do
      entity =
        tv_series([
          season(1, [
            episode(1, nil),
            episode(2, "/tv/show/S01E02.mkv"),
            episode(3, "/tv/show/S01E03.mkv")
          ])
        ])

      assert {:play_next, "/tv/show/S01E02.mkv", position} = Resume.resolve(entity, [])
      assert position == 0.0
    end
  end

  describe "MovieSeries" do
    test "no progress → play_next first movie" do
      entity =
        movie_series([
          child_movie("/movies/first.mkv", 0),
          child_movie("/movies/second.mkv", 1)
        ])

      assert {:play_next, "/movies/first.mkv", position} = Resume.resolve(entity, [])
      assert position == 0.0
    end

    test "partial progress on first movie → resume" do
      m1 = child_movie("/movies/first.mkv", 0)
      m2 = child_movie("/movies/second.mkv", 1)
      entity = movie_series([m1, m2])

      records = [
        progress(
          movie_id: m1.id,
          position: 1200.5,
          duration: 7200.0,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:resume, "/movies/first.mkv", 1200.5} = Resume.resolve(entity, records)
    end

    test "completed first movie → play_next second movie" do
      m1 = child_movie("/movies/first.mkv", 0)
      m2 = child_movie("/movies/second.mkv", 1)
      m3 = child_movie("/movies/third.mkv", 2)
      entity = movie_series([m1, m2, m3])

      records = [
        progress(
          movie_id: m1.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/movies/second.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "all movies completed → restart from first" do
      m1 = child_movie("/movies/first.mkv", 0)
      m2 = child_movie("/movies/second.mkv", 1)
      entity = movie_series([m1, m2])

      records = [
        progress(
          movie_id: m1.id,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          movie_id: m2.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:restart, "/movies/first.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "skips movies without content_url" do
      entity =
        movie_series([
          child_movie(nil, 0),
          child_movie("/movies/second.mkv", 1)
        ])

      assert {:play_next, "/movies/second.mkv", position} = Resume.resolve(entity, [])
      assert position == 0.0
    end

    test "no movies with content_url → no_playable_content" do
      entity =
        movie_series([
          child_movie(nil, 0),
          child_movie(nil, 1)
        ])

      assert {:no_playable_content} = Resume.resolve(entity, [])
    end

    test "single movie behaves like walking" do
      m1 = child_movie("/movies/solo.mkv", 0)
      entity = movie_series([m1])

      records = [
        progress(movie_id: m1.id, position: 600.0, duration: 3600.0)
      ]

      assert {:resume, "/movies/solo.mkv", 600.0} = Resume.resolve(entity, records)
    end
  end

  describe "no playable content" do
    test "movie with no content_url" do
      entity = %{type: :movie, content_url: nil, seasons: nil, movies: nil}
      assert {:no_playable_content} = Resume.resolve(entity, [])
    end

    test "tv series with no episodes having content_url" do
      entity =
        tv_series([
          season(1, [
            episode(1, nil),
            episode(2, nil)
          ])
        ])

      assert {:no_playable_content} = Resume.resolve(entity, [])
    end
  end
end
