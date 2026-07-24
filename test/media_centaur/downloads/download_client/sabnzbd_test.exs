defmodule MediaCentaur.Downloads.DownloadClient.SABnzbdTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Downloads.DownloadClient.SABnzbd
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.{Config, Secret}

  setup do
    original_config = :persistent_term.get({Config, :config}, %{})

    :persistent_term.put(
      {Config, :config},
      Map.merge(original_config, %{
        usenet_download_client_url: "http://sab.test",
        usenet_download_client_api_key: Secret.wrap("sab-key")
      })
    )

    Req.Test.stub(:sabnzbd, fn conn -> Req.Test.json(conn, %{}) end)
    client = Req.new(plug: {Req.Test, :sabnzbd}, retry: false, base_url: "http://sab.test")

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original_config)
      SABnzbd.invalidate_client()
    end)

    {:ok, client: client}
  end

  defp queue_response(slots) do
    %{"queue" => %{"slots" => slots}}
  end

  defp history_response(slots) do
    %{"history" => %{"slots" => slots}}
  end

  defp queue_slot(overrides) do
    Map.merge(
      %{
        "nzo_id" => "SABnzbd_nzo_q1",
        "filename" => "Sample.Show.S01E01.1080p.WEB-DL",
        "status" => "Downloading",
        "mb" => "100.0",
        "mbleft" => "40.0",
        "percentage" => "60",
        "timeleft" => "0:02:00",
        "cat" => "tv"
      },
      overrides
    )
  end

  defp history_slot(overrides) do
    Map.merge(
      %{
        "nzo_id" => "SABnzbd_nzo_h1",
        "name" => "Sample.Show.S01E02.1080p.WEB-DL",
        "status" => "Completed",
        "storage" => "/downloads/complete/Sample.Show.S01E02.1080p.WEB-DL",
        "bytes" => 100,
        "category" => "tv",
        "fail_message" => ""
      },
      overrides
    )
  end

  describe "list_downloads/2" do
    test ":active GETs mode=queue with the api key and parses slots", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api"
        assert conn.params["mode"] == "queue"
        assert conn.params["apikey"] == "sab-key"
        assert conn.params["output"] == "json"
        Req.Test.json(conn, queue_response([queue_slot(%{})]))
      end)

      assert {:ok, [%QueueItem{} = item]} = SABnzbd.list_downloads(:active, client)
      assert item.id == "SABnzbd_nzo_q1"
      assert item.state == :downloading
      assert item.protocol == :usenet
    end

    test ":completed GETs mode=history and returns only Completed entries", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.params["mode"] == "history"

        Req.Test.json(
          conn,
          history_response([
            history_slot(%{}),
            history_slot(%{"nzo_id" => "SABnzbd_nzo_h2", "status" => "Failed"})
          ])
        )
      end)

      assert {:ok, [%QueueItem{id: "SABnzbd_nzo_h1", state: :completed}]} =
               SABnzbd.list_downloads(:completed, client)
    end

    test ":all merges queue and history items", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([history_slot(%{})]))
        end
      end)

      assert {:ok, items} = SABnzbd.list_downloads(:all, client)
      assert Enum.map(items, & &1.id) == ["SABnzbd_nzo_q1", "SABnzbd_nzo_h1"]
    end

    test "an incorrect API key maps to :auth_failed — SABnzbd reports it as 200 + error JSON", %{
      client: client
    } do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
      end)

      assert {:error, :auth_failed} = SABnzbd.list_downloads(:active, client)
    end

    test "a non-auth API error surfaces as an api_error tuple", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "not implemented"})
      end)

      assert {:error, {:api_error, "not implemented"}} = SABnzbd.list_downloads(:active, client)
    end

    test "returns http_error tuple on non-200 responses", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, {:http_error, 500, _}} = SABnzbd.list_downloads(:active, client)
    end
  end

  describe "test_connection/1" do
    test "uses a keyed endpoint so a wrong API key fails the test", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.params["mode"] == "queue"
        assert conn.params["apikey"] == "sab-key"
        Req.Test.json(conn, queue_response([]))
      end)

      assert :ok = SABnzbd.test_connection(client)
    end

    test "returns :auth_failed for a rejected key", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
      end)

      assert {:error, :auth_failed} = SABnzbd.test_connection(client)
    end
  end

  describe "cancel_download/2" do
    test "deletes the queue entry including files", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.params["mode"] == "queue"
        assert conn.params["name"] == "delete"
        assert conn.params["value"] == "SABnzbd_nzo_q1"
        assert conn.params["del_files"] == "1"
        Req.Test.json(conn, %{"status" => true})
      end)

      assert :ok = SABnzbd.cancel_download("SABnzbd_nzo_q1", client)
    end

    # A terminal job (Completed/Failed) lives in SABnzbd's history, not its
    # queue. The queue delete matches nothing and reports `status: false` —
    # so the driver must fall back to a history delete, or the errored entry
    # can never be removed and re-renders on every poll.
    test "falls back to a history delete when the id is not in the live queue", %{client: client} do
      parent = self()

      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" ->
            Req.Test.json(conn, %{"status" => false, "nzo_ids" => []})

          "history" ->
            send(
              parent,
              {:history_delete, conn.params["name"], conn.params["value"], conn.params["del_files"]}
            )

            Req.Test.json(conn, %{"status" => true})
        end
      end)

      assert :ok = SABnzbd.cancel_download("nzo_failed_1", client)
      # The history delete must actually fire — a green :ok alone would also
      # pass against the queue-only bug (the no-op queue delete returns :ok).
      assert_receive {:history_delete, "delete", "nzo_failed_1", "1"}
    end

    # Cleanup cancels can arrive after the job already left both stores
    # (e.g. the user clicked twice). Deleting an absent id is the desired
    # end state, so it resolves :ok rather than erroring.
    test "is idempotent — an id in neither queue nor history still resolves :ok", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "nzo_ids" => []})
      end)

      assert :ok = SABnzbd.cancel_download("already_gone", client)
    end

    test "returns http_error tuple on non-200 responses", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, {:http_error, 500, _}} = SABnzbd.cancel_download("x", client)
    end
  end

  describe "sync/2 (DownloadClient sync contract)" do
    test "fetches queue + history each tick and returns the merged items", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([history_slot(%{})]))
        end
      end)

      assert {:ok, result} = SABnzbd.sync(nil, client)

      assert [%QueueItem{id: "SABnzbd_nzo_q1"}, %QueueItem{id: "SABnzbd_nzo_h1"}] = result.items
      assert result.movement?, "first sync from a fresh bookmark counts as movement"
      assert result.summary =~ "sabnzbd"
    end

    test "a steady-state echo is not movement", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([history_slot(%{})]))
        end
      end)

      {:ok, first} = SABnzbd.sync(nil, client)
      assert {:ok, second} = SABnzbd.sync(first.driver_state, client)
      refute second.movement?
    end

    test "progress on an item counts as movement", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([]))
        end
      end)

      {:ok, first} = SABnzbd.sync(nil, client)

      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" ->
            Req.Test.json(conn, queue_response([queue_slot(%{"mbleft" => "10.0"})]))

          "history" ->
            Req.Test.json(conn, history_response([]))
        end
      end)

      assert {:ok, second} = SABnzbd.sync(first.driver_state, client)
      assert second.movement?
    end

    test "an error returns the bookmark to carry forward", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, {:http_error, 500, _}, _bookmark} = SABnzbd.sync(nil, client)
    end

    test "an auth failure surfaces as :auth_failed so connectivity grades it", %{client: client} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
      end)

      assert {:error, :auth_failed, _bookmark} = SABnzbd.sync(nil, client)
    end
  end
end
