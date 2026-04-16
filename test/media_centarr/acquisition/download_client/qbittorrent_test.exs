defmodule MediaCentarr.Acquisition.DownloadClient.QBittorrentTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Acquisition.QueueItem
  alias MediaCentarr.{Config, Secret}

  setup do
    original_config = :persistent_term.get({Config, :config}, %{})

    :persistent_term.put(
      {Config, :config},
      Map.merge(original_config, %{
        download_client_url: "http://qbit.test",
        download_client_username: "alice",
        download_client_password: Secret.wrap("s3cret")
      })
    )

    Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original_config)
      QBittorrent.invalidate_client()
    end)

    {:ok, client: client}
  end

  describe "list_downloads/2" do
    test "GETs /api/v2/torrents/info with filter=all by default", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v2/torrents/info"
        assert conn.params == %{"filter" => "all"}
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = QBittorrent.list_downloads(:all, client)
    end

    test "translates :active filter to qbittorrent's \"active\"", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.params == %{"filter" => "active"}
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = QBittorrent.list_downloads(:active, client)
    end

    test "translates :completed filter to qbittorrent's \"completed\"", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.params == %{"filter" => "completed"}
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = QBittorrent.list_downloads(:completed, client)
    end

    test "parses each torrent into a QueueItem", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        Req.Test.json(conn, [
          %{
            "hash" => "abc",
            "name" => "Movie.2024",
            "state" => "downloading",
            "size" => 100,
            "amount_left" => 25,
            "progress" => 0.75,
            "eta" => 60,
            "category" => "movies"
          }
        ])
      end)

      assert {:ok, [%QueueItem{} = item]} = QBittorrent.list_downloads(:all, client)
      assert item.id == "abc"
      assert item.title == "Movie.2024"
      assert item.state == :downloading
      assert item.progress == 75.0
    end

    test "returns http_error tuple on non-200, non-403 responses", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, ~s({"error":"oops"}))
      end)

      assert {:error, {:http_error, 500, _}} = QBittorrent.list_downloads(:all, client)
    end
  end

  describe "auth retry on 403" do
    test "calls /api/v2/auth/login with form-encoded creds, then retries", %{client: client} do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/torrents/info"} ->
            n = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if n == 0 do
              Plug.Conn.send_resp(conn, 403, "Forbidden")
            else
              Req.Test.json(conn, [])
            end

          {"POST", "/api/v2/auth/login"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "username=alice&password=s3cret"

            conn
            |> Plug.Conn.put_resp_header("set-cookie", "SID=abc123; HttpOnly; SameSite=Strict")
            |> Plug.Conn.send_resp(200, "Ok.")
        end
      end)

      assert {:ok, []} = QBittorrent.list_downloads(:all, client)
      # 1st info call (403), then login, then retry info (200)
      assert :counters.get(counter, 1) == 2
    end

    test "returns :auth_failed when login returns 403", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/torrents/info"} ->
            Plug.Conn.send_resp(conn, 403, "Forbidden")

          {"POST", "/api/v2/auth/login"} ->
            Plug.Conn.send_resp(conn, 403, "Fails.")
        end
      end)

      assert {:error, :auth_failed} = QBittorrent.list_downloads(:all, client)
    end

    test "returns :auth_failed when login returns 200 but no SID cookie", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/torrents/info"} ->
            Plug.Conn.send_resp(conn, 403, "Forbidden")

          {"POST", "/api/v2/auth/login"} ->
            Plug.Conn.send_resp(conn, 200, "Ok.")
        end
      end)

      assert {:error, :auth_failed} = QBittorrent.list_downloads(:all, client)
    end
  end

  describe "cancel_download/2" do
    test "POSTs /api/v2/torrents/delete with hash and deleteFiles=true", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v2/torrents/delete"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == "hashes=abc123&deleteFiles=true"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert :ok = QBittorrent.cancel_download("abc123", client)
    end

    test "returns http_error tuple on non-200, non-403 responses", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:error, {:http_error, 500, _}} = QBittorrent.cancel_download("abc", client)
    end

    test "re-auths on 403 then retries the delete", %{client: client} do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} ->
            n = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if n == 0 do
              Plug.Conn.send_resp(conn, 403, "Forbidden")
            else
              Plug.Conn.send_resp(conn, 200, "")
            end

          {"POST", "/api/v2/auth/login"} ->
            conn
            |> Plug.Conn.put_resp_header("set-cookie", "SID=xyz")
            |> Plug.Conn.send_resp(200, "Ok.")
        end
      end)

      assert :ok = QBittorrent.cancel_download("abc", client)
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "test_connection/1" do
    test "GETs /api/v2/app/version and returns :ok on 200", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v2/app/version"
        Plug.Conn.send_resp(conn, 200, "v4.6.0")
      end)

      assert :ok = QBittorrent.test_connection(client)
    end

    test "returns http_error on a 500 response", %{client: client} do
      Req.Test.stub(:qbittorrent, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:error, {:http_error, 500}} = QBittorrent.test_connection(client)
    end

    test "re-auths on 403 then retries", %{client: client} do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/app/version"} ->
            n = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if n == 0 do
              Plug.Conn.send_resp(conn, 403, "Forbidden")
            else
              Plug.Conn.send_resp(conn, 200, "v4.6.0")
            end

          {"POST", "/api/v2/auth/login"} ->
            conn
            |> Plug.Conn.put_resp_header("set-cookie", "SID=xyz")
            |> Plug.Conn.send_resp(200, "Ok.")
        end
      end)

      assert :ok = QBittorrent.test_connection(client)
      assert :counters.get(counter, 1) == 2
    end
  end
end
