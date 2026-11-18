defmodule MediaCentaur.NewReleases.TmdbReferencesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Features
  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.TmdbReferences

  setup do
    :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
  end

  test "every member is a scheduled reference while the feature is on" do
    assert Features.enabled?(:new_releases)

    assert TmdbReferences.references() == MapSet.new([{301, :movie}])
    assert TmdbReferences.schedules_checks?()
  end

  test "while the feature is off the shelf references nothing" do
    Features.set(:new_releases, false)
    assert TmdbReferences.references() == MapSet.new()
  end
end
