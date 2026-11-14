defmodule MediaCentaur.Library.HomeFeedTest do
  @moduledoc """
  Continue Watching membership and its bar, read from title progress
  (design of 2026-11-14): a TV series is on the shelf while its title
  progress is in progress; a movie or video while its row has a viewing
  that counts.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{Deletion, ProgressRecords}
  alias MediaCentaur.Profiles.Actor

  # A series named `name` with one season of `count` episodes, each with a file.
  defp seed_series(name, count) do
    series = create_tv_series(%{name: name})
    season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

    episodes =
      for number <- 1..count do
        create_episode(%{
          season_id: season.id,
          episode_number: number,
          name: "Episode #{number}",
          content_url: "/media/test/#{name}-s01e#{number}.mkv"
        })
      end

    {series, episodes}
  end

  defp mark_watched(profile_id, episode),
    do: create_watch_progress(%{profile_id: profile_id, episode_id: episode.id, completed: true})

  # Playback finished `episode`: the mark, and the series watch position at it.
  defp finish(profile_id, episode, finished_at \\ DateTime.utc_now(:second)) do
    row = mark_watched(profile_id, episode)

    create_series_watch_position(%{
      profile_id: profile_id,
      playable_item_id: row.playable_item_id,
      finished_at: finished_at
    })
  end

  defp shelf_ids(profile_id, opts \\ []),
    do: profile_id |> Library.list_in_progress(opts) |> Enum.map(& &1.entity_id)

  describe "a TV series" do
    test "a fully watched series with its position mid-set is on Continue Watching" do
      profile_id = owner_profile_id()
      {series, [first, second, third]} = seed_series("Sample Show", 3)
      mark_watched(profile_id, second)
      mark_watched(profile_id, third)
      finish(profile_id, first)

      assert [row] = Library.list_in_progress(profile_id)
      assert row.entity_id == series.id
      assert row.progress_pct == 33
    end

    test "a series with its position at the final episode is not" do
      profile_id = owner_profile_id()
      {_series, [first, second, third]} = seed_series("Sample Show", 3)
      mark_watched(profile_id, first)
      mark_watched(profile_id, second)
      finish(profile_id, third)

      assert Library.list_in_progress(profile_id) == []
    end

    test "a skipped episode does not keep a series on the shelf once the position reaches the final one" do
      profile_id = owner_profile_id()
      {_series, [_first, second]} = seed_series("Sample Show", 2)
      finish(profile_id, second)

      assert Library.list_in_progress(profile_id) == []
    end

    test "a series whose finished episodes were all deleted is" do
      profile_id = owner_profile_id()
      {series, [_first, second, _third, _fourth]} = seed_series("Sample Show", 4)
      finish(profile_id, second, ~U[2026-05-14 20:00:00Z])

      Deletion.cleanup_removed_files(for number <- 1..2, do: "/media/test/Sample Show-s01e#{number}.mkv")

      assert [row] = Library.list_in_progress(profile_id)
      assert row.entity_id == series.id
      assert row.progress_pct == 0
      assert row.last_watched_at == ~U[2026-05-14 20:00:00Z]
    end

    test "a series marked by hand, no row carrying a time, is on the shelf after every dated title" do
      profile = create_profile(%{name: "Ana"})
      {marked, [first, _second]} = seed_series("Marked Show", 2)

      {:ok, %{last_watched_at: nil}} =
        ProgressRecords.toggle_watched(Actor.new(profile.id), :episode, first.id)

      {watched, [watched_first, _watched_second]} = seed_series("Watched Show", 2)
      finish(profile.id, watched_first, ~U[2020-01-01 00:00:00Z])

      assert [dated, undated] = Library.list_in_progress(profile.id)
      assert dated.entity_id == watched.id
      assert undated.entity_id == marked.id
      assert undated.last_watched_at == nil
      assert undated.progress_pct == 50
    end

    test "another profile's position does not put a series on this profile's shelf" do
      other = create_profile(%{name: "Ana"})
      {_series, [first, _second]} = seed_series("Sample Show", 2)
      finish(other.id, first)

      assert Library.list_in_progress(owner_profile_id()) == []
    end

    test "finished series, however many were watched more recently, do not keep an unfinished one off the shelf" do
      profile_id = owner_profile_id()
      now = DateTime.utc_now(:second)

      for index <- 1..8 do
        {_series, [only]} = seed_series("Finished Show #{index}", 1)
        finish(profile_id, only, DateTime.add(now, -index, :minute))
      end

      {unfinished, [first, _second]} = seed_series("Sample Show", 2)
      finish(profile_id, first, DateTime.add(now, -60, :minute))

      assert shelf_ids(profile_id, limit: 2) == [unfinished.id]
    end
  end

  describe "a movie or video" do
    test "a watched movie being replayed is; a movie with a 30-second viewing is not" do
      profile_id = owner_profile_id()
      replayed = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})
      clicked = create_standalone_movie(%{name: "Movie B", content_url: "/media/test/movie-b.mkv"})

      create_watch_progress(%{
        movie_id: replayed.id,
        completed: true,
        position_seconds: 600.0,
        duration_seconds: 6000.0
      })

      create_watch_progress(%{movie_id: clicked.id, position_seconds: 30.0, duration_seconds: 6000.0})

      assert [row] = Library.list_in_progress(profile_id)
      assert row.entity_id == replayed.id
      assert row.progress_pct == 10
    end

    test "a video with a viewing that counts is; one with a shorter viewing is not" do
      profile_id = owner_profile_id()
      viewed = create_video_object(%{name: "Sample Video", content_url: "/media/test/video-a.mkv"})
      clicked = create_video_object(%{name: "Other Video", content_url: "/media/test/video-b.mkv"})

      create_watch_progress(%{
        video_object_id: viewed.id,
        position_seconds: 60.0,
        duration_seconds: 600.0
      })

      create_watch_progress(%{
        video_object_id: clicked.id,
        position_seconds: 59.0,
        duration_seconds: 600.0
      })

      assert shelf_ids(profile_id) == [viewed.id]
    end

    test "a viewing whose row carries no time sorts after a dated one" do
      profile_id = owner_profile_id()
      undated = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})
      dated = create_standalone_movie(%{name: "Movie B", content_url: "/media/test/movie-b.mkv"})

      undated_row =
        create_watch_progress(%{movie_id: undated.id, position_seconds: 600.0, duration_seconds: 6000.0})

      force_attrs(undated_row, last_watched_at: nil)
      create_watch_progress(%{movie_id: dated.id, position_seconds: 600.0, duration_seconds: 6000.0})

      assert shelf_ids(profile_id) == [dated.id, undated.id]
    end
  end
end
