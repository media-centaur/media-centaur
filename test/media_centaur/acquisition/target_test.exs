defmodule MediaCentaur.Acquisition.TargetTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Search.SearchResult

  @hex_lower "0123456789abcdef0123456789abcdef01234567"
  @hex_upper "0123456789ABCDEF0123456789ABCDEF01234567"

  describe "acquire_changeset/5 — auto-pick grab" do
    test "stores the torrent_hash it is handed (already normalized by the caller)" do
      changeset =
        Target.acquire_changeset(%Target{}, "1080p", "Sample.Release", "guid-1", @hex_lower)

      assert changeset.changes.torrent_hash == @hex_lower
      assert changeset.changes.status == "acquired"
      assert changeset.changes.release_title == "Sample.Release"
    end

    test "omits torrent_hash entirely when none is available (no nil clobber)" do
      changeset = Target.acquire_changeset(%Target{}, "1080p", "Sample.Release", "guid-1", nil)

      refute Map.has_key?(changeset.changes, :torrent_hash)
    end

    test "remains backward-compatible at arity 4 (no hash)" do
      changeset = Target.acquire_changeset(%Target{}, "1080p", "Sample.Release", "guid-1")

      refute Map.has_key?(changeset.changes, :torrent_hash)
      assert changeset.changes.status == "acquired"
    end
  end

  describe "acquired_changeset/2 — manual pick" do
    test "captures the infohash from the picked search result" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "g1",
        indexer_id: 1,
        info_hash: @hex_upper
      }

      changeset = Target.acquired_changeset(result, pursuit_id: Ecto.UUID.generate())

      assert changeset.changes.torrent_hash == @hex_lower
    end

    test "captures the infohash parsed from the magnet when info_hash is absent" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "g1",
        indexer_id: 1,
        magnet_url: "magnet:?xt=urn:btih:#{@hex_upper}&dn=Sample"
      }

      changeset = Target.acquired_changeset(result, pursuit_id: Ecto.UUID.generate())

      assert changeset.changes.torrent_hash == @hex_lower
    end

    test "omits the hash when the result carries none" do
      result = %SearchResult{title: "Sample.Release", guid: "g2", indexer_id: 1}

      changeset = Target.acquired_changeset(result, pursuit_id: Ecto.UUID.generate())

      refute Map.has_key?(changeset.changes, :torrent_hash)
    end
  end
end
