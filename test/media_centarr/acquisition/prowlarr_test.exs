defmodule MediaCentarr.Acquisition.ProwlarrTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Acquisition.{Prowlarr, SearchResult}

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)
    on_exit(fn -> :persistent_term.erase({Prowlarr, :client}) end)
    {:ok, client: client}
  end

  describe "search/2" do
    test "returns search results parsed from Prowlarr response" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT",
            "guid" => "abc123",
            "indexerId" => 1,
            "size" => 50_000_000_000,
            "seeders" => 42,
            "leechers" => 5,
            "indexer" => "sample-indexer",
            "publishDate" => "2024-06-01T00:00:00Z"
          }
        ])
      end)

      assert {:ok, [result]} = Prowlarr.search("Sample Movie", year: 2024)

      assert %SearchResult{} = result
      assert result.title == "Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT"
      assert result.guid == "abc123"
      assert result.indexer_id == 1
      assert result.quality == :uhd_4k
      assert result.seeders == 42
      assert result.indexer_name == "sample-indexer"
    end

    test "returns empty list when no results" do
      assert {:ok, []} = Prowlarr.search("Nonexistent Movie 9999")
    end

    test "returns multiple results with quality parsed" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2023.2160p.BluRay.REMUX",
            "guid" => "guid-4k",
            "indexerId" => 1
          },
          %{
            "title" => "Sample.Movie.2023.1080p.BluRay.x264",
            "guid" => "guid-1080",
            "indexerId" => 1
          }
        ])
      end)

      assert {:ok, [first, second]} = Prowlarr.search("Sample Movie")
      assert first.quality == :uhd_4k
      assert second.quality == :hd_1080p
    end

    test "returns error on non-200 response" do
      Req.Test.stub(:prowlarr, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Unauthorized"}))
      end)

      assert {:error, _} = Prowlarr.search("some movie")
    end
  end

  describe "grab/1" do
    test "posts grab request to /api/v1/search with guid and indexer_id, returns :ok" do
      Req.Test.stub(:prowlarr, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v1/search"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["guid"] == "abc123"
        assert payload["indexerId"] == 1
        Req.Test.json(conn, %{"approved" => true})
      end)

      result = %SearchResult{title: "Some.Movie.2160p", guid: "abc123", indexer_id: 1}
      assert :ok = Prowlarr.grab(result)
    end

    test "returns error on HTTP failure" do
      Req.Test.stub(:prowlarr, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"message" => "Bad Request"}))
      end)

      result = %SearchResult{title: "Some.Movie.2160p", guid: "bad-guid", indexer_id: 1}
      assert {:error, _} = Prowlarr.grab(result)
    end
  end

  describe "list_download_clients/0" do
    test "GETs /api/v1/downloadclient and parses each entry" do
      Req.Test.stub(:prowlarr, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v1/downloadclient"

        Req.Test.json(conn, [
          %{
            "id" => 1,
            "name" => "qBittorrent Local",
            "implementation" => "QBittorrent",
            "enable" => true,
            "fields" => [
              %{"name" => "host", "value" => "localhost"},
              %{"name" => "port", "value" => 8080},
              %{"name" => "username", "value" => "admin"},
              %{"name" => "password", "value" => ""},
              %{"name" => "useSsl", "value" => false}
            ]
          }
        ])
      end)

      assert {:ok, [client]} = Prowlarr.list_download_clients()
      assert client.name == "qBittorrent Local"
      assert client.type == "qbittorrent"
      assert client.url == "http://localhost:8080"
      assert client.username == "admin"
      assert client.enabled == true
    end

    test "uses https when useSsl is true" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "name" => "qb",
            "implementation" => "QBittorrent",
            "enable" => true,
            "fields" => [
              %{"name" => "host", "value" => "qb.example.com"},
              %{"name" => "port", "value" => 8443},
              %{"name" => "useSsl", "value" => true}
            ]
          }
        ])
      end)

      assert {:ok, [client]} = Prowlarr.list_download_clients()
      assert client.url == "https://qb.example.com:8443"
    end

    test "lowercases unknown implementation strings for forward compatibility" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "name" => "deluge",
            "implementation" => "Deluge",
            "enable" => true,
            "fields" => [
              %{"name" => "host", "value" => "h"},
              %{"name" => "port", "value" => 8112}
            ]
          }
        ])
      end)

      assert {:ok, [client]} = Prowlarr.list_download_clients()
      assert client.type == "deluge"
    end

    test "tolerates fields with no \"value\" key (real Prowlarr response shape)" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "name" => "qBit",
            "implementation" => "QBittorrent",
            "enable" => true,
            "fields" => [
              %{"name" => "host", "value" => "localhost"},
              %{"name" => "port", "value" => 8080},
              # Real Prowlarr returns optional fields with no "value" key.
              %{
                "name" => "urlBase",
                "label" => "URL Base",
                "type" => "textbox",
                "advanced" => true
              },
              %{"name" => "username", "value" => "admin"}
            ]
          }
        ])
      end)

      assert {:ok, [client]} = Prowlarr.list_download_clients()
      assert client.url == "http://localhost:8080"
      assert client.username == "admin"
    end

    test "returns empty list when none configured" do
      assert {:ok, []} = Prowlarr.list_download_clients()
    end

    test "returns http_error on non-200 response" do
      Req.Test.stub(:prowlarr, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Unauthorized"}))
      end)

      assert {:error, _} = Prowlarr.list_download_clients()
    end
  end

  describe "default_client/0" do
    setup do
      original = :persistent_term.get({MediaCentarr.Config, :config})

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        %{
          original
          | prowlarr_url: "http://prowlarr.test",
            prowlarr_api_key: MediaCentarr.Secret.wrap("test-key"),
            showcase_mode: false
        }
      )

      Prowlarr.invalidate_client()

      on_exit(fn ->
        :persistent_term.put({MediaCentarr.Config, :config}, original)
        Prowlarr.invalidate_client()
      end)

      :ok
    end

    test "disables Req retries so transport errors fail fast" do
      client = Prowlarr.default_client()
      assert client.options[:retry] == false
    end

    test "uses a generous receive_timeout that survives slow indexer searches" do
      # Prowlarr's /api/v1/search fans out to every configured indexer in
      # real time and can take 20s+ legitimately. The client default must
      # not clip valid responses; the lightweight `ping/0` overrides this
      # per-call when fast failure is appropriate.
      client = Prowlarr.default_client()
      timeout = client.options[:receive_timeout]
      assert is_integer(timeout)
      assert timeout >= 30_000
    end
  end

  describe "ping/0" do
    test "returns :ok on 200 from /api/v1/system/status" do
      Req.Test.stub(:prowlarr, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v1/system/status"
        Req.Test.json(conn, %{"version" => "1.0.0", "appName" => "Prowlarr"})
      end)

      assert Prowlarr.ping() == :ok
    end

    test "returns {:error, {:http_error, 401, _}} when the api key is wrong" do
      Req.Test.stub(:prowlarr, fn conn ->
        Plug.Conn.send_resp(conn, 401, "")
      end)

      assert {:error, {:http_error, 401, _}} = Prowlarr.ping()
    end

    test "returns {:error, transport_error} on network failure" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %Req.TransportError{reason: :timeout}} = Prowlarr.ping()
    end
  end
end
