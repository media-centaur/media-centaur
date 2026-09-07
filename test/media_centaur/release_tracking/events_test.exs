defmodule MediaCentaur.ReleaseTracking.EventsTest do
  @moduledoc """
  Creating a tracked title is machinery and is silent; a person raising a
  rung onto Follow is the act, and announces. The announcement follows
  the act, not the row — which is why the row needs no provenance field
  to say where it came from.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TmdbStubs

  alias MediaCentaur.Discovery
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Events.TrackingStarted
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()
    stub_series_universe_for_targeting()
    ReleaseTracking.subscribe()
    :ok
  end

  defp show(tmdb_id), do: Title.new!(%{tmdb_id: tmdb_id, media_type: :tv_series, name: "Sample Show"})

  test "crossing onto Follow announces TrackingStarted with the title it holds" do
    {:ok, _intent} = ReleaseTracking.set_rung(show(246_810), :follow)
    await_supervised_tasks()

    item = ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)

    assert_receive {:tracking_started, %TrackingStarted{item_id: item_id, title: %Title{} = announced}},
                   500

    assert item_id == item.id
    assert %Title{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"} = announced
  end

  test "the record is written by the same act — there is no second step to forget" do
    {:ok, _intent} = ReleaseTracking.set_rung(show(246_810), :follow)
    await_supervised_tasks()

    assert Discovery.listed?(246_810, :tv_series)
    assert Discovery.rung(246_810, :tv_series) == :follow
  end

  test "moving between following rungs announces nothing — following already began" do
    {:ok, _} = ReleaseTracking.set_rung(show(246_810), :follow)
    await_supervised_tasks()
    assert_receive {:tracking_started, %TrackingStarted{}}, 500

    {:ok, intent} = ReleaseTracking.set_rung(show(246_810), :grab)
    await_supervised_tasks()

    assert intent.rung == :grab
    refute_receive {:tracking_started, _event}, 100
  end

  test "dropping off the ladder and back on announces again" do
    {:ok, _} = ReleaseTracking.set_rung(show(246_810), :grab)
    await_supervised_tasks()
    assert_receive {:tracking_started, %TrackingStarted{}}, 500

    {:ok, nil} = ReleaseTracking.set_rung(show(246_810), :off)
    {:ok, _} = ReleaseTracking.set_rung(show(246_810), :follow)
    await_supervised_tasks()

    assert_receive {:tracking_started, %TrackingStarted{}}, 500
  end

  test "creating a tracked title directly is silent — it is machinery, not an act" do
    for tmdb_id <- [1402, 1403] do
      {:ok, _item} =
        ReleaseTracking.track_item(%{
          tmdb_id: tmdb_id,
          media_type: :tv_series,
          name: "Sample Show"
        })
    end

    refute_receive {:tracking_started, _event}, 100
  end
end
