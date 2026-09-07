defmodule MediaCentaur.ReleaseTracking.EventsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Events.TrackingStarted
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  # ADR-065: creating a tracked title is machinery and is silent; arming is
  # a person's act and announces. The announcement follows the act, not the
  # row — which is why `source` could be removed with nothing lost.

  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()
    ReleaseTracking.subscribe()
    :ok
  end

  test "arming announces TrackingStarted with the title it holds" do
    item = create_tracking_item(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})
    title = Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})

    {:ok, armed} = ReleaseTracking.arm(title)
    await_supervised_tasks()

    assert armed.id == item.id

    assert_receive {:tracking_started, %TrackingStarted{item_id: item_id, title: %Title{} = announced}},
                   500

    assert item_id == item.id
    assert %Title{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"} = announced
  end

  test "arming puts the title on the watchlist — the invariant, kept by the act itself" do
    create_tracking_item(%{tmdb_id: 1400, media_type: :tv_series, name: "Sample Show"})
    title = Title.new!(%{tmdb_id: 1400, media_type: :tv_series, name: "Sample Show"})

    {:ok, _armed} = ReleaseTracking.arm(title)
    await_supervised_tasks()

    assert MediaCentaur.Discovery.on_watchlist?(1400, :tv_series)
  end

  test "arming an already-armed title does not overwrite the mode the person set" do
    item = create_tracking_item(%{tmdb_id: 1401, media_type: :tv_series, name: "Sample Show"})
    {:ok, _} = ReleaseTracking.set_tracking_mode(item, :grab)
    title = Title.new!(%{tmdb_id: 1401, media_type: :tv_series, name: "Sample Show"})

    {:ok, armed} = ReleaseTracking.arm(title)
    await_supervised_tasks()

    assert armed.tracking_mode == :grab
  end

  test "creating a tracked title is silent, whatever mode it is seeded with" do
    for {tmdb_id, mode} <- [{1402, :watch}, {1403, :global}] do
      {:ok, _item} =
        ReleaseTracking.track_item(%{
          tmdb_id: tmdb_id,
          media_type: :tv_series,
          name: "Sample Show",
          tracking_mode: mode
        })
    end

    refute_receive {:tracking_started, _event}, 100
  end
end
