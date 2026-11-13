defmodule MediaCentaur.Downloads.DownloadClient.ConformanceTest do
  @moduledoc """
  The `DownloadClient` contract, run once per driver.

  Everything above a driver (`QueueMonitor`, `Connectivity`, cancel
  routing) reads these client-neutral outcomes and nothing else, so a
  driver that answers one of them differently breaks the callers without
  failing its own wire-level tests. A driver is listed in `@drivers` with
  the client's answers for each situation; a module that implements the
  behaviour and is not listed fails the first test here.
  """
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient
  alias MediaCentaur.Downloads.DownloadClient.{QBittorrent, SABnzbd, SyncResult}
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Secret

  @drivers [QBittorrent, SABnzbd]

  # --- qBittorrent's side of each situation --------------------------------

  defp config(QBittorrent) do
    %ClientConfig{
      protocol: :torrent,
      type: "qbittorrent",
      url: "http://qbit.test",
      username: "alice",
      password: Secret.wrap("s3cret")
    }
  end

  defp config(SABnzbd) do
    %ClientConfig{
      protocol: :usenet,
      type: "sabnzbd",
      url: "http://sab.test",
      api_key: Secret.wrap("sab-key")
    }
  end

  defp stub_name(QBittorrent), do: :qbittorrent
  defp stub_name(SABnzbd), do: :sabnzbd

  # One download, `left` of 1000 units still to fetch.
  defp answer(QBittorrent, {:one_download, left}, conn) do
    case conn.request_path do
      "/api/v2/app/version" ->
        Plug.Conn.send_resp(conn, 200, "v5.0.0")

      "/api/v2/sync/maindata" ->
        Req.Test.json(conn, maindata(conn.params["rid"], left))

      "/api/v2/torrents/files" ->
        Req.Test.json(conn, [%{"name" => "Sample.Show.S01E01.1080p.WEB-DL/episode.mkv", "size" => 1000}])

      "/api/v2/torrents/delete" ->
        Plug.Conn.send_resp(conn, 200, "")
    end
  end

  defp answer(QBittorrent, {:progressed_to, left}, conn) do
    Req.Test.json(conn, %{
      "rid" => 2,
      "torrents" => %{"hash-a" => %{"amount_left" => left, "progress" => (1000 - left) / 1000}}
    })
  end

  defp answer(QBittorrent, :credentials_rejected, conn) do
    case conn.request_path do
      "/api/v2/auth/login" -> Plug.Conn.send_resp(conn, 403, "Fails.")
      _other -> Plug.Conn.send_resp(conn, 403, "Forbidden")
    end
  end

  # --- SABnzbd's side of each situation ------------------------------------

  defp answer(SABnzbd, {:one_download, left}, conn) do
    case conn.params["mode"] do
      "queue" ->
        slot = %{
          "nzo_id" => "SABnzbd_nzo_a",
          "filename" => "Sample.Show.S01E01.1080p.WEB-DL",
          "status" => "Downloading",
          "mb" => "1000.0",
          "mbleft" => "#{left}.0",
          "percentage" => "#{div(1000 - left, 10)}",
          "timeleft" => "0:02:00",
          "cat" => "tv"
        }

        Req.Test.json(conn, %{"queue" => %{"slots" => [slot]}})

      "history" ->
        Req.Test.json(conn, %{"history" => %{"slots" => []}})
    end
  end

  defp answer(SABnzbd, {:progressed_to, left}, conn), do: answer(SABnzbd, {:one_download, left}, conn)

  defp answer(SABnzbd, :credentials_rejected, conn) do
    Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
  end

  defp answer(_driver, :server_error, conn), do: Plug.Conn.send_resp(conn, 500, "boom")

  # qBittorrent sends the whole queue to a client that has no bookmark
  # (`rid=0`) and only what changed after that — nothing, for a queue
  # that stood still.
  defp maindata("0", left) do
    %{
      "rid" => 1,
      "full_update" => true,
      "torrents" => %{
        "hash-a" => %{
          "name" => "Sample.Show.S01E01.1080p.WEB-DL",
          "state" => "downloading",
          "size" => 1000,
          "amount_left" => left,
          "progress" => (1000 - left) / 1000
        }
      }
    }
  end

  defp maindata(_rid, _left), do: %{"rid" => 2}

  defp client_answers(driver, situation) do
    Req.Test.stub(stub_name(driver), &answer(driver, situation, &1))
  end

  setup do
    # A session cookie obtained by an earlier test must not decide this one.
    :persistent_term.erase({QBittorrent, :cookie})
    :ok
  end

  test "every module implementing the behaviour is held to this contract" do
    {:ok, modules} = :application.get_key(:media_centaur, :modules)

    implementers =
      Enum.filter(modules, fn module ->
        DownloadClient in (module.module_info(:attributes)
                           |> Keyword.get_values(:behaviour)
                           |> List.flatten())
      end)

    assert Enum.sort(implementers) == Enum.sort(@drivers)
  end

  for driver <- @drivers do
    describe "#{inspect(driver)}" do
      @describetag driver: driver

      test "test_connection/1 is :ok against a client that answers", %{driver: driver} do
        client_answers(driver, {:one_download, 500})

        assert :ok = driver.test_connection(config(driver))
      end

      test "test_connection/1 names rejected credentials :auth_failed", %{driver: driver} do
        client_answers(driver, :credentials_rejected)

        assert {:error, :auth_failed} = driver.test_connection(config(driver))
      end

      test "test_connection/1 is an error when the client fails", %{driver: driver} do
        client_answers(driver, :server_error)

        assert {:error, reason} = driver.test_connection(config(driver))
        refute reason == :auth_failed
      end

      test "sync/2 from no state returns the queue as items of the driver's protocol", %{driver: driver} do
        client_answers(driver, {:one_download, 500})
        protocol = config(driver).protocol

        assert {:ok, %SyncResult{items: [item], movement?: true}} = driver.sync(config(driver), nil)

        assert %QueueItem{
                 title: "Sample.Show.S01E01.1080p.WEB-DL",
                 state: :downloading,
                 protocol: ^protocol,
                 progress: progress
               } = item

        assert is_binary(item.id)
        assert_in_delta progress, 50.0, 0.1
      end

      test "sync/2 with the returned state reports no movement for an unchanged queue", %{driver: driver} do
        client_answers(driver, {:one_download, 500})

        {:ok, first} = driver.sync(config(driver), nil)

        assert {:ok, %SyncResult{items: [_item], movement?: false}} =
                 driver.sync(config(driver), first.driver_state)
      end

      test "sync/2 reports movement when a download progressed", %{driver: driver} do
        client_answers(driver, {:one_download, 500})
        {:ok, first} = driver.sync(config(driver), nil)

        client_answers(driver, {:progressed_to, 100})

        assert {:ok, %SyncResult{movement?: true, items: [%QueueItem{progress: progress}]}} =
                 driver.sync(config(driver), first.driver_state)

        assert_in_delta progress, 90.0, 0.1
      end

      test "sync/2 answers a failing client with a state the next tick recovers from", %{driver: driver} do
        client_answers(driver, {:one_download, 500})
        {:ok, first} = driver.sync(config(driver), nil)

        client_answers(driver, :server_error)
        assert {:error, _reason, recovery_state} = driver.sync(config(driver), first.driver_state)

        client_answers(driver, {:one_download, 500})
        assert {:ok, %SyncResult{items: [_item]}} = driver.sync(config(driver), recovery_state)
      end

      test "sync/2 names rejected credentials :auth_failed", %{driver: driver} do
        client_answers(driver, :credentials_rejected)

        assert {:error, :auth_failed, _state} = driver.sync(config(driver), nil)
      end

      test "cancel_download/2 is :ok for an id the client holds", %{driver: driver} do
        client_answers(driver, {:one_download, 500})
        {:ok, %SyncResult{items: [item]}} = driver.sync(config(driver), nil)

        assert :ok = driver.cancel_download(config(driver), item.id)
      end

      test "list_files/2 is the download's files, or :unsupported for a client that cannot say", %{
        driver: driver
      } do
        client_answers(driver, {:one_download, 500})
        {:ok, %SyncResult{items: [item]}} = driver.sync(config(driver), nil)

        case driver.list_files(config(driver), item.id) do
          {:ok, files} ->
            assert [%{name: "Sample.Show.S01E01.1080p.WEB-DL/episode.mkv", size: 1000}] = files

          {:error, reason} ->
            assert reason == :unsupported
        end
      end

      test "cancel_download/2 is an error when the client fails", %{driver: driver} do
        client_answers(driver, :server_error)

        assert {:error, _reason} = driver.cancel_download(config(driver), "any-id")
      end
    end
  end
end
