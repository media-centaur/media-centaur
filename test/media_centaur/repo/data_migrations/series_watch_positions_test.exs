defmodule MediaCentaur.Repo.DataMigrations.SeriesWatchPositionsTest do
  @moduledoc """
  The upgrade to recorded series watch positions. Each test builds the rows
  the previous version left — a completed row still carrying its offset, a
  replay that cleared the mark — which today's writers refuse to produce,
  so they are forced through the factory.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.EpisodeOrder
  alias MediaCentaur.Library.MovieOrder
  alias MediaCentaur.Library.ProgressRecords
  alias MediaCentaur.Library.SeriesWatchPosition
  alias MediaCentaur.Library.SeriesWatchPositions
  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaur.Library.WatchProgress
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.SeriesWatchPositions, as: Migration

  @day ~U[2026-03-01 20:00:00Z]

  setup do
    %{profile: create_profile(%{name: "Ana"})}
  end

  # A series of `count` episodes in one season, each with a file.
  defp create_series(name, count) do
    series = create_tv_series(%{name: name})
    season = create_season(%{tv_series_id: series.id, season_number: 1})

    episodes =
      for number <- 1..count do
        create_episode(%{
          season_id: season.id,
          episode_number: number,
          name: "Episode #{number}",
          content_url: "/media/test/#{series.id}/S01E#{number}.mkv"
        })
      end

    {series, season, episodes}
  end

  # The row the previous version left when playback finished an episode:
  # marked, still at its end offset, last touched `hours` after `@day`.
  defp finished(profile, episode, hours) do
    %{profile_id: profile.id, episode_id: episode.id, completed: true}
    |> Map.merge(%{position_seconds: 1289.0, duration_seconds: 1300.0})
    |> create_watch_progress()
    |> backdate(:last_watched_at, DateTime.add(@day, hours, :hour))
  end

  # The row the previous version left when a watched item was started
  # again: the mark cleared, the offset of the replay.
  defp unmarked_viewing(profile, container, position_seconds, hours) do
    container
    |> Map.merge(%{profile_id: profile.id, position_seconds: position_seconds, duration_seconds: 1300.0})
    |> create_watch_progress()
    |> backdate(:last_watched_at, DateTime.add(@day, hours, :hour))
  end

  defp episode_key(episode), do: EpisodeOrder.order_key(1, episode.episode_number)

  defp position_key(profile, series) do
    case SeriesWatchPositions.get(profile.id, series.id) do
      nil -> nil
      position -> position.order_key
    end
  end

  # The item Play offers after the upgrade, read the way the app reads it.
  defp title_progress(profile, series, episodes) do
    TitleProgress.compute(
      Enum.map(episodes, &%{id: &1.id, key: episode_key(&1)}),
      SeriesWatchPositions.get(profile.id, series.id),
      ProgressRecords.list_for_container(profile.id, :tv_series, series.id)
    )
  end

  defp snapshot do
    %{
      progress: Repo.all(from(progress in WatchProgress, order_by: progress.id)),
      positions: Repo.all(from(position in SeriesWatchPosition, order_by: position.id))
    }
  end

  describe "backfill/1 — the series watch position" do
    test "a series watched in order to the middle: the position is the newest finished episode",
         %{profile: profile} do
      {series, _season, [first, second, third, _fourth] = episodes} = create_series("Sample Show", 4)
      finished(profile, first, 1)
      finished(profile, second, 2)

      assert :ok = Migration.backfill(Repo)

      position = SeriesWatchPositions.get(profile.id, series.id)
      assert position.series_type == :tv_series
      assert position.order_key == episode_key(second)
      assert position.finished_at == DateTime.add(@day, 2, :hour)

      assert %{state: :in_progress, next: %{item_id: next_id, offset_seconds: +0.0}} =
               title_progress(profile, series, episodes)

      assert next_id == third.id
    end

    test "a rewatch — every episode finished, the newest early in the series: Play continues after it",
         %{profile: profile} do
      {series, _season, [first, second, third] = episodes} = create_series("Sample Show", 3)
      finished(profile, first, 1)
      finished(profile, third, 3)
      finished(profile, second, 50)

      Migration.backfill(Repo)

      assert position_key(profile, series) == episode_key(second)

      assert %{state: :in_progress, next: %{item_id: next_id}} =
               title_progress(profile, series, episodes)

      assert next_id == third.id
    end

    test "every episode finished and the final one newest: the series is complete", %{profile: profile} do
      {series, _season, [first, second, third] = episodes} = create_series("Sample Show", 3)
      finished(profile, first, 1)
      finished(profile, second, 2)
      finished(profile, third, 3)

      Migration.backfill(Repo)

      assert position_key(profile, series) == episode_key(third)
      assert %{state: :complete, next: nil} = title_progress(profile, series, episodes)
    end

    test "an earlier episode replayed in full while later ones wait: Play stays on the first episode without a row",
         %{profile: profile} do
      {series, _season, [first, second, third, fourth] = episodes} = create_series("Sample Show", 4)
      finished(profile, second, 2)
      finished(profile, third, 3)
      finished(profile, first, 50)

      Migration.backfill(Repo)

      assert position_key(profile, series) == episode_key(third)
      assert %{next: %{item_id: next_id}} = title_progress(profile, series, episodes)
      assert next_id == fourth.id
    end

    test "a gap — an episode with no row whose successors are finished: Play stays on the gap",
         %{profile: profile} do
      {series, _season, [first, second, third, fourth] = episodes} = create_series("Sample Show", 4)
      finished(profile, first, 1)
      finished(profile, fourth, 4)
      finished(profile, third, 50)

      Migration.backfill(Repo)

      assert position_key(profile, series) == episode_key(first)
      assert %{next: %{item_id: next_id}} = title_progress(profile, series, episodes)
      assert next_id == second.id
    end

    test "the gap is the first episode: no position, and Play offers the first episode", %{
      profile: profile
    } do
      {series, _season, [first, second, third] = episodes} = create_series("Sample Show", 3)
      finished(profile, third, 3)
      finished(profile, second, 50)

      Migration.backfill(Repo)

      assert position_key(profile, series) == nil

      assert %{state: :in_progress, next: %{item_id: next_id}} =
               title_progress(profile, series, episodes)

      assert next_id == first.id
    end

    test "the newest finished episode is followed by one with no row: the position is that episode",
         %{profile: profile} do
      {series, _season, [first, second] = episodes} = create_series("Sample Show", 2)
      finished(profile, first, 1)

      Migration.backfill(Repo)

      assert position_key(profile, series) == episode_key(first)
      assert %{next: %{item_id: next_id}} = title_progress(profile, series, episodes)
      assert next_id == second.id
    end

    test "episodes marked in the same second resolve to the later one", %{profile: profile} do
      {series, _season, [first, second, third, _fourth]} = create_series("Sample Show", 4)
      for episode <- [second, third, first], do: finished(profile, episode, 1)

      Migration.backfill(Repo)

      assert position_key(profile, series) == episode_key(third)
    end

    test "an episode without a file is not a gap", %{profile: profile} do
      {series, season, [first, second]} = create_series("Sample Show", 2)
      create_episode(%{season_id: season.id, episode_number: 3, name: "Episode 3"})
      finished(profile, second, 2)
      finished(profile, first, 50)

      Migration.backfill(Repo)

      # Every episode with a file is finished, so this is a rewatch from
      # the first episode — not a walk back to "the episode before 3".
      assert position_key(profile, series) == episode_key(first)
    end

    test "a series with only an unfinished viewing gets no position, and Play resumes the viewing",
         %{profile: profile} do
      {series, _season, [first, _second] = episodes} = create_series("Sample Show", 2)
      unmarked_viewing(profile, %{episode_id: first.id}, 620.0, 1)

      Migration.backfill(Repo)

      assert position_key(profile, series) == nil

      assert %{next: %{item_id: next_id, offset_seconds: 620.0}} =
               title_progress(profile, series, episodes)

      assert next_id == first.id
    end

    test "a standalone movie gets no position", %{profile: profile} do
      movie = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})

      create_watch_progress(%{
        profile_id: profile.id,
        movie_id: movie.id,
        completed: true,
        position_seconds: 5300.0
      })

      Migration.backfill(Repo)

      assert Repo.all(SeriesWatchPosition) == []
    end

    test "two profiles each get their own position", %{profile: ana} do
      ben = create_profile(%{name: "Ben"})
      {series, _season, [first, second, third]} = create_series("Sample Show", 3)
      finished(ana, first, 1)
      finished(ben, first, 1)
      finished(ben, second, 2)
      create_profile(%{name: "Cleo"})

      Migration.backfill(Repo)

      assert position_key(ana, series) == episode_key(first)
      assert position_key(ben, series) == episode_key(second)
      assert length(Repo.all(SeriesWatchPosition)) == 2
      refute position_key(ben, series) == episode_key(third)
    end

    test "a collection's position is keyed by release date and collection position", %{profile: profile} do
      collection = create_movie_series(%{name: "Sample Collection"})

      [earlier, later, undated] =
        for {name, date, position} <- [
              {"Movie A", ~D[1999-03-31], 2},
              {"Movie B", ~D[2003-05-15], 1},
              {"Movie C", nil, 3}
            ] do
          create_movie(%{
            name: name,
            movie_series_id: collection.id,
            date_published: date,
            position: position,
            content_url: "/media/test/#{collection.id}/#{name}.mkv"
          })
        end

      for {movie, hours} <- [{undated, 1}, {earlier, 2}] do
        %{profile_id: profile.id, movie_id: movie.id, completed: true, position_seconds: 5300.0}
        |> create_watch_progress()
        |> backdate(:last_watched_at, DateTime.add(@day, hours, :hour))
      end

      Migration.backfill(Repo)

      position = SeriesWatchPositions.get(profile.id, collection.id)
      assert position.series_type == :movie_series
      assert position.order_key == ["1999-03-31", "00002"]
      assert position.order_key == MovieOrder.order_key(earlier)

      # Story order is undated, earlier, later: the next movie is the later one.
      ordered_set = Enum.map([undated, earlier, later], &%{id: &1.id, key: MovieOrder.order_key(&1)})
      rows = ProgressRecords.list_for_container(profile.id, :movie_series, collection.id)
      assert %{next: %{item_id: next_id}} = TitleProgress.compute(ordered_set, position, rows)
      assert next_id == later.id
    end

    test "writes the row in the form the schema's own writer stores", %{profile: profile} do
      {series, _season, [first, _second]} = create_series("Sample Show", 2)
      {written_series, _season, [written_first]} = create_series("Sample Show 2", 1)
      progress = finished(profile, first, 1)

      # The comparison row: the same key and time, written by the real writer.
      create_series_watch_position(%{
        profile_id: profile.id,
        playable_item_id:
          create_watch_progress(%{profile_id: profile.id, episode_id: written_first.id}).playable_item_id,
        finished_at: progress.last_watched_at
      })

      Migration.backfill(Repo)

      columns = "id, profile_id, series_type, order_key, finished_at, inserted_at, updated_at"

      raw = fn series_id ->
        "SELECT #{columns} FROM library_series_watch_positions WHERE series_id = ?"
        |> Repo.query!([series_id])
        |> Map.fetch!(:rows)
        |> hd()
      end

      [id, profile_id, series_type, order_key, finished_at, inserted_at, updated_at] = raw.(series.id)

      assert [
               written_id,
               ^profile_id,
               ^series_type,
               ^order_key,
               ^finished_at,
               written_inserted_at,
               _updated_at
             ] =
               raw.(written_series.id)

      assert order_key == ~s(["00001","00001"])
      assert {:ok, ^id} = Ecto.UUID.cast(id)
      assert String.length(id) == String.length(written_id)
      assert Regex.replace(~r/\d/, inserted_at, "0") == Regex.replace(~r/\d/, written_inserted_at, "0")
      assert inserted_at == updated_at

      assert %SeriesWatchPosition{inserted_at: %DateTime{}} =
               SeriesWatchPositions.get(profile.id, series.id)
    end
  end

  describe "backfill/1 — the item rows" do
    test "a finished row loses its offset and keeps its mark, duration and last_watched_at",
         %{profile: profile} do
      {_series, _season, [first]} = create_series("Sample Show", 1)
      progress = finished(profile, first, 1)

      Migration.backfill(Repo)

      reloaded = Repo.reload!(progress)
      assert reloaded.completed
      assert reloaded.position_seconds == 0.0
      assert reloaded.duration_seconds == 1300.0
      assert reloaded.last_watched_at == progress.last_watched_at
      assert reloaded.updated_at == progress.updated_at
    end

    test "a finished extra loses its offset", %{profile: profile} do
      movie = create_standalone_movie(%{name: "Movie A"})
      extra = create_extra(%{movie_id: movie.id, name: "Featurette"})

      progress =
        %{profile_id: profile.id, extra_id: extra.id, position_seconds: 590.0, duration_seconds: 600.0}
        |> create_extra_progress()
        |> force_attrs(completed: true)

      unfinished_extra = create_extra(%{movie_id: movie.id, name: "Deleted Scene"})

      unfinished =
        create_extra_progress(%{
          profile_id: profile.id,
          extra_id: unfinished_extra.id,
          position_seconds: 90.0
        })

      Migration.backfill(Repo)

      assert %{completed: true, position_seconds: +0.0, duration_seconds: 600.0} = Repo.reload!(progress)
      assert %{completed: false, position_seconds: 90.0} = Repo.reload!(unfinished)
    end

    test "a replay that cleared the mark gets it back and keeps its offset as the viewing in flight",
         %{profile: profile} do
      {series, _season, [first, second, third] = episodes} = create_series("Sample Show", 3)
      finished(profile, first, 1)
      finished(profile, third, 3)
      replay = unmarked_viewing(profile, %{episode_id: second.id}, 620.0, 50)
      create_watch_event(%{profile_id: profile.id, entity_type: :episode, episode_id: second.id})

      Migration.backfill(Repo)

      reloaded = Repo.reload!(replay)
      assert reloaded.completed
      assert reloaded.position_seconds == 620.0
      assert reloaded.last_watched_at == replay.last_watched_at

      # Play resumed the replay before the upgrade, and still does.
      assert position_key(profile, series) == episode_key(third)

      assert %{state: :in_progress, next: %{item_id: next_id, offset_seconds: 620.0}} =
               title_progress(profile, series, episodes)

      assert next_id == second.id
    end

    test "a replayed standalone movie gets its mark back", %{profile: profile} do
      movie = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})
      replay = unmarked_viewing(profile, %{movie_id: movie.id}, 900.0, 1)
      create_watch_event(%{profile_id: profile.id, entity_type: :movie, movie_id: movie.id})

      Migration.backfill(Repo)

      assert %{completed: true, position_seconds: 900.0} = Repo.reload!(replay)
    end

    test "an unfinished viewing of an item never finished is left alone", %{profile: profile} do
      {_series, _season, [first, second]} = create_series("Sample Show", 2)
      viewing = unmarked_viewing(profile, %{episode_id: first.id}, 620.0, 1)
      create_watch_event(%{profile_id: profile.id, entity_type: :episode, episode_id: second.id})

      Migration.backfill(Repo)

      assert %{completed: false, position_seconds: 620.0} = Repo.reload!(viewing)
    end

    test "another profile's history does not restore the mark", %{profile: ana} do
      ben = create_profile(%{name: "Ben"})
      {_series, _season, [first]} = create_series("Sample Show", 1)
      viewing = unmarked_viewing(ana, %{episode_id: first.id}, 620.0, 1)
      create_watch_event(%{profile_id: ben.id, entity_type: :episode, episode_id: first.id})

      Migration.backfill(Repo)

      refute Repo.reload!(viewing).completed
    end

    test "an unmarked row with no offset is left alone even with history", %{profile: profile} do
      {_series, _season, [first]} = create_series("Sample Show", 1)
      unmarked = unmarked_viewing(profile, %{episode_id: first.id}, 0.0, 1)
      create_watch_event(%{profile_id: profile.id, entity_type: :episode, episode_id: first.id})

      Migration.backfill(Repo)

      refute Repo.reload!(unmarked).completed
    end
  end

  describe "backfill/1 — run again" do
    test "a second run changes nothing", %{profile: profile} do
      {_series, _season, [first, second, third, _fourth]} = create_series("Sample Show", 4)
      finished(profile, first, 1)
      finished(profile, third, 3)
      finished(profile, second, 50)

      unmarked_viewing(
        profile,
        %{episode_id: hd(elem(create_series("Sample Show 2", 2), 2)).id},
        620.0,
        1
      )

      movie = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})

      create_watch_progress(%{
        profile_id: profile.id,
        movie_id: movie.id,
        completed: true,
        position_seconds: 5300.0
      })

      Migration.backfill(Repo)
      after_first = snapshot()
      assert length(after_first.positions) == 1

      Migration.backfill(Repo)

      assert snapshot() == after_first
    end

    test "a second run leaves a position the first run wrote where it is, even though the rows now read differently",
         %{profile: profile} do
      {series, _season, [first, second, third]} = create_series("Sample Show", 3)
      finished(profile, first, 1)
      finished(profile, third, 3)
      unmarked_viewing(profile, %{episode_id: second.id}, 620.0, 50)
      create_watch_event(%{profile_id: profile.id, entity_type: :episode, episode_id: second.id})

      Migration.backfill(Repo)
      Migration.backfill(Repo)

      # The restored replay is now the newest marked row; the position
      # still says what the first run read.
      assert position_key(profile, series) == episode_key(third)
      assert length(Repo.all(SeriesWatchPosition)) == 1
    end
  end
end
