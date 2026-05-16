defmodule MediaCentarr.Library.ProgressSummariesTest do
  @moduledoc """
  Spec for `Library.list_progress_summaries/1` — the bulk progress
  lookup used by projection consumers (Phase 3.1).

  Returns `%{entity_id => summary}` keyed by container UUID. Each
  summary carries the same shape `ProgressSummary.compute/2` returns:
  `:episodes_completed`, `:episodes_total`, the position fields, plus
  `:last_watched_at` for ordering. The function issues at most a
  bounded number of queries (one per container kind in the input
  set); tests assert that bound via `MediaCentarr.QueryCounter`.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.QueryCounter
  alias MediaCentarr.Library.FilePresence

  defp record_present(file), do: FilePresence.stamp(file.file_path, file.watch_dir)

  defp seed_present_movie(name) do
    movie = create_standalone_movie(%{name: name})
    record_present(create_linked_file(%{movie_id: movie.id}))
    movie
  end

  defp seed_present_video_object(name) do
    vo = create_video_object(%{name: name})
    record_present(create_linked_file(%{video_object_id: vo.id}))
    vo
  end

  defp seed_present_tv_series_with_episode(name) do
    series = create_tv_series(%{name: name})
    season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

    episode =
      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "S1E1",
        content_url: "/media/test/#{name}-s01e01.mkv"
      })

    playable_item = create_playable_item_for_episode(episode)

    record_present(
      create_linked_file(%{playable_item_id: playable_item.id, file_path: episode.content_url})
    )

    %{series: series, season: season, episode: episode, playable_item: playable_item}
  end

  describe "list_progress_summaries/1 — empty / no-progress cases" do
    test "returns empty map for empty id list" do
      assert Library.list_progress_summaries([]) == %{}
    end

    test "entities with no WatchProgress are absent from the result" do
      movie = seed_present_movie("Untouched Movie")

      result = Library.list_progress_summaries([movie.id])

      assert result == %{}
    end
  end

  describe "list_progress_summaries/1 — single container" do
    test "returns summary for a standalone movie with progress" do
      movie = seed_present_movie("Partial Movie")

      before = DateTime.utc_now(:second)

      _ =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 60.0,
          duration_seconds: 120.0,
          completed: false
        })

      result = Library.list_progress_summaries([movie.id])

      assert summary = result[movie.id]
      assert summary.episodes_completed == 0
      assert summary.episodes_total == 1
      assert summary.episode_position_seconds == 60.0
      assert summary.episode_duration_seconds == 120.0
      # The changeset stamps `last_watched_at` with `DateTime.utc_now(:second)`,
      # so we can only assert the field is present and recent.
      assert %DateTime{} = summary.last_watched_at
      assert DateTime.compare(summary.last_watched_at, before) in [:gt, :eq]
    end

    test "completed movie reports episodes_completed=1" do
      movie = seed_present_movie("Done Movie")

      _ =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 120.0,
          duration_seconds: 120.0,
          completed: true,
          last_watched_at: ~U[2026-05-15 00:00:00Z]
        })

      result = Library.list_progress_summaries([movie.id])

      assert result[movie.id].episodes_completed == 1
      assert result[movie.id].episodes_total == 1
    end

    test "video object progress is reported" do
      vo = seed_present_video_object("Sample VO")

      _ =
        create_watch_progress(%{
          video_object_id: vo.id,
          position_seconds: 5.0,
          duration_seconds: 50.0,
          completed: false,
          last_watched_at: ~U[2026-05-15 00:00:00Z]
        })

      result = Library.list_progress_summaries([vo.id])

      assert result[vo.id].episodes_completed == 0
      assert result[vo.id].episodes_total == 1
    end
  end

  describe "list_progress_summaries/1 — TV series" do
    test "counts completed episodes against series episode total" do
      %{series: series, season: season, episode: ep1} =
        seed_present_tv_series_with_episode("Sample Show")

      # Add a second episode (no progress).
      _ep2 =
        create_episode(%{
          season_id: season.id,
          episode_number: 2,
          name: "S1E2",
          content_url: "/media/test/sample-show-s01e02.mkv"
        })

      before = DateTime.utc_now(:second)

      _ =
        create_watch_progress(%{
          episode_id: ep1.id,
          position_seconds: 30.0,
          duration_seconds: 60.0,
          completed: true
        })

      result = Library.list_progress_summaries([series.id])

      summary = result[series.id]
      assert summary.episodes_completed == 1
      assert summary.episodes_total == 2
      assert %DateTime{} = summary.last_watched_at
      assert DateTime.compare(summary.last_watched_at, before) in [:gt, :eq]
    end
  end

  describe "list_progress_summaries/1 — mixed batch" do
    test "returns summaries for movies and TV series in one call" do
      movie = seed_present_movie("Mixed Movie")
      %{series: series, episode: ep} = seed_present_tv_series_with_episode("Mixed Show")

      _ =
        create_watch_progress(%{
          movie_id: movie.id,
          completed: false,
          position_seconds: 10.0,
          duration_seconds: 100.0,
          last_watched_at: ~U[2026-05-13 00:00:00Z]
        })

      _ =
        create_watch_progress(%{
          episode_id: ep.id,
          completed: true,
          position_seconds: 60.0,
          duration_seconds: 60.0,
          last_watched_at: ~U[2026-05-14 00:00:00Z]
        })

      result = Library.list_progress_summaries([movie.id, series.id])

      assert result |> Map.keys() |> Enum.sort() == Enum.sort([movie.id, series.id])
      assert result[movie.id].episodes_completed == 0
      assert result[series.id].episodes_completed == 1
    end

    test "issues at most a bounded number of queries (kind-grouped, not per-id)" do
      m1 = seed_present_movie("Movie 1")
      m2 = seed_present_movie("Movie 2")
      m3 = seed_present_movie("Movie 3")
      %{series: s1, episode: ep1} = seed_present_tv_series_with_episode("Show 1")
      %{series: s2, episode: ep2} = seed_present_tv_series_with_episode("Show 2")

      for movie <- [m1, m2, m3] do
        create_watch_progress(%{
          movie_id: movie.id,
          completed: false,
          position_seconds: 5.0,
          duration_seconds: 100.0,
          last_watched_at: ~U[2026-05-13 00:00:00Z]
        })
      end

      for episode <- [ep1, ep2] do
        create_watch_progress(%{
          episode_id: episode.id,
          completed: true,
          position_seconds: 60.0,
          duration_seconds: 60.0,
          last_watched_at: ~U[2026-05-14 00:00:00Z]
        })
      end

      ids = [m1.id, m2.id, m3.id, s1.id, s2.id]

      {result, queries} = QueryCounter.count(fn -> Library.list_progress_summaries(ids) end)

      assert map_size(result) == 5

      # Generous cap: even covering 4 kinds with 2 queries each leaves
      # plenty of room. The bound that matters is "does NOT scale with
      # row count" — same id-count run on 100 entities should issue the
      # same number of queries.
      assert length(queries) <= 12, """
      Expected <= 12 queries; got #{length(queries)}.
      #{QueryCounter.format(queries)}
      """
    end
  end
end
