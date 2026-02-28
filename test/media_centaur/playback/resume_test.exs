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
    %{episode_number: number, content_url: url}
  end

  defp progress(opts) do
    %{
      season_number: Keyword.get(opts, :season),
      episode_number: Keyword.get(opts, :episode),
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
      entity =
        tv_series([
          season(1, [
            episode(1, "/tv/show/S01E01.mkv"),
            episode(2, "/tv/show/S01E02.mkv")
          ])
        ])

      records = [
        progress(
          season: 1,
          episode: 1,
          position: 500.0,
          duration: 2800.0,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:resume, "/tv/show/S01E01.mkv", 500.0} = Resume.resolve(entity, records)
    end

    test "completed mid-season → play_next episode" do
      entity =
        tv_series([
          season(1, [
            episode(1, "/tv/show/S01E01.mkv"),
            episode(2, "/tv/show/S01E02.mkv"),
            episode(3, "/tv/show/S01E03.mkv")
          ])
        ])

      records = [
        progress(
          season: 1,
          episode: 1,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          season: 1,
          episode: 2,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/tv/show/S01E03.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "season boundary → play_next first episode of next season" do
      entity =
        tv_series([
          season(1, [
            episode(1, "/tv/show/S01E01.mkv"),
            episode(2, "/tv/show/S01E02.mkv")
          ]),
          season(2, [
            episode(1, "/tv/show/S02E01.mkv")
          ])
        ])

      records = [
        progress(
          season: 1,
          episode: 1,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          season: 1,
          episode: 2,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/tv/show/S02E01.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "all episodes completed → restart from first" do
      entity =
        tv_series([
          season(1, [
            episode(1, "/tv/show/S01E01.mkv"),
            episode(2, "/tv/show/S01E02.mkv")
          ])
        ])

      records = [
        progress(
          season: 1,
          episode: 1,
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          season: 1,
          episode: 2,
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
