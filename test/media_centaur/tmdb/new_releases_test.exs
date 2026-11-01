defmodule MediaCentaur.TMDB.NewReleasesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.NewReleases
  alias MediaCentaur.TMDB.NewReleases.Member

  describe "replace/1 and the reads" do
    test "the membership is the entries in order, with their digital dates" do
      :ok =
        NewReleases.replace([
          %{tmdb_id: 301, digital_date: ~D[2026-10-30]},
          %{tmdb_id: 302, digital_date: ~D[2026-10-24]}
        ])

      assert [
               %Member{tmdb_id: 301, position: 0, digital_date: ~D[2026-10-30]},
               %Member{tmdb_id: 302, position: 1, digital_date: ~D[2026-10-24]}
             ] = NewReleases.members()

      assert NewReleases.refs() == [{301, :movie}, {302, :movie}]
    end

    test "a second replace is the whole shelf, not an addition" do
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
      :ok = NewReleases.replace([%{tmdb_id: 303, digital_date: ~D[2026-10-31]}])

      assert NewReleases.refs() == [{303, :movie}]
    end

    test "a duplicate id keeps its first position" do
      :ok =
        NewReleases.replace([
          %{tmdb_id: 301, digital_date: ~D[2026-10-30]},
          %{tmdb_id: 302, digital_date: ~D[2026-10-24]},
          %{tmdb_id: 301, digital_date: ~D[2026-10-30]}
        ])

      assert NewReleases.refs() == [{301, :movie}, {302, :movie}]
    end

    test "an empty list empties the shelf" do
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])
      :ok = NewReleases.replace([])

      assert NewReleases.members() == []
    end

    test "every replace is announced on the shelf's topic" do
      :ok = NewReleases.subscribe()
      :ok = NewReleases.replace([%{tmdb_id: 301, digital_date: ~D[2026-10-30]}])

      assert_receive {:new_releases_changed}
    end
  end
end
