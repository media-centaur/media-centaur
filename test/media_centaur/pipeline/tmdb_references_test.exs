defmodule MediaCentaur.Pipeline.TmdbReferencesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Pipeline.TmdbReferences

  test "every owned movie and series is a reference; a collection is not" do
    create_movie(%{name: "Sample Movie", tmdb_id: "550"})
    create_tv_series(%{name: "Sample Show", tmdb_id: "1396"})
    collection = create_movie_series(%{name: "Sample Collection"})
    create_external_id(%{movie_series_id: collection.id, source: "tmdb_collection", external_id: "263"})

    assert TmdbReferences.references() == MapSet.new([{550, :movie}, {1396, :tv_series}])
  end

  test "owned titles schedule checks" do
    assert TmdbReferences.schedules_checks?()
  end
end
