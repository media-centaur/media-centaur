defmodule MediaCentaur.ReleaseTracking.LibraryEventsTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.AutoTrackJob

  setup do
    setup_tmdb_client()
    :ok
  end

  defp stub_new_show(tmdb_id) do
    stub_routes([
      {"/tv/#{tmdb_id}",
       %{
         "id" => tmdb_id,
         "name" => "New Show",
         "status" => "Returning Series",
         "poster_path" => "/new.jpg",
         "number_of_seasons" => 1,
         "next_episode_to_air" => %{
           "air_date" => "2026-07-01",
           "season_number" => 2,
           "episode_number" => 1,
           "name" => "Premiere"
         }
       }}
    ])
  end

  describe "library_entities_changed/1" do
    test "reconciles links inline and auto-tracks through the job" do
      tv_series = create_tv_series(%{name: "New Show", status: :returning})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "5555"})
      stub_new_show(5555)

      # Oban runs inline in tests, so the job's TMDB work has happened by
      # the time this returns — the auto-tracked item is the evidence.
      assert :ok = ReleaseTracking.library_entities_changed([tv_series.id])

      item = ReleaseTracking.get_item_by_tmdb(5555, :tv_series)
      assert item.library_container_id == tv_series.id
      assert item.source == :library
    end

    test "is a no-op for an empty batch" do
      assert :ok = ReleaseTracking.library_entities_changed([])
    end
  end

  describe "AutoTrackJob.perform/1" do
    test "auto-tracks the entity ids it was enqueued with" do
      tv_series = create_tv_series(%{name: "New Show", status: :returning})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "6565"})
      stub_new_show(6565)

      assert :ok = perform_job(AutoTrackJob, %{"entity_ids" => [tv_series.id]})
      assert ReleaseTracking.get_item_by_tmdb(6565, :tv_series)
    end
  end
end
