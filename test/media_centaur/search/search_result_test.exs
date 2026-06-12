defmodule MediaCentaur.Search.SearchResultTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.SearchResult

  describe "from_prowlarr/1" do
    test "keeps info_hash and magnet_url from the raw result" do
      raw = %{
        "title" => "Sample.Release.2024.1080p-GRP",
        "guid" => "g1",
        "indexerId" => 3,
        "size" => 1_000,
        "infoHash" => "0123456789ABCDEF0123456789ABCDEF01234567",
        "magnetUrl" => "magnet:?xt=urn:btih:0123456789ABCDEF0123456789ABCDEF01234567"
      }

      result = SearchResult.from_prowlarr(raw)

      assert result.info_hash == "0123456789ABCDEF0123456789ABCDEF01234567"
      assert result.magnet_url =~ "urn:btih:"
    end

    test "leaves info_hash and magnet_url nil when the indexer omits them" do
      raw = %{"title" => "Sample.Release", "guid" => "g2", "indexerId" => 1}

      result = SearchResult.from_prowlarr(raw)

      assert result.info_hash == nil
      assert result.magnet_url == nil
    end

    test "scrubs invalid UTF-8 bytes from the title at the boundary" do
      # Indexers ship scene titles with mangled encodings; JSON decoding
      # passes the raw bytes through. Every downstream consumer (unicode
      # regexes, Ecto casts, the UI) assumes valid UTF-8, so the invariant
      # is enforced here, where external data enters the system.
      invalid_title = "Sample Movie 2024 1080p " <> <<0xE2, 0x80, 0x20>>
      refute String.valid?(invalid_title)

      raw = %{"title" => invalid_title, "guid" => "g3", "indexerId" => 1}

      result = SearchResult.from_prowlarr(raw)

      assert String.valid?(result.title)
      assert result.title =~ "Sample Movie 2024 1080p"
    end
  end
end
