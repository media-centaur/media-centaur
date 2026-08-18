defmodule MediaCentaur.DiscoveryTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Discovery.WatchlistItem

  describe "WatchlistItem.create_changeset/1" do
    test "valid with identity + name" do
      changeset =
        WatchlistItem.create_changeset(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      assert changeset.valid?
    end

    test "requires tmdb_id, media_type, name" do
      changeset = WatchlistItem.create_changeset(%{})
      refute changeset.valid?
      assert %{tmdb_id: _, media_type: _, name: _} = errors_on(changeset)
    end

    test "rejects unknown media_type" do
      changeset =
        WatchlistItem.create_changeset(%{tmdb_id: 777, media_type: :book, name: "Sample"})

      refute changeset.valid?
    end
  end
end
