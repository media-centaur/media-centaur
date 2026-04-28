defmodule MediaCentarr.Playback.ResumeTargetTest do
  use ExUnit.Case, async: true

  import MediaCentarr.TestFactory

  alias MediaCentarr.Playback.ResumeTarget

  # --- Single items (Movie / VideoObject) ---

  describe "compute/2 — Movie" do
    test "no progress → begin with name" do
      entity = build_entity(%{type: :movie, name: "Sample Movie", content_url: "/m.mkv"})

      result = ResumeTarget.compute(entity, [])

      assert result == %{"action" => "begin", "name" => "Sample Movie"}
    end

    test "partial progress → resume with position/duration" do
      entity = build_entity(%{type: :movie, name: "Sample Movie", content_url: "/m.mkv"})

      progress = [
        build_progress(%{position_seconds: 4500.0, duration_seconds: 9840.0, completed: false})
      ]

      result = ResumeTarget.compute(entity, progress)

      assert result == %{
               "action" => "resume",
               "name" => "Sample Movie",
               "positionSeconds" => 4500.0,
               "durationSeconds" => 9840.0
             }
    end

    test "completed → nil" do
      entity = build_entity(%{type: :movie, name: "Sample Movie", content_url: "/m.mkv"})

      progress = [
        build_progress(%{position_seconds: 9800.0, duration_seconds: 9840.0, completed: true})
      ]

      assert ResumeTarget.compute(entity, progress) == nil
    end

    test "no content_url → nil" do
      entity = build_entity(%{type: :movie, name: "No File", content_url: nil})
      assert ResumeTarget.compute(entity, []) == nil
    end
  end

  # --- TV Series ---

  describe "compute/2 — TVSeries" do
    test "no progress → begin first episode" do
      {entity, episode_ids} = build_tv_entity()

      result = ResumeTarget.compute(entity, [])

      assert result == %{
               "action" => "begin",
               "targetId" => Enum.at(episode_ids, 0),
               "name" => "Pilot",
               "seasonNumber" => 1,
               "episodeNumber" => 1
             }
    end

    test "mid-episode → resume with position" do
      {entity, episode_ids} = build_tv_entity()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 1),
          position_seconds: 1200.5,
          duration_seconds: 3600.0,
          completed: false,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        })
      ]

      result = ResumeTarget.compute(entity, progress)

      assert result == %{
               "action" => "resume",
               "targetId" => Enum.at(episode_ids, 1),
               "name" => "The One",
               "seasonNumber" => 1,
               "episodeNumber" => 2,
               "positionSeconds" => 1200.5,
               "durationSeconds" => 3600.0
             }
    end

    test "completed episode, next available → begin next" do
      {entity, episode_ids} = build_tv_entity()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        })
      ]

      result = ResumeTarget.compute(entity, progress)

      assert result == %{
               "action" => "begin",
               "targetId" => Enum.at(episode_ids, 1),
               "name" => "The One",
               "seasonNumber" => 1,
               "episodeNumber" => 2
             }
    end

    test "all episodes completed → nil" do
      {entity, episode_ids} = build_tv_entity()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -120, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 1),
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 2),
          completed: true,
          last_watched_at: now
        })
      ]

      assert ResumeTarget.compute(entity, progress) == nil
    end
  end

  # --- MovieSeries ---

  describe "compute/2 — MovieSeries" do
    test "no progress → begin first movie" do
      {entity, movie_ids} = build_movie_series_entity()

      result = ResumeTarget.compute(entity, [])

      assert result == %{
               "action" => "begin",
               "targetId" => Enum.at(movie_ids, 0),
               "name" => "Sample Movie One",
               "ordinal" => 1,
               "total" => 3
             }
    end

    test "mid-movie → resume with position" do
      {entity, movie_ids} = build_movie_series_entity()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          completed: true,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        }),
        build_progress(%{
          movie_id: Enum.at(movie_ids, 1),
          position_seconds: 4500.0,
          duration_seconds: 9000.0,
          completed: false,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        })
      ]

      result = ResumeTarget.compute(entity, progress)

      assert result == %{
               "action" => "resume",
               "targetId" => Enum.at(movie_ids, 1),
               "name" => "Sample Movie Two",
               "ordinal" => 2,
               "total" => 3,
               "positionSeconds" => 4500.0,
               "durationSeconds" => 9000.0
             }
    end

    test "completed first, begin second" do
      {entity, movie_ids} = build_movie_series_entity()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        })
      ]

      result = ResumeTarget.compute(entity, progress)

      assert result == %{
               "action" => "begin",
               "targetId" => Enum.at(movie_ids, 1),
               "name" => "Sample Movie Two",
               "ordinal" => 2,
               "total" => 3
             }
    end

    test "all completed → nil" do
      {entity, movie_ids} = build_movie_series_entity()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -120, :second)
        }),
        build_progress(%{
          movie_id: Enum.at(movie_ids, 1),
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          movie_id: Enum.at(movie_ids, 2),
          completed: true,
          last_watched_at: now
        })
      ]

      assert ResumeTarget.compute(entity, progress) == nil
    end
  end

  # --- Child targets ---

  describe "compute_child_targets/2 — TVSeries" do
    test "mixed progress returns keyed map" do
      {entity, episode_ids} = build_tv_entity()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 1),
          position_seconds: 1200.0,
          duration_seconds: 3600.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ResumeTarget.compute_child_targets(entity, progress)

      # Episode 1 completed → nil
      assert result[Enum.at(episode_ids, 0)] == nil
      # Episode 2 partial → resume
      assert result[Enum.at(episode_ids, 1)] == %{
               "action" => "resume",
               "positionSeconds" => 1200.0,
               "durationSeconds" => 3600.0
             }

      # Episode 3 no progress → begin
      assert result[Enum.at(episode_ids, 2)] == %{"action" => "begin"}
    end
  end

  describe "compute_child_targets/2 — MovieSeries" do
    test "mixed progress returns keyed map" do
      {entity, movie_ids} = build_movie_series_entity()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          movie_id: Enum.at(movie_ids, 1),
          position_seconds: 4500.0,
          duration_seconds: 9000.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ResumeTarget.compute_child_targets(entity, progress)

      # Movie 1 completed → nil
      assert result[Enum.at(movie_ids, 0)] == nil
      # Movie 2 partial → resume
      assert result[Enum.at(movie_ids, 1)] == %{
               "action" => "resume",
               "positionSeconds" => 4500.0,
               "durationSeconds" => 9000.0
             }

      # Movie 3 no progress → begin
      assert result[Enum.at(movie_ids, 2)] == %{"action" => "begin"}
    end
  end

  describe "compute_child_targets/2 — single items" do
    test "returns nil for Movie" do
      entity = build_entity(%{type: :movie, name: "Solo Movie", content_url: "/m.mkv"})
      assert ResumeTarget.compute_child_targets(entity, []) == nil
    end
  end

  # --- Test data builders ---

  defp build_tv_entity do
    ep1 = build_episode(%{episode_number: 1, name: "Pilot", content_url: "/s1e1.mkv"})
    ep2 = build_episode(%{episode_number: 2, name: "The One", content_url: "/s1e2.mkv"})
    ep3 = build_episode(%{episode_number: 3, name: "Third", content_url: "/s1e3.mkv"})
    season = build_season(%{season_number: 1, episodes: [ep1, ep2, ep3]})

    entity =
      build_entity(%{
        type: :tv_series,
        name: "Test Show",
        seasons: [season]
      })

    {entity, [ep1.id, ep2.id, ep3.id]}
  end

  defp build_movie_series_entity do
    m1 = build_movie(%{name: "Sample Movie One", content_url: "/m1.mkv", position: 0})
    m2 = build_movie(%{name: "Sample Movie Two", content_url: "/m2.mkv", position: 1})
    m3 = build_movie(%{name: "Sample Movie Three", content_url: "/m3.mkv", position: 2})

    entity =
      build_entity(%{
        type: :movie_series,
        name: "Sample Movie Series",
        movies: [m1, m2, m3]
      })

    {entity, [m1.id, m2.id, m3.id]}
  end
end
