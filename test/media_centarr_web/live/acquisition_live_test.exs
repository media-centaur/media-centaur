defmodule MediaCentarrWeb.AcquisitionLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Secret

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentarr.Config, :config})

    :persistent_term.put(
      {MediaCentarr.Config, :config},
      Map.merge(config, %{
        prowlarr_url: "http://prowlarr.test",
        prowlarr_api_key: Secret.wrap("test-key"),
        download_client_type: "qbittorrent",
        download_client_url: "http://qb.test"
      })
    )

    # The /download page is now gated on explicit green connection tests
    # for Prowlarr (and the queue section on the download client). Seed
    # both so tests of other behaviors see the fully-enabled page.
    Capabilities.save_test_result(:prowlarr, :ok)
    Capabilities.save_test_result(:download_client, :ok)

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentarr.Config, :config}, config)
    end)

    :ok
  end

  describe "mount" do
    test "redirects to library when Prowlarr is not configured", %{conn: conn} do
      config = :persistent_term.get({MediaCentarr.Config, :config})

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        Map.merge(config, %{prowlarr_url: nil, prowlarr_api_key: nil})
      )

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/download")
    end

    test "redirects to library when Prowlarr is configured but untested", %{conn: conn} do
      Capabilities.clear_test_result(:prowlarr)

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/download")
    end

    test "hides the active-downloads queue when the download client is untested",
         %{conn: conn} do
      Capabilities.clear_test_result(:download_client)

      {:ok, _view, html} = live(conn, ~p"/download")

      refute html =~ "Downloading"
      assert html =~ "Connect a download client"
    end

    test "renders the download page when Prowlarr is configured", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/download")

      assert html =~ "Download"
      assert html =~ "data-page-behavior=\"download\""
      assert html =~ "data-nav-default-zone=\"download\""
    end
  end

  describe "query_change" do
    test "updates expansion preview for valid syntax", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      html =
        view
        |> form("form[phx-change='query_change']", query: "The Pitt S02E{00-09}")
        |> render_change()

      assert html =~ "10 queries in parallel"
    end

    test "shows error for invalid brace syntax", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      html =
        view
        |> form("form[phx-change='query_change']", query: "foo {a-}")
        |> render_change()

      assert html =~ "Invalid brace syntax"
    end
  end

  describe "submit_search and grab_selected" do
    test "renders results, lets user select, and submits a grab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      # Allow the LiveView (and tasks it spawns via $callers) to use the stub.
      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Movie.A.2024.2160p.BluRay",
                "guid" => "guid-a",
                "indexerId" => 1,
                "seeders" => 50,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/release" ->
            Req.Test.json(conn, %{"approved" => true})

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      html = wait_until(view, &(&1 =~ "Movie.A.2024.2160p.BluRay"))
      # Default selection should be applied — Grab button shows count of 1
      assert html =~ "Grab 1 selected"

      # Submit the grab
      view
      |> element("button[phx-click='grab_selected']")
      |> render_click()

      html = wait_until(view, &(&1 =~ "1 grab(s) submitted"))
      assert html =~ "1 grab(s) submitted"
    end
  end

  describe "cancel download" do
    setup do
      Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, []) end)

      qbit_client =
        Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")

      :persistent_term.put({QBittorrent, :client}, qbit_client)

      config = :persistent_term.get({MediaCentarr.Config, :config})

      :persistent_term.put(
        {MediaCentarr.Config, :config},
        Map.merge(config, %{
          download_client_type: "qbittorrent",
          download_client_url: "http://qbit.test",
          download_client_username: "alice",
          download_client_password: Secret.wrap("s3cret")
        })
      )

      on_exit(fn ->
        :persistent_term.put({MediaCentarr.Config, :config}, config)
        QBittorrent.invalidate_client()
      end)

      :ok
    end

    test "confirming the modal calls qBittorrent delete and clears the row", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/torrents/info"} ->
            n = :counters.get(delete_counter, 1)

            if n > 0 do
              Req.Test.json(conn, [])
            else
              Req.Test.json(conn, [
                %{
                  "hash" => "hash-a",
                  "name" => "Movie.Test.2024",
                  "state" => "downloading",
                  "size" => 100,
                  "amount_left" => 50,
                  "progress" => 0.5,
                  "eta" => 120,
                  "category" => ""
                }
              ])
            end

          {"POST", "/api/v2/torrents/delete"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "hashes=hash-a&deleteFiles=true"
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      # Force a poll after allow is granted (the mount-triggered poll may have
      # raced with the allow call).
      send(view.pid, :poll_queue)
      html = wait_until(view, &(&1 =~ "Movie.Test.2024"))
      assert html =~ "phx-click=\"cancel_download_prompt\""

      # Open the confirmation modal.
      html =
        view
        |> element("button[phx-click='cancel_download_prompt']")
        |> render_click()

      assert html =~ "Cancel download?"

      # Confirm.
      view
      |> element("button[phx-click='cancel_download_confirm']")
      |> render_click()

      assert :counters.get(delete_counter, 1) == 1
      # Row is gone (no more cancel-prompt button for that hash) and modal closed.
      html = wait_until(view, fn h -> not (h =~ "phx-value-id=\"hash-a\"") end)
      assert html =~ "No active downloads"
      refute html =~ "Cancel download?"
    end

    test "dismissing the modal does not call qBittorrent delete", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/torrents/info"} ->
            Req.Test.json(conn, [
              %{
                "hash" => "hash-b",
                "name" => "Show.S01E01",
                "state" => "downloading",
                "size" => 100,
                "amount_left" => 50,
                "progress" => 0.5,
                "eta" => 120,
                "category" => ""
              }
            ])

          {"POST", "/api/v2/torrents/delete"} ->
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)
      send(view.pid, :poll_queue)
      wait_until(view, &(&1 =~ "Show.S01E01"))

      html =
        view
        |> element("button[phx-click='cancel_download_prompt']")
        |> render_click()

      assert html =~ "Cancel download?"

      html =
        view
        |> element("button[phx-click='cancel_download_cancel']")
        |> render_click()

      refute html =~ "Cancel download?"
      assert :counters.get(delete_counter, 1) == 0
    end
  end

  # Polls render(view) until `predicate.(html)` returns true or the timeout
  # elapses. Used to wait for async Task.Supervisor work to deliver
  # {:search_result, _, _} / grab completion messages back to the LiveView.
  defp wait_until(view, predicate, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(view, predicate, deadline)
  end

  defp do_wait_until(view, predicate, deadline) do
    html = render(view)

    cond do
      predicate.(html) ->
        html

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("wait_until timed out")

      true ->
        Process.sleep(10)
        do_wait_until(view, predicate, deadline)
    end
  end
end
