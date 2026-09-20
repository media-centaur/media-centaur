defmodule MediaCentaur.ReleaseTracking.CompleteMovieTrackingTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking

  setup do
    ReleaseTracking.subscribe()
    :ok
  end

  test "removes movie tracking item when matching library Movie is created" do
    movie = create_standalone_movie(%{name: "Solo Movie", tmdb_id: "424242"})
    item = create_tracking_item(%{tmdb_id: 424_242, media_type: :movie, name: "Solo Movie"})

    :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])

    assert ReleaseTracking.get_item(item.id) == nil
    assert ReleaseTracking.get_item_by_tmdb(424_242, :movie) == nil
    assert_received {:item_removed, "424242", "movie"}
  end

  test "does not remove TV series tracking when a TV series library entity arrives" do
    tv_series = create_tv_series(%{name: "Active Series", tmdb_id: "55555"})
    item = create_tracking_item(%{tmdb_id: 55_555, media_type: :tv_series, name: "Active Series"})

    :ok = ReleaseTracking.complete_movie_tracking_for([tv_series.id])

    assert ReleaseTracking.get_item(item.id) != nil
  end

  test "does not remove tracking for a different film when an unrelated movie arrives" do
    movie = create_standalone_movie(%{name: "Single Film", tmdb_id: "111"})
    item = create_tracking_item(%{tmdb_id: 999, media_type: :movie, name: "Some Film"})

    :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])

    assert ReleaseTracking.get_item(item.id) != nil
  end

  test "is idempotent — second call after removal is a no-op" do
    movie = create_standalone_movie(%{name: "Idempotent Movie", tmdb_id: "303030"})
    create_tracking_item(%{tmdb_id: 303_030, media_type: :movie, name: "Idempotent Movie"})

    :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])
    assert ReleaseTracking.get_item_by_tmdb(303_030, :movie) == nil
    assert_received {:item_removed, "303030", "movie"}

    :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])
    refute_received {:item_removed, "303030", "movie"}
  end

  test "ignores library movies without a tmdb_id" do
    movie = create_standalone_movie(%{name: "Manual Import", tmdb_id: nil})
    item = create_tracking_item(%{tmdb_id: 777_777, media_type: :movie, name: "Manual Import"})

    :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])

    assert ReleaseTracking.get_item(item.id) != nil
  end
end
