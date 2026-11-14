defmodule MediaCentaur.Library.TitleProgressRegressionTest do
  @moduledoc """
  The Play-target regression set (ADR-027), moved here when
  `MediaCentaur.Library.TitleProgress` replaced the playback module that
  derived the Play target before it.

  Same entity fixtures and test names. Each fixture is restated in the
  three facts the rule reads: a completed record is a watched mark resting
  at offset 0; where the most recently watched record was completed,
  playback finished that item, so the series watch position sits at it
  (`finished_at` is that record's `last_watched_at`); an unfinished record
  keeps its offset as the viewing in flight.

  Each expectation is restated on the value: `{:resume, url, offset}` and
  `{:play_next, url, 0.0}` are `next` at that item and offset;
  `{:restart, …}` is `:complete` (Play then starts the first item from the
  start, `Playback.Resolver`); `{:no_playable_content}` is an empty
  ordered set.

  Two expectations changed with the rule (design of 2026-11-14, "The
  rule"), each marked where it stands.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Library.{EpisodeOrder, MovieOrder, TitleProgress}

  defp movie(url) do
    %{id: Ecto.UUID.generate(), type: :movie, content_url: url, seasons: nil, movies: nil}
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

  # `ProgressRecords.list_for_container/3` synthesises `:playable_item`
  # carrying the `(container_type, container_id)` discriminator; the
  # fixtures mirror that shape.
  defp progress(opts) do
    playable_item =
      cond do
        episode_id = Keyword.get(opts, :episode_id) ->
          %{container_type: :episode, container_id: episode_id}

        movie_id = Keyword.get(opts, :movie_id) ->
          %{container_type: :movie, container_id: movie_id}
      end

    %{
      playable_item: playable_item,
      position_seconds: Keyword.get(opts, :position, 0.0),
      duration_seconds: Keyword.get(opts, :duration, 0.0),
      completed: Keyword.get(opts, :completed, false),
      last_watched_at: Keyword.get(opts, :last_watched_at, ~U[2026-01-01 00:00:00Z])
    }
  end

  # The series watch position left by playback finishing an episode.
  defp finished_episode(season_number, episode_number, finished_at),
    do: %{order_key: EpisodeOrder.order_key(season_number, episode_number), finished_at: finished_at}

  # The series watch position left by playback finishing a collection movie.
  defp finished_movie(movie, finished_at),
    do: %{order_key: MovieOrder.order_key(movie), finished_at: finished_at}

  describe "Movie" do
    test "no progress → play_next" do
      entity = movie("/videos/movie-a.mkv")

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, nil, [])

      assert item_id == entity.id
      assert offset == 0.0
    end

    test "partial progress → resume" do
      entity = movie("/videos/movie-a.mkv")
      records = [progress(movie_id: entity.id, position: 1200.5, duration: 3200.0)]

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: 1200.5}} =
               TitleProgress.for_entity(entity, nil, records)

      assert item_id == entity.id
    end

    test "completed → play_next (replay from start)" do
      entity = movie("/videos/movie-a.mkv")
      records = [progress(movie_id: entity.id, duration: 3200.0, completed: true)]

      # A single-item title with its mark set has no next: it is complete,
      # and Play replays its one item from the start.
      assert %TitleProgress{state: :complete, next: nil} =
               TitleProgress.for_entity(entity, nil, records)

      assert [%{id: first_id}] = TitleProgress.ordered_set(entity)
      assert first_id == entity.id
    end
  end

  describe "TVSeries" do
    test "no progress → play_next first episode" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      entity = tv_series([season(1, [ep1, episode(2, "/tv/show/S01E02.mkv")])])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, nil, [])

      assert item_id == ep1.id
      assert offset == 0.0
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

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: 500.0}} =
               TitleProgress.for_entity(entity, nil, records)

      assert item_id == ep1.id
    end

    test "completed mid-season → play_next episode" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      ep3 = episode(3, "/tv/show/S01E03.mkv")
      entity = tv_series([season(1, [ep1, ep2, ep3])])

      records = [
        progress(episode_id: ep1.id, completed: true, last_watched_at: ~U[2026-01-14 20:00:00Z]),
        progress(episode_id: ep2.id, completed: true, last_watched_at: ~U[2026-01-15 20:00:00Z])
      ]

      position = finished_episode(1, 2, ~U[2026-01-15 20:00:00Z])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, position, records)

      assert item_id == ep3.id
      assert offset == 0.0
    end

    test "replaying an old watched episode advances past watched territory to the first unwatched" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      ep3 = episode(3, "/tv/show/S01E03.mkv")
      ep4 = episode(4, "/tv/show/S01E04.mkv")
      entity = tv_series([season(1, [ep1, ep2, ep3, ep4])])

      # Episodes 1–3 completed; episode 1 was replayed most recently, so
      # the series watch position sits at episode 1.
      records = [
        progress(episode_id: ep1.id, completed: true, last_watched_at: ~U[2026-01-20 20:00:00Z]),
        progress(episode_id: ep2.id, completed: true, last_watched_at: ~U[2026-01-14 20:00:00Z]),
        progress(episode_id: ep3.id, completed: true, last_watched_at: ~U[2026-01-15 20:00:00Z])
      ]

      position = finished_episode(1, 1, ~U[2026-01-20 20:00:00Z])

      # CHANGED EXPECTATION (design of 2026-11-14, "The rule", consequence
      # "Play continues from whatever was finished last"): the rule of
      # e2c85f363 — skip watched territory to the first never-watched
      # episode — is retired. This asserted episode 4; Play now follows
      # the replay to episode 2.
      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: +0.0}} =
               TitleProgress.for_entity(entity, position, records)

      assert item_id == ep2.id
    end

    test "advancing onto a partially-watched episode still targets it" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      ep3 = episode(3, "/tv/show/S01E03.mkv")
      entity = tv_series([season(1, [ep1, ep2, ep3])])

      # Episode 2 has an old viewing in flight, older than the finish of
      # episode 1. It is still the next target after episode 1.
      records = [
        progress(episode_id: ep1.id, completed: true, last_watched_at: ~U[2026-01-20 20:00:00Z]),
        progress(
          episode_id: ep2.id,
          position: 300.0,
          duration: 1500.0,
          last_watched_at: ~U[2026-01-10 20:00:00Z]
        )
      ]

      position = finished_episode(1, 1, ~U[2026-01-20 20:00:00Z])

      # CHANGED EXPECTATION (design of 2026-11-14, "The rule": "Offset of
      # next: the item's viewing in flight if it counts, otherwise the
      # start"): the same target, which this asserted at 0.0; it now
      # starts at that episode's own offset.
      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: 300.0}} =
               TitleProgress.for_entity(entity, position, records)

      assert item_id == ep2.id
    end

    test "season boundary → play_next first episode of next season" do
      s1e1 = episode(1, "/tv/show/S01E01.mkv")
      s1e2 = episode(2, "/tv/show/S01E02.mkv")
      s2e1 = episode(1, "/tv/show/S02E01.mkv")
      entity = tv_series([season(1, [s1e1, s1e2]), season(2, [s2e1])])

      records = [
        progress(episode_id: s1e1.id, completed: true, last_watched_at: ~U[2026-01-14 20:00:00Z]),
        progress(episode_id: s1e2.id, completed: true, last_watched_at: ~U[2026-01-15 20:00:00Z])
      ]

      position = finished_episode(1, 2, ~U[2026-01-15 20:00:00Z])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, position, records)

      assert item_id == s2e1.id
      assert offset == 0.0
    end

    test "all episodes completed → restart from first" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      entity = tv_series([season(1, [ep1, ep2])])

      records = [
        progress(episode_id: ep1.id, completed: true, last_watched_at: ~U[2026-01-14 20:00:00Z]),
        progress(episode_id: ep2.id, completed: true, last_watched_at: ~U[2026-01-15 20:00:00Z])
      ]

      position = finished_episode(1, 2, ~U[2026-01-15 20:00:00Z])

      assert %TitleProgress{state: :complete, next: nil} =
               TitleProgress.for_entity(entity, position, records)

      assert [%{id: first_id} | _rest] = TitleProgress.ordered_set(entity)
      assert first_id == ep1.id
    end

    # From the Play button hint's tests, which named it a regression.
    test "first 4 of 8 episodes completed (regression: large remainder) → begin next" do
      episodes = for number <- 1..8, do: episode(number, "/tv/show/S01E0#{number}.mkv")
      entity = tv_series([season(1, episodes)])
      finished_at = ~U[2026-01-15 20:00:00Z]

      records =
        for {watched, seconds_before} <- Enum.zip(Enum.take(episodes, 4), [180, 120, 60, 0]) do
          progress(
            episode_id: watched.id,
            completed: true,
            last_watched_at: DateTime.add(finished_at, -seconds_before, :second)
          )
        end

      assert %TitleProgress{
               state: :in_progress,
               next: %{item_id: item_id, offset_seconds: offset},
               before_next: 4,
               total: 8
             } =
               TitleProgress.for_entity(entity, finished_episode(1, 4, finished_at), records)

      assert item_id == Enum.at(episodes, 4).id
      assert offset == 0.0
    end

    test "skip episodes missing content_url" do
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      entity = tv_series([season(1, [episode(1, nil), ep2, episode(3, "/tv/show/S01E03.mkv")])])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, nil, [])

      assert item_id == ep2.id
      assert offset == 0.0
    end
  end

  describe "MovieSeries" do
    test "no progress → play_next first movie" do
      m1 = child_movie("/movies/first.mkv", 0)
      entity = movie_series([m1, child_movie("/movies/second.mkv", 1)])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, nil, [])

      assert item_id == m1.id
      assert offset == 0.0
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

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: 1200.5}} =
               TitleProgress.for_entity(entity, nil, records)

      assert item_id == m1.id
    end

    test "completed first movie → play_next second movie" do
      m1 = child_movie("/movies/first.mkv", 0)
      m2 = child_movie("/movies/second.mkv", 1)
      m3 = child_movie("/movies/third.mkv", 2)
      entity = movie_series([m1, m2, m3])

      records = [
        progress(movie_id: m1.id, completed: true, last_watched_at: ~U[2026-01-15 20:00:00Z])
      ]

      position = finished_movie(m1, ~U[2026-01-15 20:00:00Z])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, position, records)

      assert item_id == m2.id
      assert offset == 0.0
    end

    test "all movies completed → restart from first" do
      m1 = child_movie("/movies/first.mkv", 0)
      m2 = child_movie("/movies/second.mkv", 1)
      entity = movie_series([m1, m2])

      records = [
        progress(movie_id: m1.id, completed: true, last_watched_at: ~U[2026-01-14 20:00:00Z]),
        progress(movie_id: m2.id, completed: true, last_watched_at: ~U[2026-01-15 20:00:00Z])
      ]

      position = finished_movie(m2, ~U[2026-01-15 20:00:00Z])

      assert %TitleProgress{state: :complete, next: nil} =
               TitleProgress.for_entity(entity, position, records)

      assert [%{id: first_id} | _rest] = TitleProgress.ordered_set(entity)
      assert first_id == m1.id
    end

    test "skips movies without content_url" do
      m2 = child_movie("/movies/second.mkv", 1)
      entity = movie_series([child_movie(nil, 0), m2])

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: offset}} =
               TitleProgress.for_entity(entity, nil, [])

      assert item_id == m2.id
      assert offset == 0.0
    end

    test "no movies with content_url → no_playable_content" do
      entity = movie_series([child_movie(nil, 0), child_movie(nil, 1)])

      assert %TitleProgress{total: 0, next: nil} = TitleProgress.for_entity(entity, nil, [])
    end

    test "single movie behaves like walking" do
      m1 = child_movie("/movies/solo.mkv", 0)
      entity = movie_series([m1])

      records = [progress(movie_id: m1.id, position: 600.0, duration: 3600.0)]

      assert %TitleProgress{next: %{item_id: item_id, offset_seconds: 600.0}} =
               TitleProgress.for_entity(entity, nil, records)

      assert item_id == m1.id
    end
  end

  describe "no playable content" do
    test "movie with no content_url" do
      entity = %{id: Ecto.UUID.generate(), type: :movie, content_url: nil, seasons: nil, movies: nil}
      assert %TitleProgress{total: 0, next: nil} = TitleProgress.for_entity(entity, nil, [])
    end

    test "tv series with no episodes having content_url" do
      entity = tv_series([season(1, [episode(1, nil), episode(2, nil)])])

      assert %TitleProgress{total: 0, next: nil} = TitleProgress.for_entity(entity, nil, [])
    end
  end
end
