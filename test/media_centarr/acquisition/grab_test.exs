defmodule MediaCentarr.Acquisition.GrabTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{Grab, SearchResult}

  describe "manual_grabbed_changeset/3" do
    test "produces a row in terminal grabbed state with manual origin" do
      result = %SearchResult{
        title: "Sample.Movie.2010.2160p.UHD.BluRay.REMUX-FGT",
        guid: "abc-123",
        indexer_id: 1,
        quality: :uhd_4k
      }

      changeset = Grab.manual_grabbed_changeset(result, "Sample Movie 2010")

      assert changeset.valid?
      assert changeset.changes.title == "Sample.Movie.2010.2160p.UHD.BluRay.REMUX-FGT"
      assert changeset.changes.tmdb_id == "abc-123"
      assert changeset.changes.tmdb_type == "manual"
      assert changeset.changes.origin == "manual"
      assert changeset.changes.status == "grabbed"
      assert changeset.changes.quality == "4K"
      assert changeset.changes.prowlarr_guid == "abc-123"
      assert changeset.changes.manual_query == "Sample Movie 2010"
      assert %DateTime{} = changeset.changes.grabbed_at
    end

    test "uses the parsed quality label even when result.quality is nil" do
      # An unparseable release title results in nil quality — record it as
      # "Unknown" rather than crashing the user's grab.
      result = %SearchResult{
        title: "Random.Release.Without.Quality.Markers",
        guid: "x",
        indexer_id: 1,
        quality: nil
      }

      changeset = Grab.manual_grabbed_changeset(result, "random")
      assert changeset.changes.quality == "Unknown"
    end

    test "trims whitespace-only query to nil for cleaner display" do
      result = %SearchResult{title: "T", guid: "g", indexer_id: 1, quality: :hd_1080p}
      changeset = Grab.manual_grabbed_changeset(result, "   ")
      assert Ecto.Changeset.get_field(changeset, :manual_query) == nil
    end
  end

  describe "create_changeset/1 — origin" do
    test "casts origin when provided" do
      changeset =
        Grab.create_changeset(%{
          tmdb_id: "1",
          tmdb_type: "movie",
          title: "T",
          origin: "manual"
        })

      assert changeset.changes.origin == "manual"
    end

    test "leaves origin out of changes when not provided (DB default applies)" do
      changeset = Grab.create_changeset(%{tmdb_id: "1", tmdb_type: "movie", title: "T"})
      refute Map.has_key?(changeset.changes, :origin)
    end
  end
end
