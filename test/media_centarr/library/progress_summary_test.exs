defmodule MediaCentarr.Library.ProgressSummaryTest do
  use ExUnit.Case, async: true

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.ProgressSummary

  describe "no progress" do
    test "empty list returns nil" do
      entity = build_entity(%{type: :movie, name: "No Progress"})
      assert ProgressSummary.compute(entity, []) == nil
    end
  end

  describe "Movie" do
    test "partial progress returns position/duration, completed 0, total 1" do
      entity = build_entity(%{type: :movie, name: "Movie"})

      progress = [
        build_progress(%{
          position_seconds: 600.0,
          duration_seconds: 7200.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == nil
      assert result.episode_position_seconds == 600.0
      assert result.episode_duration_seconds == 7200.0
      assert result.episodes_completed == 0
      assert result.episodes_total == 1
    end

    test "completed progress returns completed 1" do
      entity = build_entity(%{type: :movie, name: "Done Movie"})

      progress = [
        build_progress(%{
          position_seconds: 7000.0,
          duration_seconds: 7200.0,
          completed: true
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.episodes_completed == 1
      assert result.episodes_total == 1
    end
  end

  describe "TVSeries" do
    test "no progress on episodes returns current_episode as first, position 0" do
      {entity, episode_ids} = build_tv_entity_with_episodes()

      # A progress record exists but is not completed, for S01E01
      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          position_seconds: 0.0,
          duration_seconds: 2400.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 1}
      assert result.episode_position_seconds == 0.0
      assert result.episodes_completed == 0
      assert result.episodes_total == 3
    end

    test "partial progress on E02 makes current E02" do
      {entity, episode_ids} = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          position_seconds: 2400.0,
          duration_seconds: 2400.0,
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 1),
          position_seconds: 600.0,
          duration_seconds: 2400.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 2}
      assert result.episode_position_seconds == 600.0
      assert result.episodes_completed == 1
    end

    test "completed E01 advances to E02" do
      {entity, episode_ids} = build_tv_entity_with_episodes()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          position_seconds: 2400.0,
          duration_seconds: 2400.0,
          completed: true,
          last_watched_at: DateTime.utc_now()
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 2}
      assert result.episode_position_seconds == 0.0
      assert result.episodes_completed == 1
    end

    test "all completed stays on last episode" do
      {entity, episode_ids} = build_tv_entity_with_episodes()

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

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 3}
      assert result.episodes_completed == 3
      assert result.episodes_total == 3
    end

    test "episodes without content_url are skipped from total" do
      episode_a = build_episode(%{episode_number: 1, name: "E1", content_url: "/ep1.mkv"})
      episode_b = build_episode(%{episode_number: 2, name: "E2", content_url: nil})
      episode_c = build_episode(%{episode_number: 3, name: "E3", content_url: "/ep3.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode_a, episode_b, episode_c]})

      entity =
        build_entity(%{
          type: :tv_series,
          name: "Partial Show",
          seasons: [season]
        })

      progress = [
        build_progress(%{
          episode_id: episode_a.id,
          position_seconds: 0.0,
          duration_seconds: 2400.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      # Only 2 episodes have content_url
      assert result.episodes_total == 2
    end
  end

  describe "find_current_item resume precedence (TVSeries)" do
    # These cases cover the non-obvious edges of "where does Continue
    # Watching resume?" — orphaned FKs, non-monotonic completion order,
    # and competing partial vs. completed records. Each test pins one
    # rule that would otherwise have to be re-discovered by reading
    # `find_current_item/2` and `advance_from/3`.

    test "progress FK that matches no available item → first unwatched item, nil progress" do
      # Episode was deleted (or never made it into the items list) but
      # the WatchProgress row survives. Resume must not crash and must
      # not credit the orphan — it falls through to the first unwatched
      # item in the series.
      {entity, _episode_ids} = build_tv_entity_with_episodes()

      progress = [
        build_progress(%{
          episode_id: 999_999,
          position_seconds: 600.0,
          duration_seconds: 2400.0,
          completed: false,
          last_watched_at: DateTime.utc_now()
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 1}
      assert result.episode_position_seconds == 0.0
      assert result.episode_duration_seconds == 0.0
    end

    test "orphan FK is completed → first unwatched item, nil progress" do
      # Same as above but the orphaned record is `completed: true`. The
      # "advance from current" path can't find an index, so it falls
      # back to first-unwatched; the orphan's position is discarded.
      {entity, _episode_ids} = build_tv_entity_with_episodes()

      progress = [
        build_progress(%{
          episode_id: 999_999,
          position_seconds: 2400.0,
          duration_seconds: 2400.0,
          completed: true,
          last_watched_at: DateTime.utc_now()
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 1}
      assert result.episode_position_seconds == 0.0
    end

    test "non-monotonic completion: most recent completed is mid-series → advances from THERE, not from end" do
      # User watched E03, then went back and watched E01. Most recent
      # completed = E01. Resume must advance to E02 (the item AFTER
      # the most-recent record), not to "the first unwatched" (E02
      # would be the same here, but the rule is about following
      # advance-from-most-recent, not scanning for unwatched).
      {entity, episode_ids} = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 2),
          completed: true,
          last_watched_at: DateTime.add(now, -120, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 2}
    end

    test "most recent completed mid-series, next item also completed → still advances (does not skip)" do
      # User watched E01, E02, E03 in order and the most recent record
      # is E02 (e.g., they re-watched it). advance_from(E02) lands on
      # E03 — even though E03 is already completed. The rule is "next
      # item in the list after the most recent record", not "next
      # unwatched item". This pins the surprising behaviour so a future
      # refactor doesn't silently change it.
      {entity, episode_ids} = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -180, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 2),
          completed: true,
          position_seconds: 2400.0,
          duration_seconds: 2400.0,
          last_watched_at: DateTime.add(now, -120, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 1),
          completed: true,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 3}
    end

    test "most recent is partial, even with older completed records → resumes the partial" do
      # An older completed E01 plus a newer partial E02 → resume E02
      # at its position. The "most recent record" wins regardless of
      # completion state.
      {entity, episode_ids} = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -3600, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 1),
          position_seconds: 800.0,
          duration_seconds: 2400.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 2}
      assert result.episode_position_seconds == 800.0
    end

    test "sparse progress: completed E01, completely unwatched E02, partial E03 → resumes E03" do
      # Non-contiguous viewing pattern (skipped E02, started E03). The
      # most-recent rule resumes E03 at its position; we do not try to
      # nag the user about the unwatched gap.
      {entity, episode_ids} = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          episode_id: Enum.at(episode_ids, 0),
          completed: true,
          last_watched_at: DateTime.add(now, -3600, :second)
        }),
        build_progress(%{
          episode_id: Enum.at(episode_ids, 2),
          position_seconds: 1200.0,
          duration_seconds: 2400.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 3}
      assert result.episode_position_seconds == 1200.0
    end
  end

  describe "find_current_item resume precedence (MovieSeries)" do
    test "progress FK that matches no available movie → first unwatched movie, nil progress" do
      # Same orphan-FK scenario for movie series — e.g. a movie was
      # delisted from the collection but its progress row remained.
      {entity, _movie_ids} = build_movie_series_entity()

      progress = [
        build_progress(%{
          movie_id: 999_999,
          position_seconds: 1000.0,
          duration_seconds: 7200.0,
          completed: false,
          last_watched_at: DateTime.utc_now()
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 0, episode: 1}
      assert result.episode_position_seconds == 0.0
      assert result.episodes_completed == 0
    end

    test "non-monotonic completion in movie series advances from most-recent, not from end" do
      # Watched M3 first, then M1. Most recent = M1 → advances to M2.
      {entity, movie_ids} = build_movie_series_entity()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 2),
          completed: true,
          last_watched_at: DateTime.add(now, -120, :second)
        }),
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          completed: true,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 0, episode: 2}
    end
  end

  describe "MovieSeries" do
    test "per-movie progress tracks total and completed" do
      {entity, movie_ids} = build_movie_series_entity()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          position_seconds: 7000.0,
          duration_seconds: 7200.0,
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          movie_id: Enum.at(movie_ids, 1),
          position_seconds: 1200.0,
          duration_seconds: 6000.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.episodes_total == 3
      assert result.episodes_completed == 1
      assert result.current_episode == %{season: 0, episode: 2}
      assert result.episode_position_seconds == 1200.0
      assert result.episode_duration_seconds == 6000.0
    end

    test "all movies completed stays on last" do
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

      result = ProgressSummary.compute(entity, progress)

      assert result.episodes_completed == 3
      assert result.episodes_total == 3
      assert result.current_episode == %{season: 0, episode: 3}
    end

    test "no progress on movies returns first as current" do
      {entity, movie_ids} = build_movie_series_entity()

      progress = [
        build_progress(%{
          movie_id: Enum.at(movie_ids, 0),
          position_seconds: 0.0,
          duration_seconds: 7200.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 0, episode: 1}
      assert result.episode_position_seconds == 0.0
      assert result.episodes_completed == 0
      assert result.episodes_total == 3
    end

    test "movies without content_url are excluded from total" do
      movie_a = build_movie(%{content_url: "/m1.mkv", position: 0})
      movie_b = build_movie(%{content_url: nil, position: 1})
      movie_c = build_movie(%{content_url: "/m3.mkv", position: 2})

      entity =
        build_entity(%{
          type: :movie_series,
          name: "Partial Collection",
          movies: [movie_a, movie_b, movie_c]
        })

      progress = [
        build_progress(%{
          movie_id: movie_a.id,
          position_seconds: 0.0,
          duration_seconds: 7200.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.episodes_total == 2
    end
  end

  # Builds a TV entity with 3 episodes, all with content_url set.
  # Returns {entity, [episode_id_1, episode_id_2, episode_id_3]}.
  defp build_tv_entity_with_episodes do
    episode_a = build_episode(%{episode_number: 1, name: "Pilot", content_url: "/s01e01.mkv"})
    episode_b = build_episode(%{episode_number: 2, name: "Second", content_url: "/s01e02.mkv"})
    episode_c = build_episode(%{episode_number: 3, name: "Third", content_url: "/s01e03.mkv"})
    season = build_season(%{season_number: 1, episodes: [episode_a, episode_b, episode_c]})

    entity =
      build_entity(%{
        type: :tv_series,
        name: "Test Show",
        seasons: [season]
      })

    {entity, [episode_a.id, episode_b.id, episode_c.id]}
  end

  # Builds a MovieSeries entity with 3 movies, all with content_url set.
  # Returns {entity, [movie_id_1, movie_id_2, movie_id_3]}.
  defp build_movie_series_entity do
    movie_a = build_movie(%{name: "First", content_url: "/m1.mkv", position: 0})
    movie_b = build_movie(%{name: "Second", content_url: "/m2.mkv", position: 1})
    movie_c = build_movie(%{name: "Third", content_url: "/m3.mkv", position: 2})

    entity =
      build_entity(%{
        type: :movie_series,
        name: "Test Collection",
        movies: [movie_a, movie_b, movie_c]
      })

    {entity, [movie_a.id, movie_b.id, movie_c.id]}
  end
end
