defmodule MediaCentaur.Library.TitleProgressesTest do
  @moduledoc """
  Spec for `Library.ProgressRecords.title_progresses/2` — the bulk read
  of title progress the library grid and Continue Watching use.

  Returns `%{entity_id => TitleProgress}` keyed by container UUID, for
  every id the profile has a progress row or a series watch position
  under. The function issues a fixed number of queries whatever the
  number of titles; a test asserts that with `MediaCentaur.QueryCounter`.

  It derives a series' ordered set in SQL (file presence), where the
  single read `title_progress/2` derives it from the entity view; "the
  bulk read and the single read agree" keeps the two one definition.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.{
    Containers,
    Deletion,
    EntityShape,
    FilePresence,
    Progress,
    ProgressRecords,
    TitleProgress
  }

  alias MediaCentaur.Profiles.Actor
  alias MediaCentaur.QueryCounter

  defp record_present(file), do: FilePresence.stamp(file.file_path, file.media_dir)

  defp seed_present_movie(name) do
    movie = create_standalone_movie(%{name: name})
    record_present(create_linked_file(%{movie_id: movie.id}))
    movie
  end

  defp seed_present_video_object(name) do
    video_object = create_video_object(%{name: name})
    record_present(create_linked_file(%{video_object_id: video_object.id}))
    video_object
  end

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

    %{series: series, season: season, episodes: episodes}
  end

  defp mark_watched(profile_id, episode),
    do: create_watch_progress(%{profile_id: profile_id, episode_id: episode.id, completed: true})

  # Playback finished `episode`: the mark, and the series watch position at it.
  defp finish(profile_id, episode, finished_at \\ ~U[2026-05-14 00:00:00Z]) do
    row = mark_watched(profile_id, episode)

    create_series_watch_position(%{
      profile_id: profile_id,
      playable_item_id: row.playable_item_id,
      finished_at: finished_at
    })
  end

  defp entity_view(type, id) do
    {:ok, loaded} = Containers.fetch_with_associations(type, id)
    EntityShape.to_entity_view(loaded, type)
  end

  describe "empty and no-progress cases" do
    test "returns an empty map for an empty id list" do
      assert ProgressRecords.title_progresses(owner_profile_id(), []) == %{}
    end

    test "a title with no progress row and no series watch position is absent" do
      movie = seed_present_movie("Movie A")
      %{series: series} = seed_series("Sample Show", 2)

      assert ProgressRecords.title_progresses(owner_profile_id(), [movie.id, series.id]) == %{}
    end

    test "another profile's progress is not this profile's" do
      other = create_profile(%{name: "Ana"})
      %{series: series, episodes: [first | _rest]} = seed_series("Sample Show", 2)
      finish(other.id, first)

      assert ProgressRecords.title_progresses(owner_profile_id(), [series.id]) == %{}
    end
  end

  describe "a single-item title" do
    test "a standalone movie with a viewing that counts is in progress at its offset" do
      movie = seed_present_movie("Movie A")
      before = DateTime.utc_now(:second)

      create_watch_progress(%{movie_id: movie.id, position_seconds: 600.0, duration_seconds: 1200.0})

      assert %{} = result = ProgressRecords.title_progresses(owner_profile_id(), [movie.id])

      assert %TitleProgress{
               state: :in_progress,
               next: %{item_id: item_id, offset_seconds: 600.0, duration_seconds: 1200.0},
               before_next: 0,
               total: 1,
               last_watched_at: %DateTime{} = last_watched_at
             } = result[movie.id]

      assert item_id == movie.id
      assert DateTime.compare(last_watched_at, before) in [:gt, :eq]
      assert TitleProgress.percent(result[movie.id]) == 50
    end

    test "a watched movie is complete" do
      movie = seed_present_movie("Movie A")

      create_watch_progress(%{
        movie_id: movie.id,
        duration_seconds: 120.0,
        completed: true,
        last_watched_at: ~U[2026-05-15 00:00:00Z]
      })

      assert %TitleProgress{state: :complete, next: nil, total: 1} =
               ProgressRecords.title_progresses(owner_profile_id(), [movie.id])[movie.id]
    end

    test "a movie with a viewing under 60 seconds is unstarted" do
      movie = seed_present_movie("Movie A")
      create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 1200.0})

      assert %TitleProgress{state: :unstarted} =
               ProgressRecords.title_progresses(owner_profile_id(), [movie.id])[movie.id]
    end

    test "a video object's progress is reported" do
      video_object = seed_present_video_object("Sample Video")

      create_watch_progress(%{
        video_object_id: video_object.id,
        position_seconds: 90.0,
        duration_seconds: 900.0,
        last_watched_at: ~U[2026-05-15 00:00:00Z]
      })

      assert %TitleProgress{state: :in_progress, next: %{offset_seconds: 90.0}, total: 1} =
               ProgressRecords.title_progresses(owner_profile_id(), [video_object.id])[video_object.id]
    end
  end

  describe "a TV series" do
    test "returns each title's TitleProgress" do
      profile_id = owner_profile_id()
      %{series: series, episodes: [first, second, third]} = seed_series("Sample Show", 3)
      mark_watched(profile_id, second)
      mark_watched(profile_id, third)
      finish(profile_id, first)

      movie = seed_present_movie("Movie A")
      create_watch_progress(%{movie_id: movie.id, position_seconds: 600.0, duration_seconds: 1200.0})

      progresses = ProgressRecords.title_progresses(profile_id, [series.id, movie.id])

      assert %TitleProgress{state: :in_progress, next: %{item_id: next_id}, before_next: 1, total: 3} =
               progresses[series.id]

      assert next_id == second.id
      assert %TitleProgress{state: :in_progress, next: %{offset_seconds: 600.0}} = progresses[movie.id]
    end

    test "a series whose finished episodes were deleted still has a title progress" do
      profile_id = owner_profile_id()

      %{series: series, episodes: [_first, _second, third, fourth, _fifth]} =
        seed_series("Sample Show", 5)

      finish(profile_id, third)

      Deletion.cleanup_removed_files(for number <- 1..3, do: "/media/test/Sample Show-s01e#{number}.mkv")

      assert %TitleProgress{state: :in_progress, next: %{item_id: next_id}, before_next: 0, total: 2} =
               ProgressRecords.title_progresses(profile_id, [series.id])[series.id]

      assert next_id == fourth.id
    end

    test "episodes without files are not in the ordered set" do
      profile_id = owner_profile_id()
      %{series: series, season: season, episodes: [first]} = seed_series("Sample Show", 1)
      create_episode(%{season_id: season.id, episode_number: 2, name: "Episode 2"})
      finish(profile_id, first)

      assert %TitleProgress{state: :complete, total: 1} =
               ProgressRecords.title_progresses(profile_id, [series.id])[series.id]
    end

    test "a series marked by hand, with no timestamp on any row, is in progress with no last-watched time" do
      profile = create_profile(%{name: "Ana"})
      %{series: series, episodes: [first, second]} = seed_series("Sample Show", 2)

      {:ok, %{last_watched_at: nil}} =
        ProgressRecords.toggle_watched(Actor.new(profile.id), :episode, first.id)

      assert %TitleProgress{
               state: :in_progress,
               next: %{item_id: next_id},
               before_next: 1,
               total: 2,
               last_watched_at: nil
             } = ProgressRecords.title_progresses(profile.id, [series.id])[series.id]

      assert next_id == second.id
    end
  end

  describe "a movie collection" do
    test "absent member movies are not in the ordered set; the position decides next" do
      profile_id = owner_profile_id()
      collection = create_movie_series(%{name: "Sample Collection"})

      [part_one, part_two, _part_three] =
        for position <- 0..2 do
          create_movie(%{
            movie_series_id: collection.id,
            name: "Part #{position + 1}",
            position: position
          })
        end

      record_present(create_linked_file(%{movie_id: part_one.id}))
      record_present(create_linked_file(%{movie_id: part_two.id}))

      row = create_watch_progress(%{movie_id: part_one.id, duration_seconds: 100.0, completed: true})
      create_series_watch_position(%{profile_id: profile_id, playable_item_id: row.playable_item_id})

      assert %TitleProgress{state: :in_progress, next: %{item_id: next_id}, before_next: 1, total: 2} =
               ProgressRecords.title_progresses(profile_id, [collection.id])[collection.id]

      assert next_id == part_two.id
    end
  end

  describe "the bulk read and the single read agree" do
    test "for a fully marked series with its position mid-set" do
      profile_id = owner_profile_id()
      %{series: series, episodes: [first, second, third]} = seed_series("Sample Show", 3)
      mark_watched(profile_id, second)
      mark_watched(profile_id, third)
      finish(profile_id, first)

      %{title_progress: single} =
        ProgressRecords.title_progress(profile_id, entity_view(:tv_series, series.id))

      assert %TitleProgress{state: :in_progress, before_next: 1, total: 3} = single
      assert ProgressRecords.title_progresses(profile_id, [series.id])[series.id] == single
    end

    test "for a series with a session in flight, at the live offset" do
      if Process.whereis(Progress.Worker) == nil do
        start_supervised!({Progress.Worker, [flush_interval_ms: 60_000, name: Progress.Worker]})
      end

      Progress.reset_for_test!()

      profile_id = owner_profile_id()
      %{series: series, episodes: [first, second, third]} = seed_series("Sample Show", 3)
      mark_watched(profile_id, third)
      finish(profile_id, first)
      replayed = mark_watched(profile_id, second)
      :ok = Progress.record(profile_id, replayed.playable_item_id, 600.0, 1200.0)

      %{title_progress: single} =
        ProgressRecords.title_progress(profile_id, entity_view(:tv_series, series.id))

      assert %TitleProgress{next: %{item_id: next_id, offset_seconds: 600.0}} = single
      assert next_id == second.id
      assert ProgressRecords.title_progresses(profile_id, [series.id])[series.id] == single
    end

    test "for a standalone movie" do
      profile_id = owner_profile_id()
      movie = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})
      create_watch_progress(%{movie_id: movie.id, position_seconds: 600.0, duration_seconds: 1200.0})

      %{title_progress: single} =
        ProgressRecords.title_progress(profile_id, entity_view(:movie, movie.id))

      assert ProgressRecords.title_progresses(profile_id, [movie.id])[movie.id] == single
    end
  end

  describe "a mixed batch" do
    test "returns the progress of movies and TV series in one call" do
      profile_id = owner_profile_id()
      movie = seed_present_movie("Movie A")
      %{series: series, episodes: [episode]} = seed_series("Sample Show", 1)

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0,
        last_watched_at: ~U[2026-05-13 00:00:00Z]
      })

      finish(profile_id, episode)

      result = ProgressRecords.title_progresses(profile_id, [movie.id, series.id])

      assert result |> Map.keys() |> Enum.sort() == Enum.sort([movie.id, series.id])
      assert result[movie.id].state == :in_progress
      assert result[series.id].state == :complete
    end

    test "issues the same number of queries for one series as for many" do
      profile_id = owner_profile_id()

      [first_series | _rest] =
        series_ids =
        for number <- 1..6 do
          %{series: series, episodes: [first | _rest]} = seed_series("Sample Show #{number}", 2)
          finish(profile_id, first)
          series.id
        end

      movie_ids =
        for number <- 1..3 do
          movie = seed_present_movie("Movie #{number}")
          create_watch_progress(%{movie_id: movie.id, position_seconds: 90.0, duration_seconds: 900.0})
          movie.id
        end

      {_one, queries_for_one} =
        QueryCounter.count(fn -> ProgressRecords.title_progresses(profile_id, [first_series]) end)

      {all, queries_for_all} =
        QueryCounter.count(fn ->
          ProgressRecords.title_progresses(profile_id, series_ids ++ movie_ids)
        end)

      assert map_size(all) == 9

      assert length(queries_for_all) == length(queries_for_one), """
      Expected the query count not to grow with the number of titles.
      #{QueryCounter.format(queries_for_all)}
      """

      assert length(queries_for_all) <= 12
    end
  end
end
