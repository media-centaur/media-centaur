defmodule MediaCentaur.Library.SeriesWatchPositionsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.EntityCascade
  alias MediaCentaur.Library.SeriesWatchPositions

  setup do
    profile = create_profile()
    series = create_tv_series(%{name: "Sample Show"})
    season = create_season(%{tv_series_id: series.id, season_number: 1})
    episode = create_episode(%{season_id: season.id, episode_number: 5, name: "Episode 5"})
    progress = create_watch_progress(%{profile_id: profile.id, episode_id: episode.id})
    %{profile: profile, series: series, episode: episode, item_id: progress.playable_item_id}
  end

  test "record_finish/3 records the episode's order key against its series", context do
    now = ~U[2026-11-14 10:00:00Z]

    assert {:ok, position} =
             SeriesWatchPositions.record_finish(context.profile.id, context.item_id, now)

    assert position.series_id == context.series.id
    assert position.series_type == :tv_series
    assert position.order_key == ["00001", "00005"]
    assert position.finished_at == now
    assert SeriesWatchPositions.get(context.profile.id, context.series.id) == position
  end

  test "record_finish/3 replaces the series' earlier position", context do
    {:ok, _first} =
      SeriesWatchPositions.record_finish(context.profile.id, context.item_id, ~U[2026-11-14 10:00:00Z])

    later_episode =
      create_episode(%{season_id: context.episode.season_id, episode_number: 6, name: "Episode 6"})

    later = create_watch_progress(%{profile_id: context.profile.id, episode_id: later_episode.id})

    {:ok, second} =
      SeriesWatchPositions.record_finish(
        context.profile.id,
        later.playable_item_id,
        ~U[2026-11-14 11:00:00Z]
      )

    position = SeriesWatchPositions.get(context.profile.id, context.series.id)
    assert position.id == second.id
    assert position.order_key == ["00001", "00006"]
    assert position.finished_at == ~U[2026-11-14 11:00:00Z]
  end

  test "record_finish/3 keeps one position per profile", context do
    other_profile = create_profile(%{name: "Other Profile"})
    now = DateTime.utc_now(:second)

    {:ok, _position} = SeriesWatchPositions.record_finish(context.profile.id, context.item_id, now)

    assert SeriesWatchPositions.get(other_profile.id, context.series.id) == nil
  end

  test "record_finish/3 records no position for an episode of a season with no number", context do
    season = create_season(%{tv_series_id: context.series.id, name: "Specials"})
    episode = create_episode(%{season_id: season.id, episode_number: 1, name: "Special"})
    progress = create_watch_progress(%{profile_id: context.profile.id, episode_id: episode.id})

    assert SeriesWatchPositions.record_finish(
             context.profile.id,
             progress.playable_item_id,
             DateTime.utc_now(:second)
           ) == :none

    assert SeriesWatchPositions.get(context.profile.id, context.series.id) == nil
  end

  test "record_finish/3 records no position for an episode with no number", context do
    force_attrs(context.episode, episode_number: nil)

    assert SeriesWatchPositions.record_finish(
             context.profile.id,
             context.item_id,
             DateTime.utc_now(:second)
           ) == :none
  end

  test "record_finish/3 records a collection movie's order key against its collection", context do
    collection = create_movie_series(%{name: "Sample Collection"})

    movie =
      create_movie(%{
        name: "Movie A",
        movie_series_id: collection.id,
        date_published: ~D[2001-05-04],
        position: 2
      })

    progress = create_watch_progress(%{profile_id: context.profile.id, movie_id: movie.id})

    assert {:ok, position} =
             SeriesWatchPositions.record_finish(
               context.profile.id,
               progress.playable_item_id,
               DateTime.utc_now(:second)
             )

    assert position.series_id == collection.id
    assert position.series_type == :movie_series
    assert position.order_key == ["2001-05-04", "00002"]
  end

  test "record_finish/3 keeps the empty date of an undated collection movie in its order key", context do
    collection = create_movie_series(%{name: "Sample Collection"})
    movie = create_movie(%{name: "Movie A", movie_series_id: collection.id, position: 2})
    progress = create_watch_progress(%{profile_id: context.profile.id, movie_id: movie.id})

    assert {:ok, _position} =
             SeriesWatchPositions.record_finish(
               context.profile.id,
               progress.playable_item_id,
               DateTime.utc_now(:second)
             )

    # Read back: the key is compared element by element with the ordered
    # set's (`MovieOrder.order_key/1`), so a dropped element reorders it.
    assert SeriesWatchPositions.get(context.profile.id, collection.id).order_key == ["", "00002"]
  end

  test "record_finish/3 records nothing for a standalone movie" do
    profile = create_profile()
    movie = create_movie(%{name: "Movie A"})
    progress = create_watch_progress(%{profile_id: profile.id, movie_id: movie.id})

    assert SeriesWatchPositions.record_finish(
             profile.id,
             progress.playable_item_id,
             DateTime.utc_now(:second)
           ) == :none
  end

  test "deleting the finished episode leaves the position; destroying the series removes it",
       context do
    create_series_watch_position(%{profile_id: context.profile.id, playable_item_id: context.item_id})

    EntityCascade.delete_playable_items(:episode, context.episode.id)
    assert SeriesWatchPositions.get(context.profile.id, context.series.id)

    EntityCascade.destroy!(context.series.id)
    refute SeriesWatchPositions.get(context.profile.id, context.series.id)
  end

  test "clearing the library removes every position", context do
    create_series_watch_position(%{profile_id: context.profile.id, playable_item_id: context.item_id})

    EntityCascade.destroy_all!()

    refute SeriesWatchPositions.get(context.profile.id, context.series.id)
  end

  test "removing the profile removes its positions", context do
    create_series_watch_position(%{profile_id: context.profile.id, playable_item_id: context.item_id})

    :ok = MediaCentaur.Profiles.remove(context.profile)

    refute SeriesWatchPositions.get(context.profile.id, context.series.id)
  end

  test "by_series/2 returns positions keyed by series id", context do
    position =
      create_series_watch_position(%{profile_id: context.profile.id, playable_item_id: context.item_id})

    assert SeriesWatchPositions.by_series(context.profile.id, [context.series.id]) ==
             %{context.series.id => position}

    assert SeriesWatchPositions.by_series(context.profile.id, []) == %{}
  end
end
