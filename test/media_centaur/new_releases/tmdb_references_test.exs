defmodule MediaCentaur.NewReleases.TmdbReferencesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Features
  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.TmdbReferences

  setup do
    :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
  end

  test "every member is a scheduled reference while Discovery is on" do
    Features.set(:discovery, true)

    assert TmdbReferences.references() == MapSet.new([{301, :movie}])
    assert TmdbReferences.schedules_checks?()
  end

  test "while Discovery is off the shelf references nothing" do
    refute Features.enabled?(:discovery)
    assert TmdbReferences.references() == MapSet.new()
  end
end
