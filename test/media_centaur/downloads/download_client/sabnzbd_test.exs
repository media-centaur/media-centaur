defmodule MediaCentaur.Downloads.DownloadClient.SABnzbdTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient.SABnzbd
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Secret

  # The driver is a function of its slot config; the test config routes
  # its requests through the `:sabnzbd` Req.Test stub.
  setup do
    Req.Test.stub(:sabnzbd, fn conn -> Req.Test.json(conn, %{}) end)

    config = %ClientConfig{
      protocol: :usenet,
      type: "sabnzbd",
      url: "http://sab.test",
      api_key: Secret.wrap("sab-key")
    }

    {:ok, config: config}
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

  describe "request contract" do
    test "every call GETs /api with the api key and json output, and slots parse into items", %{
      config: config
    } do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api"
        assert conn.params["apikey"] == "sab-key"
        assert conn.params["output"] == "json"

        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([history_slot(%{})]))
        end
      end)

      assert {:ok, %{items: [queue_item, history_item]}} = SABnzbd.sync(config, nil)
      assert %QueueItem{id: "SABnzbd_nzo_q1", state: :downloading, protocol: :usenet} = queue_item
      assert %QueueItem{id: "SABnzbd_nzo_h1", state: :completed} = history_item
    end

    test "a non-auth API error surfaces as an api_error tuple", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "not implemented"})
      end)

      assert {:error, {:api_error, "not implemented"}} = SABnzbd.test_connection(config)
    end
  end

  describe "test_connection/1" do
    test "uses a keyed endpoint so a wrong API key fails the test", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.params["mode"] == "queue"
        assert conn.params["apikey"] == "sab-key"
        Req.Test.json(conn, queue_response([]))
      end)

      assert :ok = SABnzbd.test_connection(config)
    end

    test "returns :auth_failed for a rejected key", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
      end)

      assert {:error, :auth_failed} = SABnzbd.test_connection(config)
    end
  end

  describe "cancel_download/2" do
    test "deletes the queue entry including files", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        assert conn.params["mode"] == "queue"
        assert conn.params["name"] == "delete"
        assert conn.params["value"] == "SABnzbd_nzo_q1"
        assert conn.params["del_files"] == "1"
        Req.Test.json(conn, %{"status" => true})
      end)

      assert :ok = SABnzbd.cancel_download(config, "SABnzbd_nzo_q1")
    end

    # A terminal job (Completed/Failed) lives in SABnzbd's history, not its
    # queue. The queue delete matches nothing and reports `status: false` —
    # so the driver must fall back to a history delete, or the errored entry
    # can never be removed and re-renders on every poll.
    test "falls back to a history delete when the id is not in the live queue", %{config: config} do
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

      assert :ok = SABnzbd.cancel_download(config, "nzo_failed_1")
      # The history delete must actually fire — a green :ok alone would also
      # pass against the queue-only bug (the no-op queue delete returns :ok).
      assert_receive {:history_delete, "delete", "nzo_failed_1", "1"}
    end

    # Cleanup cancels can arrive after the job already left both stores
    # (e.g. the user clicked twice). Deleting an absent id is the desired
    # end state, so it resolves :ok rather than erroring.
    test "is idempotent — an id in neither queue nor history still resolves :ok", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "nzo_ids" => []})
      end)

      assert :ok = SABnzbd.cancel_download(config, "already_gone")
    end

    test "returns http_error tuple on non-200 responses", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, {:http_error, 500, _}} = SABnzbd.cancel_download(config, "x")
    end
  end

  describe "sync/2 (DownloadClient sync contract)" do
    test "fetches queue + history each tick and returns the merged items", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([history_slot(%{})]))
        end
      end)

      assert {:ok, result} = SABnzbd.sync(config, nil)

      assert [%QueueItem{id: "SABnzbd_nzo_q1"}, %QueueItem{id: "SABnzbd_nzo_h1"}] = result.items
      assert result.movement?, "first sync from a fresh bookmark counts as movement"
      assert result.summary =~ "sabnzbd"
    end

    test "a steady-state echo is not movement", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([history_slot(%{})]))
        end
      end)

      {:ok, first} = SABnzbd.sync(config, nil)
      assert {:ok, second} = SABnzbd.sync(config, first.driver_state)
      refute second.movement?
    end

    test "progress on an item counts as movement", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" -> Req.Test.json(conn, queue_response([queue_slot(%{})]))
          "history" -> Req.Test.json(conn, history_response([]))
        end
      end)

      {:ok, first} = SABnzbd.sync(config, nil)

      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "queue" ->
            Req.Test.json(conn, queue_response([queue_slot(%{"mbleft" => "10.0"})]))

          "history" ->
            Req.Test.json(conn, history_response([]))
        end
      end)

      assert {:ok, second} = SABnzbd.sync(config, first.driver_state)
      assert second.movement?
    end

    test "an error returns the bookmark to carry forward", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, {:http_error, 500, _}, _bookmark} = SABnzbd.sync(config, nil)
    end

    test "an auth failure surfaces as :auth_failed so connectivity grades it", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
      end)

      assert {:error, :auth_failed, _bookmark} = SABnzbd.sync(config, nil)
    end
  end
end
