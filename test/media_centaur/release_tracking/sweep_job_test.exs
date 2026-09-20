defmodule MediaCentaur.ReleaseTracking.SweepJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.SweepJob

  @yesterday Date.add(Date.utc_today(), -1)

  defp perform do
    Oban.Testing.perform_job(SweepJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)
  end

  test "an aired release becomes an open want" do
    item = create_tracking_item(%{tmdb_id: 4242, media_type: :tv_series})

    ReleaseTracking.create_release!(%{
      item_id: item.id,
      air_date: @yesterday,
      title: "Just Aired",
      season_number: 4,
      episode_number: 1
    })

    assert :ok = perform()
    assert [%{season_number: 4, episode_number: 1}] = ReleaseTracking.open_wants_for_item(item.id)
  end

  test "publishes {:tracking_sweep_completed} — the drop planner's clock" do
    ReleaseTracking.subscribe()
    assert :ok = perform()
    assert_receive {:tracking_sweep_completed}
  end
end
