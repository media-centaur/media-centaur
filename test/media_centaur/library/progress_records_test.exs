defmodule MediaCentaur.Library.ProgressRecordsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.Containers
  alias MediaCentaur.Library.EntityShape
  alias MediaCentaur.Library.ProgressRecords
  alias MediaCentaur.Library.SeriesWatchPositions
  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaur.Profiles.Actor
  alias MediaCentaur.Topics

  describe "index_progress_by_key/1" do
    test "indexes by episode_id FK" do
      ep_id_a = Ecto.UUID.generate()
      ep_id_b = Ecto.UUID.generate()

      progress_a =
        build_progress(%{episode_id: ep_id_a, position_seconds: 30.0})

      progress_b =
        build_progress(%{episode_id: ep_id_b, position_seconds: 60.0})

      index = ProgressRecords.index_progress_by_key([progress_a, progress_b])

      assert index[ep_id_a] == progress_a
      assert index[ep_id_b] == progress_b
      assert map_size(index) == 2
    end
  end

  describe "index_progress_by_key/1 keys movie-series progress by movie_id" do
    test "indexes progress records by movie_id FK" do
      movie_id_a = Ecto.UUID.generate()
      movie_id_b = Ecto.UUID.generate()

      progress_a = build_progress(%{movie_id: movie_id_a, position_seconds: 30.0})
      progress_b = build_progress(%{movie_id: movie_id_b, position_seconds: 60.0})

      index = ProgressRecords.index_progress_by_key([progress_a, progress_b])

      assert index[movie_id_a] == progress_a
      assert index[movie_id_b] == progress_b
      assert map_size(index) == 2
    end
  end

  describe "progress_by_leaf/3" do
    test "one query maps each leaf container to its progress row; leaves without one are absent" do
      watched = create_standalone_movie(%{name: "Watched"})
      fresh = create_standalone_movie(%{name: "Fresh"})
      create_watch_progress(%{movie_id: watched.id, position_seconds: 30.0, duration_seconds: 100.0})

      by_id = ProgressRecords.progress_by_leaf(owner_profile_id(), :movie, [watched.id, fresh.id])

      assert %{position_seconds: 30.0} = by_id[watched.id]
      refute Map.has_key?(by_id, fresh.id)
    end
  end

  describe "two profiles" do
    setup do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      ana = create_profile(%{name: "Ana"})
      %{movie: movie, me: owner_profile_id(), ana: ana.id}
    end

    test "each profile has its own row for the same title", %{movie: movie, me: me, ana: ana} do
      movie_id = movie.id

      {:ok, mine} =
        ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{position_seconds: 10.0})

      {:ok, hers} =
        ProgressRecords.find_or_create_for_container(ana, :movie, movie.id, %{position_seconds: 90.0})

      assert mine.id != hers.id
      assert mine.playable_item_id == hers.playable_item_id
      assert {:ok, %{position_seconds: 10.0}} = ProgressRecords.fetch_for_container(me, :movie, movie.id)

      assert {:ok, %{position_seconds: 90.0}} =
               ProgressRecords.fetch_for_container(ana, :movie, movie.id)

      assert [%{position_seconds: 10.0}] = ProgressRecords.list_for_container(me, :movie, movie.id)

      assert %{^movie_id => %TitleProgress{next: %{offset_seconds: 90.0}}} =
               ProgressRecords.title_progresses(ana, [movie.id])
    end

    test "a profile without a row reads nothing", %{movie: movie, me: me, ana: ana} do
      {:ok, _} =
        ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{position_seconds: 10.0})

      assert {:error, :not_found} = ProgressRecords.fetch_for_container(ana, :movie, movie.id)
      assert ProgressRecords.list_for_container(ana, :movie, movie.id) == []
      assert ProgressRecords.title_progresses(ana, [movie.id]) == %{}
      assert ProgressRecords.profile_ids_with_progress() == [me]
    end

    test "removing a profile removes its rows and no one else's", %{movie: movie, me: me, ana: ana} do
      {:ok, _} = ProgressRecords.find_or_create_for_container(me, :movie, movie.id, %{})
      {:ok, _} = ProgressRecords.find_or_create_for_container(ana, :movie, movie.id, %{})

      :ok = MediaCentaur.Profiles.remove(MediaCentaur.Profiles.get(ana))

      assert {:ok, _} = ProgressRecords.fetch_for_container(me, :movie, movie.id)
      assert {:error, :not_found} = ProgressRecords.fetch_for_container(ana, :movie, movie.id)
    end
  end

  describe "last_played_at_by_title/2" do
    test "the newest time among a title's rows, whatever the title's progress" do
      profile = create_profile(%{name: "Ana"})

      finished = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})

      {:ok, watched} =
        ProgressRecords.seed_watched(profile.id, :movie, finished.id, 5400.0)

      backdate(watched, :last_watched_at, ~U[2026-08-03 20:00:00Z])

      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      for {number, watched_at} <- [{1, ~U[2026-08-01 20:00:00Z]}, {2, ~U[2026-08-09 20:00:00Z]}] do
        episode =
          create_episode(%{season_id: season.id, episode_number: number, name: "Episode #{number}"})

        %{profile_id: profile.id, episode_id: episode.id, position_seconds: 300.0}
        |> create_watch_progress()
        |> backdate(:last_watched_at, watched_at)
      end

      untouched = create_standalone_movie(%{name: "Movie B"})

      assert ProgressRecords.last_played_at_by_title(profile.id, [finished.id, series.id, untouched.id]) ==
               %{finished.id => ~U[2026-08-03 20:00:00Z], series.id => ~U[2026-08-09 20:00:00Z]}
    end

    test "a title only marked by hand has no time; another profile's rows are not read" do
      profile = create_profile(%{name: "Ana"})
      marked = create_standalone_movie(%{name: "Movie A"})
      theirs = create_standalone_movie(%{name: "Movie B"})

      {:ok, %{last_watched_at: nil}} =
        ProgressRecords.toggle_watched(Actor.new(profile.id), :movie, marked.id)

      create_watch_progress(%{movie_id: theirs.id, position_seconds: 300.0})

      assert ProgressRecords.last_played_at_by_title(profile.id, [marked.id, theirs.id]) == %{}
      assert ProgressRecords.last_played_at_by_title(profile.id, []) == %{}
    end
  end

  describe "viewing?/1" do
    test "a viewing counts from 60 seconds" do
      refute ProgressRecords.viewing?(nil)
      refute ProgressRecords.viewing?(%{position_seconds: 59.9})
      assert ProgressRecords.viewing?(%{position_seconds: 60.0})
    end
  end

  describe "state_from_progress/1 with a watched item being replayed" do
    test "a viewing that counts reads as current, whatever the watched mark" do
      assert ProgressRecords.state_from_progress(%{completed: true, position_seconds: 300.0}) ==
               :current

      assert ProgressRecords.state_from_progress(%{completed: true, position_seconds: 0.0}) ==
               :watched

      assert ProgressRecords.state_from_progress(%{completed: false, position_seconds: 30.0}) ==
               :unwatched
    end
  end

  describe "the watched controls" do
    setup do
      profile = create_profile(%{name: "Ana"})
      movie = create_standalone_movie(%{name: "Movie A"})
      %{profile: profile, movie: movie, actor: Actor.new(profile.id)}
    end

    test "watched_control/1 offers Mark watched for an unmarked item or one with a viewing that counts" do
      assert ProgressRecords.watched_control(nil) == :mark_watched
      assert ProgressRecords.watched_control(%{completed: false, position_seconds: 0.0}) == :mark_watched

      assert ProgressRecords.watched_control(%{completed: true, position_seconds: 600.0}) ==
               :mark_watched

      assert ProgressRecords.watched_control(%{completed: true, position_seconds: 0.0}) ==
               :mark_unwatched
    end

    test "toggling an item with no row marks it watched", context do
      assert {:ok, %{completed: true}} =
               ProgressRecords.toggle_watched(context.actor, :movie, context.movie.id)
    end

    test "marking an item with no row is not a viewing: last_watched_at stays empty and the completion is published",
         context do
      Topics.subscribe(Topics.library_watch_completed())
      actor = context.actor

      assert {:ok, marked} = ProgressRecords.toggle_watched(actor, :movie, context.movie.id)
      assert marked.completed
      assert marked.position_seconds == 0.0
      assert marked.last_watched_at == nil
      assert_receive {:entity_watch_completed, %{completed: true}, ^actor}
    end

    test "marking an extra with no row leaves last_watched_at empty", context do
      extra = create_extra(%{movie_id: context.movie.id, name: "Featurette"})

      assert {:ok, marked} =
               ProgressRecords.toggle_extra_watched(context.actor, context.movie.id, extra.id)

      assert marked.completed
      assert marked.last_watched_at == nil
    end

    test "toggling a watched item with an abandoned viewing clears the viewing and keeps the mark",
         context do
      progress =
        create_watch_progress(%{
          profile_id: context.profile.id,
          movie_id: context.movie.id,
          completed: true,
          position_seconds: 600.0
        })

      progress = backdate(progress, :last_watched_at, ~U[2026-01-01 00:00:00Z])

      assert {:ok, toggled} = ProgressRecords.toggle_watched(context.actor, :movie, context.movie.id)
      assert toggled.id == progress.id
      assert toggled.completed
      assert toggled.position_seconds == 0.0
      assert toggled.last_watched_at == ~U[2026-01-01 00:00:00Z]
    end

    test "toggling a watched item with no viewing unmarks it without stamping last_watched_at",
         context do
      progress =
        create_watch_progress(%{
          profile_id: context.profile.id,
          movie_id: context.movie.id,
          completed: true
        })

      backdate(progress, :last_watched_at, ~U[2026-01-01 00:00:00Z])

      assert {:ok, toggled} = ProgressRecords.toggle_watched(context.actor, :movie, context.movie.id)
      refute toggled.completed
      assert toggled.last_watched_at == ~U[2026-01-01 00:00:00Z]
    end

    test "marking an unwatched item with a viewing sets the mark and clears the viewing, unstamped",
         context do
      progress =
        create_watch_progress(%{
          profile_id: context.profile.id,
          movie_id: context.movie.id,
          position_seconds: 600.0
        })

      backdate(progress, :last_watched_at, ~U[2026-01-01 00:00:00Z])
      Topics.subscribe(Topics.library_watch_completed())
      actor = context.actor

      assert {:ok, toggled} = ProgressRecords.toggle_watched(actor, :movie, context.movie.id)
      assert toggled.completed
      assert toggled.position_seconds == 0.0
      assert toggled.last_watched_at == ~U[2026-01-01 00:00:00Z]
      assert_receive {:entity_watch_completed, %{completed: true}, ^actor}
    end

    test "the watched controls never move the series watch position", context do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      first = create_episode(%{season_id: season.id, episode_number: 1, name: "Episode 1"})
      second = create_episode(%{season_id: season.id, episode_number: 2, name: "Episode 2"})

      finished =
        create_watch_progress(%{profile_id: context.profile.id, episode_id: first.id, completed: true})

      create_series_watch_position(%{
        profile_id: context.profile.id,
        playable_item_id: finished.playable_item_id
      })

      {:ok, _marked} = ProgressRecords.toggle_watched(context.actor, :episode, second.id)
      {:ok, _unmarked} = ProgressRecords.toggle_watched(context.actor, :episode, first.id)

      assert SeriesWatchPositions.get(context.profile.id, series.id).order_key == ["00001", "00001"]
    end

    test "toggling an extra marks it, then unmarks it", context do
      extra = create_extra(%{movie_id: context.movie.id, name: "Featurette"})

      assert {:ok, %{completed: true}} =
               ProgressRecords.toggle_extra_watched(context.actor, context.movie.id, extra.id)

      assert {:ok, %{completed: false}} =
               ProgressRecords.toggle_extra_watched(context.actor, context.movie.id, extra.id)
    end
  end

  describe "title_progress/2" do
    defp series_with_three_marked_episodes(profile) do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      episodes =
        for number <- 1..3 do
          episode =
            create_episode(%{
              season_id: season.id,
              episode_number: number,
              name: "Episode #{number}",
              content_url: "/media/test/sample-show-#{number}.mkv"
            })

          create_watch_progress(%{profile_id: profile.id, episode_id: episode.id, completed: true})
          episode
        end

      {series, episodes}
    end

    defp entity_view(series) do
      {:ok, loaded} = Containers.fetch_with_associations(:tv_series, series.id)
      EntityShape.to_entity_view(loaded, :tv_series)
    end

    test "reads the rows and the series watch position and applies the rule" do
      profile = create_profile()
      {series, [first, second, _third]} = series_with_three_marked_episodes(profile)

      {:ok, row} = ProgressRecords.fetch_for_container(profile.id, :episode, first.id)
      create_series_watch_position(%{profile_id: profile.id, playable_item_id: row.playable_item_id})

      assert %{title_progress: progress, records: records} =
               ProgressRecords.title_progress(profile.id, entity_view(series))

      assert %TitleProgress{state: :in_progress, next: %{item_id: next_id}, before_next: 1, total: 3} =
               progress

      assert next_id == second.id
      assert length(records) == 3
    end

    test "a row marked by hand carries no timestamp and is read without one" do
      profile = create_profile()
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      [first, second] =
        for number <- 1..2 do
          create_episode(%{
            season_id: season.id,
            episode_number: number,
            name: "Episode #{number}",
            content_url: "/media/test/sample-show-#{number}.mkv"
          })
        end

      {:ok, %{last_watched_at: nil}} =
        ProgressRecords.toggle_watched(Actor.new(profile.id), :episode, first.id)

      assert %{title_progress: %TitleProgress{state: :in_progress, next: %{item_id: next_id}}} =
               ProgressRecords.title_progress(profile.id, entity_view(series))

      assert next_id == second.id
    end

    test "a standalone movie reads its one row and no series watch position" do
      profile = create_profile()
      movie = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})
      create_watch_progress(%{profile_id: profile.id, movie_id: movie.id, position_seconds: 600.0})

      {:ok, loaded} = Containers.fetch_with_associations(:movie, movie.id)
      entity = EntityShape.to_entity_view(loaded, :movie)

      assert %{title_progress: %TitleProgress{state: :in_progress, next: %{offset_seconds: 600.0}}} =
               ProgressRecords.title_progress(profile.id, entity)
    end
  end

  describe "the live offset of a session in flight" do
    alias MediaCentaur.Library.Progress

    setup do
      if Process.whereis(Progress.Worker) == nil do
        start_supervised!({Progress.Worker, [flush_interval_ms: 60_000, name: Progress.Worker]})
      end

      Progress.reset_for_test!()
      profile = create_profile(%{name: "Ana"})
      movie = create_standalone_movie(%{name: "Movie A", content_url: "/media/test/movie-a.mkv"})

      watched =
        create_watch_progress(%{profile_id: profile.id, movie_id: movie.id, completed: true})

      :ok = Progress.record(profile.id, watched.playable_item_id, 600.0, 5400.0)
      %{profile: profile, movie: movie}
    end

    test "title_progress/2 reads the records at their live offset", %{profile: profile, movie: movie} do
      {:ok, loaded} = Containers.fetch_with_associations(:movie, movie.id)
      entity = EntityShape.to_entity_view(loaded, :movie)

      assert %{title_progress: progress, records: [record]} =
               ProgressRecords.title_progress(profile.id, entity)

      assert record.position_seconds == 600.0
      assert ProgressRecords.watched_control(record) == :mark_watched
      assert %TitleProgress{next: %{offset_seconds: 600.0}} = progress
    end

    test "the watched control applied is the one the live record offers: a watched item being replayed keeps its mark",
         %{profile: profile, movie: movie} do
      assert {:ok, toggled} = ProgressRecords.toggle_watched(Actor.new(profile.id), :movie, movie.id)
      assert toggled.completed
      assert toggled.position_seconds == 0.0
    end
  end

  describe "seed_watched/4" do
    setup do
      Topics.subscribe(Topics.library_watch_completed())
      %{movie: create_standalone_movie(%{name: "Movie A"}), profile_id: owner_profile_id()}
    end

    test "writes the row a finish leaves — mark set, no viewing, duration kept — and publishes nothing",
         context do
      assert {:ok, seeded} =
               ProgressRecords.seed_watched(context.profile_id, :movie, context.movie.id, 5400.0)

      assert seeded.completed
      assert seeded.position_seconds == 0.0
      assert seeded.duration_seconds == 5400.0
      assert %DateTime{} = seeded.last_watched_at
      refute_receive {:entity_watch_completed, _record, _actor}
    end

    test "marks a row that already exists and ends its viewing", context do
      existing = create_watch_progress(%{movie_id: context.movie.id, position_seconds: 600.0})

      assert {:ok, seeded} =
               ProgressRecords.seed_watched(context.profile_id, :movie, context.movie.id, 5400.0)

      assert seeded.id == existing.id
      assert seeded.completed
      assert seeded.position_seconds == 0.0
      assert seeded.duration_seconds == 5400.0
    end
  end

  describe "finish_extra/2" do
    test "sets the mark, ends the viewing and keeps the duration" do
      movie = create_standalone_movie(%{name: "Movie A"})
      extra = create_extra(%{movie_id: movie.id, name: "Featurette"})

      progress =
        create_extra_progress(%{extra_id: extra.id, position_seconds: 590.0, duration_seconds: 600.0})

      assert {:ok, finished} = ProgressRecords.finish_extra(progress, 600.0)
      assert finished.completed
      assert finished.position_seconds == 0.0
      assert finished.duration_seconds == 600.0
    end
  end
end
