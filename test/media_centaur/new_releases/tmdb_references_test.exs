defmodule MediaCentaur.NewReleases.TmdbReferencesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.TmdbReferences

  test "every member is a scheduled reference" do
    :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])

    assert TmdbReferences.references() == MapSet.new([{301, :movie}])
    assert TmdbReferences.schedules_checks?()
  end

  test "an empty shelf references nothing" do
    assert TmdbReferences.references() == MapSet.new()
  end
end
