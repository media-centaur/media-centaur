defmodule MediaCentaur.ReleaseTracking.LibraryEventsTest do
  @moduledoc """
  The library never starts tracking a title. A series appearing in the
  library is a fact about the library, not a request to follow its
  releases — so `library_entities_changed/1` reconciles the links it
  already has and does nothing else.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs

  alias MediaCentaur.ReleaseTracking

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "library_entities_changed/1" do
    test "a new series in the library is not tracked" do
      tv_series = create_tv_series(%{name: "New Show", status: :returning})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "5555"})

      assert :ok = ReleaseTracking.library_entities_changed([tv_series.id])

      refute ReleaseTracking.get_item_by_tmdb(5555, :tv_series)
    end

    test "an already-tracked title is linked to the container that arrives" do
      tv_series = create_tv_series(%{name: "Followed Show", status: :returning})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "5556"})

      {:ok, item} =
        ReleaseTracking.track_item(%{
          tmdb_id: 5556,
          media_type: :tv_series,
          name: "Followed Show",
          tracking_mode: :watch
        })

      assert :ok = ReleaseTracking.library_entities_changed([tv_series.id])

      assert ReleaseTracking.get_item(item.id).library_container_id == tv_series.id
    end

    test "is a no-op for an empty batch" do
      assert :ok = ReleaseTracking.library_entities_changed([])
    end
  end
end
