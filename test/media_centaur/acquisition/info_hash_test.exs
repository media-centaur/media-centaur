defmodule MediaCentaur.Acquisition.InfoHashTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.InfoHash
  alias MediaCentaur.Search.SearchResult

  # A real v1 infohash is 20 bytes → 40 hex chars → 32 base32 chars.
  # "Sample" bytes below are arbitrary but consistent across forms.
  @hex_lower "0123456789abcdef0123456789abcdef01234567"
  @hex_upper "0123456789ABCDEF0123456789ABCDEF01234567"

  describe "normalize/1" do
    test "downcases a 40-char hex infohash" do
      assert InfoHash.normalize(@hex_upper) == @hex_lower
    end

    test "passes a lowercase 40-char hex infohash through unchanged" do
      assert InfoHash.normalize(@hex_lower) == @hex_lower
    end

    test "decodes a 32-char base32 infohash to 40-char lowercase hex" do
      # Round-trip: encode the 20 raw bytes of @hex_lower as base32, then
      # expect normalize to recover the lowercase hex form.
      raw = Base.decode16!(@hex_upper)
      base32 = Base.encode32(raw, padding: false)

      assert byte_size(base32) == 32
      assert InfoHash.normalize(base32) == @hex_lower
    end

    test "trims surrounding whitespace" do
      assert InfoHash.normalize("  #{@hex_upper}  ") == @hex_lower
    end

    test "returns nil for a wrong-length string" do
      assert InfoHash.normalize("deadbeef") == nil
    end

    test "returns nil for a 40-char non-hex string" do
      assert InfoHash.normalize(String.duplicate("z", 40)) == nil
    end

    test "returns nil for nil" do
      assert InfoHash.normalize(nil) == nil
    end
  end

  describe "from_magnet/1" do
    test "extracts and normalizes a hex btih" do
      magnet = "magnet:?xt=urn:btih:#{@hex_upper}&dn=Sample.Release&tr=udp://tracker"
      assert InfoHash.from_magnet(magnet) == @hex_lower
    end

    test "extracts and normalizes a base32 btih" do
      raw = Base.decode16!(@hex_upper)
      base32 = Base.encode32(raw, padding: false)
      magnet = "magnet:?xt=urn:btih:#{base32}&dn=Sample"
      assert InfoHash.from_magnet(magnet) == @hex_lower
    end

    test "handles btih before other params with no dn" do
      assert InfoHash.from_magnet("magnet:?xt=urn:btih:#{@hex_lower}") == @hex_lower
    end

    test "returns nil for a v2-only magnet (urn:btmh)" do
      magnet = "magnet:?xt=urn:btmh:1220abc123&dn=Sample"
      assert InfoHash.from_magnet(magnet) == nil
    end

    test "returns nil for a non-magnet string" do
      assert InfoHash.from_magnet("https://example.test/file.torrent") == nil
    end

    test "returns nil for nil" do
      assert InfoHash.from_magnet(nil) == nil
    end
  end

  describe "from_search_result/1" do
    test "prefers the info_hash field" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "g1",
        indexer_id: 1,
        info_hash: @hex_upper,
        magnet_url: "magnet:?xt=urn:btih:#{String.duplicate("f", 40)}"
      }

      assert InfoHash.from_search_result(result) == @hex_lower
    end

    test "falls back to the magnet_url when info_hash is nil" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "g1",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: "magnet:?xt=urn:btih:#{@hex_upper}&dn=Sample"
      }

      assert InfoHash.from_search_result(result) == @hex_lower
    end

    test "falls back to the magnet_url when info_hash is unparseable" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "g1",
        indexer_id: 1,
        info_hash: "not-a-hash",
        magnet_url: "magnet:?xt=urn:btih:#{@hex_lower}"
      }

      assert InfoHash.from_search_result(result) == @hex_lower
    end

    test "returns nil when neither source carries a usable hash" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "g1",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: nil
      }

      assert InfoHash.from_search_result(result) == nil
    end
  end

  describe "from_search_result/1 magnet guid" do
    test "falls back to a magnet guid when info_hash and magnet_url are nil" do
      result = %SearchResult{
        title: "Sample.Release.2024.1080p-GRP",
        guid: "magnet:?xt=urn:btih:#{@hex_upper}&dn=Sample",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: nil
      }

      assert InfoHash.from_search_result(result) == @hex_lower
    end
  end

  describe "from_torrent/1" do
    test "computes the v1 infohash from the info-dict byte span (info last)" do
      info = "d5:filesld6:lengthi100e4:pathl8:file.mkveee4:name3:dire"
      torrent = "d8:announce21:http://tracker.test/a4:info" <> info <> "e"
      expected = :sha |> :crypto.hash(info) |> Base.encode16(case: :lower)

      assert InfoHash.from_torrent(torrent) == expected
    end

    test "computes the infohash when info is not the last key" do
      info = "d6:lengthi12345e4:name9:movie.mkve"
      torrent = "d4:info" <> info <> "1:z1:!e"
      expected = :sha |> :crypto.hash(info) |> Base.encode16(case: :lower)

      assert InfoHash.from_torrent(torrent) == expected
    end

    test "returns nil for bytes that are not a bencoded dict" do
      assert InfoHash.from_torrent("not a torrent") == nil
    end

    test "returns nil for a bencoded dict with no info key" do
      assert InfoHash.from_torrent("d8:announce3:abce") == nil
    end

    test "returns nil for nil" do
      assert InfoHash.from_torrent(nil) == nil
    end
  end

  describe "resolve/2" do
    test "returns the search-result hash without fetching" do
      result = %SearchResult{
        title: "Sample",
        guid: "g1",
        indexer_id: 1,
        info_hash: @hex_upper,
        magnet_url: nil
      }

      fetcher = fn _url -> raise "should not fetch when the hash is already known" end
      assert InfoHash.resolve(result, fetcher) == @hex_lower
    end

    test "fetches and parses a magnet redirect when the result has no hash" do
      result = %SearchResult{
        title: "Sample",
        guid: "g1",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: nil,
        download_url: "http://prowlarr.test/download/1"
      }

      fetcher = fn "http://prowlarr.test/download/1" ->
        {:magnet, "magnet:?xt=urn:btih:#{@hex_upper}&dn=Sample"}
      end

      assert InfoHash.resolve(result, fetcher) == @hex_lower
    end

    test "fetches and hashes a .torrent body when the result has no hash" do
      info = "d6:lengthi1e4:name3:abce"
      torrent = "d4:info" <> info <> "e"
      expected = :sha |> :crypto.hash(info) |> Base.encode16(case: :lower)

      result = %SearchResult{
        title: "Sample",
        guid: "g1",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: nil,
        download_url: "http://prowlarr.test/download/2"
      }

      fetcher = fn _url -> {:torrent, torrent} end
      assert InfoHash.resolve(result, fetcher) == expected
    end

    test "returns nil when the fetch fails" do
      result = %SearchResult{
        title: "Sample",
        guid: "g1",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: nil,
        download_url: "http://prowlarr.test/download/3"
      }

      fetcher = fn _url -> :error end
      assert InfoHash.resolve(result, fetcher) == nil
    end

    test "returns nil without fetching when there is no download_url" do
      result = %SearchResult{
        title: "Sample",
        guid: "g1",
        indexer_id: 1,
        info_hash: nil,
        magnet_url: nil,
        download_url: nil
      }

      fetcher = fn _url -> raise "should not fetch without a download_url" end
      assert InfoHash.resolve(result, fetcher) == nil
    end
  end
end
