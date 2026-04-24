defmodule MediaCentarr.Showcase.StubsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Showcase.Stubs

  describe "prowlarr_plug/1" do
    test "search returns fixture results" do
      client = Req.new(plug: &Stubs.prowlarr_plug/1)
      assert {:ok, results} = Prowlarr.search("anything", [], client)
      assert length(results) >= 5
      assert Enum.any?(results, fn r -> r.title =~ "Night.of.the.Living.Dead" end)
    end

    test "search fixtures parse into SearchResult structs with quality" do
      client = Req.new(plug: &Stubs.prowlarr_plug/1)
      assert {:ok, results} = Prowlarr.search("anything", [], client)

      assert Enum.all?(results, fn r -> is_integer(r.seeders) end)
      assert Enum.all?(results, fn r -> is_binary(r.guid) and r.guid != "" end)
      # At least one UHD title
      assert Enum.any?(results, fn r -> r.quality == :uhd_4k end)
    end

    test "grab endpoint returns ok with empty body" do
      client = Req.new(plug: &Stubs.prowlarr_plug/1)

      {:ok, [result | _]} = Prowlarr.search("anything", [], client)
      assert :ok = Prowlarr.grab(result, client)
    end
  end

  describe "qbittorrent_plug/1" do
    test "list_downloads :active returns fixture torrents" do
      client = Req.new(plug: &Stubs.qbittorrent_plug/1, retry: false)
      assert {:ok, items} = QBittorrent.list_downloads(:active, client)
      assert length(items) >= 4
      assert Enum.any?(items, fn i -> i.title =~ "Big.Buck.Bunny" end)
    end

    test "list_downloads :completed returns empty list" do
      client = Req.new(plug: &Stubs.qbittorrent_plug/1, retry: false)
      assert {:ok, []} = QBittorrent.list_downloads(:completed, client)
    end

    test "fixture torrents populate progress and state fields" do
      client = Req.new(plug: &Stubs.qbittorrent_plug/1, retry: false)
      assert {:ok, items} = QBittorrent.list_downloads(:all, client)

      assert Enum.any?(items, fn i -> i.state == :downloading end)
      assert Enum.any?(items, fn i -> i.state == :stalled end)
      assert Enum.all?(items, fn i -> is_binary(i.id) and i.id != "" end)
    end

    test "test_connection returns ok" do
      client = Req.new(plug: &Stubs.qbittorrent_plug/1, retry: false)
      assert :ok = QBittorrent.test_connection(client)
    end
  end
end
