defmodule MediaCentaur.ReleaseTracking.EventsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Events.TrackingStarted
  alias MediaCentaur.TMDB.Title

  setup do
    ReleaseTracking.subscribe()
    :ok
  end

  test "a manual tracking item broadcasts TrackingStarted with the title it holds" do
    {:ok, item} =
      ReleaseTracking.track_item(%{
        tmdb_id: 1399,
        media_type: :tv_series,
        name: "Sample Show",
        source: :manual
      })

    assert_receive {:tracking_started, %TrackingStarted{item_id: item_id, title: %Title{} = title}}, 500
    assert item_id == item.id
    assert %Title{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"} = title
  end

  test "a library-sourced item is silent" do
    {:ok, _item} =
      ReleaseTracking.track_item(%{
        tmdb_id: 1399,
        media_type: :tv_series,
        name: "Sample Show",
        source: :library
      })

    refute_receive {:tracking_started, _event}, 100
  end
end
