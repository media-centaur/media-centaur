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
  end
end
