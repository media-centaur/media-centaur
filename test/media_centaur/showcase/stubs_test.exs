defmodule MediaCentaur.Showcase.StubsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Downloads.DownloadClient.QBittorrent.Sync
  alias MediaCentaur.Search.Prowlarr
  alias MediaCentaur.Showcase.Stubs

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
    # The showcase driver is exercised through the real `QBittorrent`
    # module in showcase mode; here the plug's own HTTP contract is pinned.
    defp showcase_qbittorrent, do: Req.new(plug: &Stubs.qbittorrent_plug/1, retry: false)

    test "torrents/info returns fixture torrents with progress and state" do
      assert {:ok, %{status: 200, body: torrents}} =
               Req.get(showcase_qbittorrent(), url: "/api/v2/torrents/info", params: [filter: "all"])

      assert length(torrents) >= 4
      assert Enum.any?(torrents, fn t -> t["name"] =~ "Big.Buck.Bunny" end)
      assert Enum.all?(torrents, fn t -> is_binary(t["hash"]) and t["hash"] != "" end)
      assert Enum.any?(torrents, fn t -> t["state"] == "downloading" end)
    end

    test "login accepts any credentials and sets a session cookie" do
      assert {:ok, %{status: 200} = response} =
               Req.post(showcase_qbittorrent(),
                 url: "/api/v2/auth/login",
                 form: [username: "a", password: "b"]
               )

      assert Enum.any?(response.headers["set-cookie"] || [], &String.starts_with?(&1, "SID="))
    end

    test "app/version answers 200" do
      assert {:ok, %{status: 200}} = Req.get(showcase_qbittorrent(), url: "/api/v2/app/version")
    end

    test "sync/maindata answers the queue monitor's poll as a full update" do
      # QueueMonitor polls sync/maindata, not torrents/info. Without this
      # route the showcase logged a 404 every tick and the Connections
      # strip chart's only data was failed qBittorrent requests.
      assert {:ok, %{status: 200, body: body}} =
               Req.get(showcase_qbittorrent(), url: "/api/v2/sync/maindata", params: [rid: 0])

      assert body["full_update"] == true
      assert is_map(body["torrents"])

      torrents = Sync.apply_maindata(%{}, body)
      assert map_size(torrents) >= 4
      assert Enum.all?(torrents, fn {hash, torrent} -> torrent["hash"] == hash end)
      assert Enum.any?(Sync.to_queue_items(torrents), &(&1.title =~ "Big.Buck.Bunny"))
    end
  end
end
