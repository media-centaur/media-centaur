defmodule MediaCentaur.Downloads.DownloadClient.QBittorrentTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient.QBittorrent
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Secret

  # The driver is a function of its slot config; the test config routes
  # its requests through the `:qbittorrent` Req.Test stub.
  setup do
    Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, []) end)

    # A session cookie obtained by an earlier test must not decide this one.
    :persistent_term.erase({QBittorrent, :cookie})

    config = %ClientConfig{
      protocol: :torrent,
      type: "qbittorrent",
      url: "http://qbit.test",
      username: "alice",
      password: Secret.wrap("s3cret")
    }

    {:ok, config: config}
  end

  describe "auth retry on 403" do
    test "calls /api/v2/auth/login with form-encoded creds, then retries", %{config: config} do
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
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "username=alice&password=s3cret"

            conn
            |> Plug.Conn.put_resp_header("set-cookie", "SID=abc123; HttpOnly; SameSite=Strict")
            |> Plug.Conn.send_resp(200, "Ok.")
        end
      end)

      assert :ok = QBittorrent.test_connection(config)
      # 1st version call (403), then login, then retry version (200)
      assert :counters.get(counter, 1) == 2
    end

    test "returns :auth_failed when login returns 403", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/app/version"} ->
            Plug.Conn.send_resp(conn, 403, "Forbidden")

          {"POST", "/api/v2/auth/login"} ->
            Plug.Conn.send_resp(conn, 403, "Fails.")
        end
      end)

      assert {:error, :auth_failed} = QBittorrent.test_connection(config)
    end

    test "returns :auth_failed when login returns 200 but no SID cookie", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/app/version"} ->
            Plug.Conn.send_resp(conn, 403, "Forbidden")

          {"POST", "/api/v2/auth/login"} ->
            Plug.Conn.send_resp(conn, 200, "Ok.")
        end
      end)

      assert {:error, :auth_failed} = QBittorrent.test_connection(config)
    end
  end

  describe "sync_maindata/2" do
    test "GETs /api/v2/sync/maindata with rid", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v2/sync/maindata"
        assert conn.params == %{"rid" => "0"}

        Req.Test.json(conn, %{
          "rid" => 1,
          "full_update" => true,
          "torrents" => %{}
        })
      end)

      assert {:ok, %{"rid" => 1, "full_update" => true}} =
               QBittorrent.sync_maindata(config, 0)
    end

    test "passes a non-zero rid through to the request", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.params == %{"rid" => "42"}
        Req.Test.json(conn, %{"rid" => 43})
      end)

      assert {:ok, %{"rid" => 43}} = QBittorrent.sync_maindata(config, 42)
    end

    test "re-auths on 403 then retries", %{config: config} do
      counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/sync/maindata"} ->
            n = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if n == 0 do
              Plug.Conn.send_resp(conn, 403, "Forbidden")
            else
              Req.Test.json(conn, %{"rid" => 1, "full_update" => true, "torrents" => %{}})
            end

          {"POST", "/api/v2/auth/login"} ->
            conn
            |> Plug.Conn.put_resp_header("set-cookie", "SID=xyz")
            |> Plug.Conn.send_resp(200, "Ok.")
        end
      end)

      assert {:ok, %{"rid" => 1}} = QBittorrent.sync_maindata(config, 0)
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "cancel_download/2" do
    test "POSTs /api/v2/torrents/delete with hash and deleteFiles=true", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v2/torrents/delete"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == "hashes=abc123&deleteFiles=true"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert :ok = QBittorrent.cancel_download(config, "abc123")
    end

    test "returns http_error tuple on non-200, non-403 responses", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:error, {:http_error, 500, _}} = QBittorrent.cancel_download(config, "abc")
    end

    test "re-auths on 403 then retries the delete", %{config: config} do
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

      assert :ok = QBittorrent.cancel_download(config, "abc")
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "test_connection/1" do
    test "GETs /api/v2/app/version and returns :ok on 200", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v2/app/version"
        Plug.Conn.send_resp(conn, 200, "v4.6.0")
      end)

      assert :ok = QBittorrent.test_connection(config)
    end

    test "returns http_error on a 500 response", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:error, {:http_error, 500}} = QBittorrent.test_connection(config)
    end

    test "re-auths on 403 then retries", %{config: config} do
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

      assert :ok = QBittorrent.test_connection(config)
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "sync/2 (DownloadClient sync contract)" do
    defp maindata_full(rid) do
      %{
        "rid" => rid,
        "full_update" => true,
        "torrents" => %{
          "hash-a" => %{
            "name" => "Sample.Show.S01E01.1080p.WEB-DL.mkv",
            "state" => "downloading",
            "size" => 1000,
            "amount_left" => 500,
            "progress" => 0.5
          }
        },
        "server_state" => %{"dl_info_speed" => 100}
      }
    end

    test "nil driver state starts the conversation at rid=0 and returns items + state", %{
      config: config
    } do
      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.request_path == "/api/v2/sync/maindata"
        assert conn.params == %{"rid" => "0"}
        Req.Test.json(conn, maindata_full(7))
      end)

      assert {:ok, result} = QBittorrent.sync(config, nil)
      assert [%QueueItem{id: "hash-a"}] = result.items
      assert result.movement?
      assert result.summary =~ "rid=7"
    end

    test "the returned driver state carries the rid conversation forward", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, maindata_full(7)) end)
      {:ok, first} = QBittorrent.sync(config, nil)

      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.params == %{"rid" => "7"}
        # Steady-state echo: full update repeating the same set.
        Req.Test.json(conn, maindata_full(8))
      end)

      assert {:ok, second} = QBittorrent.sync(config, first.driver_state)
      assert [%QueueItem{id: "hash-a"}] = second.items
      refute second.movement?, "a full-update echo with a stable set is not movement"
    end

    test "a partial delta merges into the mirror and counts as movement", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, maindata_full(7)) end)
      {:ok, first} = QBittorrent.sync(config, nil)

      Req.Test.stub(:qbittorrent, fn conn ->
        Req.Test.json(conn, %{
          "rid" => 8,
          "torrents" => %{"hash-a" => %{"progress" => 0.9}}
        })
      end)

      assert {:ok, second} = QBittorrent.sync(config, first.driver_state)
      assert [%QueueItem{id: "hash-a", progress: progress}] = second.items
      assert progress > 0.5
      assert second.movement?
    end

    test "an error resets the conversation so the next poll is a full update", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, maindata_full(7)) end)
      {:ok, first} = QBittorrent.sync(config, nil)

      Req.Test.stub(:qbittorrent, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
      assert {:error, _reason, recovery_state} = QBittorrent.sync(config, first.driver_state)

      Req.Test.stub(:qbittorrent, fn conn ->
        assert conn.params == %{"rid" => "0"}
        Req.Test.json(conn, maindata_full(9))
      end)

      assert {:ok, _recovered} = QBittorrent.sync(config, recovery_state)
    end
  end
end
