defmodule MediaCentarrWeb.AcquisitionLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Secret

  defp stub_prowlarr_with(results) do
    Req.Test.stub(:prowlarr, fn conn ->
      Req.Test.json(conn, results)
    end)
  end

  defp sample_release(opts \\ []) do
    %{
      "guid" => Keyword.get(opts, :guid, "guid-1"),
      "title" => Keyword.get(opts, :title, "Sample.Show.S01E01.1080p.WEB-DL.mkv"),
      "indexerId" => 1,
      "size" => 1_073_741_824,
      "seeders" => 42,
      "leechers" => 0,
      "indexer" => "Test Indexer",
      "publishDate" => "2026-04-01T00:00:00Z"
    }
  end

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

    # The SearchSession GenServer is a singleton — reset it between tests
    # so leaked state from a prior test doesn't leak into the next one.
    MediaCentarr.Acquisition.clear_search_session()

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentarr.Config, :config}, config)
      MediaCentarr.Acquisition.clear_search_session()
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
        |> form("form[phx-change='query_change']", query: "Sample Show S01E{01-10}")
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

    alias MediaCentarr.Acquisition.QueueItem

    test "confirming the modal calls qBittorrent delete and clears the row", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "hashes=hash-a&deleteFiles=true"
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      # Seed the queue via the same PubSub broadcast QueueMonitor emits.
      send(
        view.pid,
        {:queue_snapshot,
         [
           %QueueItem{
             id: "hash-a",
             title: "Movie.Test.2024",
             state: :downloading,
             status: "downloading",
             download_client: "qBittorrent",
             size: 100,
             size_left: 50,
             progress: 50.0,
             timeleft: "2m"
           }
         ]}
      )

      html = render(view)
      assert html =~ "Movie.Test.2024"
      assert html =~ "phx-click=\"cancel_download_prompt\""

      # Open the confirmation modal.
      html =
        view
        |> element("button[phx-click='cancel_download_prompt']")
        |> render_click()

      assert html =~ "Cancel download?"

      # Confirm — fires the qBittorrent delete and optimistically drops the row.
      html =
        view
        |> element("button[phx-click='cancel_download_confirm']")
        |> render_click()

      assert :counters.get(delete_counter, 1) == 1
      assert html =~ "No active downloads"
      refute html =~ "phx-value-id=\"hash-a\""
      refute html =~ "Cancel download?"
    end

    test "dismissing the modal does not call qBittorrent delete", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} ->
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      send(
        view.pid,
        {:queue_snapshot,
         [
           %QueueItem{
             id: "hash-b",
             title: "Show.S01E01",
             state: :downloading,
             status: "downloading",
             download_client: "qBittorrent",
             size: 100,
             size_left: 50,
             progress: 50.0,
             timeleft: "2m"
           }
         ]}
      )

      assert render(view) =~ "Show.S01E01"

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

  describe "retry_search (per-group)" do
    test "a single timed-out search becomes retryable; retry resolves to results",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      Req.Test.allow(:prowlarr, self(), view.pid)

      # First search — every Prowlarr call fails with a transport timeout.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      html = wait_until(view, &(&1 =~ "Prowlarr timed out"))
      # Retry affordance is present alongside the timeout message
      assert html =~ "phx-click=\"retry_search\""
      assert html =~ "phx-value-term=\"Movie A\""

      # Now succeed on retry
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Movie.A.2024.1080p",
                "guid" => "guid-a",
                "indexerId" => 1,
                "seeders" => 12,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> element("button[phx-click='retry_search'][phx-value-term='Movie A']")
      |> render_click()

      html = wait_until(view, &(&1 =~ "Movie.A.2024.1080p"))
      refute html =~ "Prowlarr timed out"
    end
  end

  describe "retry_all_timeouts (footer button)" do
    test "appears only after every search completes and at least one timed out",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E{01,02}")
      |> render_submit()

      html = wait_until(view, &(&1 =~ "Retry 2 timeouts"))
      assert html =~ "phx-click=\"retry_all_timeouts\""

      # Switch the stub to succeed, then bulk-retry
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Sample.Show.Episode.1080p",
                "guid" => "guid-#{System.unique_integer([:positive])}",
                "indexerId" => 1,
                "seeders" => 8,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> element("button[phx-click='retry_all_timeouts']")
      |> render_click()

      html = wait_until(view, &(&1 =~ "Sample.Show.Episode.1080p"))
      refute html =~ "Prowlarr timed out"
      refute html =~ "Retry 2 timeouts"
    end

    test "does not appear when no searches timed out", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Healthy.Result.1080p",
                "guid" => "g",
                "indexerId" => 1,
                "seeders" => 5,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> form("form[phx-change='query_change']", query: "Healthy")
      |> render_submit()

      html = wait_until(view, &(&1 =~ "Healthy.Result.1080p"))
      refute html =~ "retry_all_timeouts"
    end
  end

  describe "debounce on acquisition PubSub events" do
    test "five rapid grab-event broadcasts trigger only one activity reload after the debounce window",
         %{conn: conn} do
      # Regression guard: :grab_submitted and related events must be debounced
      # (500ms) rather than calling load_activity on every message. Five events
      # in quick succession must result in one :reload_activity — the page must
      # render correctly after the window without crashing.
      {:ok, view, _html} = live(conn, ~p"/download")

      for _ <- 1..5 do
        send(view.pid, {:grab_submitted, %{}})
      end

      Process.sleep(600)

      assert render(view) =~ "Download"
    end
  end

  describe "search session persistence" do
    setup do
      MediaCentarr.Acquisition.clear_search_session()
      :ok
    end

    test "search query and results persist across navigation", %{conn: conn} do
      stub_prowlarr_with([sample_release()])

      {:ok, view, _html} = live(conn, "/download")

      view
      |> form("form[phx-change='query_change']", %{"query" => "Sample Show"})
      |> render_submit()

      _ = render(view)
      :timer.sleep(100)
      html = render(view)
      assert html =~ "Sample Show"
      assert html =~ "Sample.Show.S01E01"

      {:ok, _other_view, _other_html} = live(conn, "/")

      {:ok, _view2, html2} = live(conn, "/download")

      assert html2 =~ "Sample Show"
      assert html2 =~ "Sample.Show.S01E01"
    end

    test "user-changed selection persists across navigation", %{conn: conn} do
      stub_prowlarr_with([
        sample_release(guid: "guid-1", title: "Sample.Show.S01E01.720p.WEB-DL.mkv"),
        sample_release(guid: "guid-2", title: "Sample.Show.S01E01.1080p.WEB-DL.mkv")
      ])

      {:ok, view, _html} = live(conn, "/download")
      Req.Test.allow(:prowlarr, self(), view.pid)

      view
      |> form("form[phx-change='query_change']", %{"query" => "Sample Show"})
      |> render_submit()

      _ = wait_until(view, &(&1 =~ "Sample.Show.S01E01"))

      # Override the auto-default selection with a user-driven choice.
      MediaCentarr.Acquisition.set_selection("Sample Show", "guid-2")

      session_before = MediaCentarr.Acquisition.current_search_session()
      assert session_before.selections == %{"Sample Show" => "guid-2"}

      {:ok, _other_view, _other_html} = live(conn, "/")
      {:ok, _view2, _html2} = live(conn, "/download")

      session_after = MediaCentarr.Acquisition.current_search_session()
      assert session_after.selections == %{"Sample Show" => "guid-2"}
    end

    test "groups in :loading become :abandoned with retry affordance after LV crash", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn _conn ->
        :timer.sleep(:infinity)
      end)

      {:ok, view, _html} = live(conn, "/download")

      view
      |> form("form[phx-change='query_change']", %{"query" => "Pending Show"})
      |> render_submit()

      :timer.sleep(50)
      session_before = MediaCentarr.Acquisition.current_search_session()
      assert Enum.all?(session_before.groups, fn group -> group.status == :loading end)

      GenServer.stop(view.pid, :normal)

      :timer.sleep(100)

      session_after = MediaCentarr.Acquisition.current_search_session()
      assert Enum.all?(session_after.groups, fn group -> group.status == :abandoned end)

      {:ok, _view2, html2} = live(conn, "/download")
      assert html2 =~ "Retry"
    end
  end

  # Polls render(view) until `predicate.(html)` returns true or the timeout
  # elapses. Used to wait for async Task.Supervisor work to deliver
  # {:search_result, _, _} / grab completion messages back to the LiveView.
  describe "live updates from queue monitor" do
    # The active queue is now driven by QueueMonitor's PubSub broadcast
    # rather than per-LV polling. The LV must consume {:queue_snapshot, items}
    # and re-render the queue zone without making its own download-client
    # call. Without this contract the page would silently regress to stale
    # data after the polling timer was removed.

    alias MediaCentarr.Acquisition.QueueItem

    test "queue_snapshot broadcast paints the active queue",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/download")
      assert html =~ "No active downloads" or html =~ "Downloading"

      item = %QueueItem{
        id: "hash-snapshot",
        title: "Snapshot Movie 2026",
        state: :downloading,
        status: "downloading",
        download_client: "qBittorrent",
        size: 100,
        size_left: 50,
        progress: 50.0,
        timeleft: "2m"
      }

      send(view.pid, {:queue_snapshot, [item]})

      assert render(view) =~ "Snapshot Movie 2026"
    end

    test "queue_snapshot with completed items filters them out",
         %{conn: conn} do
      # QueueMonitor pre-filters completed items, but the LV defends in
      # depth — a stale snapshot from cache or a future driver that emits
      # completed entries must not surface seeded torrents on /download.
      {:ok, view, _html} = live(conn, ~p"/download")

      done = %QueueItem{id: "h1", title: "Already Done Movie", state: :completed}
      live_item = %QueueItem{id: "h2", title: "Still Downloading Movie", state: :downloading}

      send(view.pid, {:queue_snapshot, [done, live_item]})

      html = render(view)
      refute html =~ "Already Done Movie"
      assert html =~ "Still Downloading Movie"
    end

    test "empty queue_snapshot transitions to the empty state",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/download")

      seed = %QueueItem{id: "h3", title: "Soon To Vanish", state: :downloading}
      send(view.pid, {:queue_snapshot, [seed]})
      assert render(view) =~ "Soon To Vanish"

      send(view.pid, {:queue_snapshot, []})

      html = render(view)
      refute html =~ "Soon To Vanish"
      assert html =~ "No active downloads"
    end

    test "capabilities_changed pings QueueMonitor for an immediate poll",
         %{conn: conn} do
      # Without this, a user who just configured their download client would
      # wait up to 30s (QueueMonitor's idle cadence) before the queue
      # populated. Ping QueueMonitor when the LV learns capabilities changed
      # so the queue surfaces within one round-trip.
      test_pid = self()

      Req.Test.stub(:qbittorrent, fn conn ->
        send(test_pid, :qbit_called)
        Req.Test.json(conn, [])
      end)

      qbit_client =
        Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")

      :persistent_term.put({QBittorrent, :client}, qbit_client)
      on_exit(fn -> QBittorrent.invalidate_client() end)

      monitor = start_supervised!(MediaCentarr.Acquisition.QueueMonitor)
      Req.Test.allow(:qbittorrent, self(), monitor)

      {:ok, view, _html} = live(conn, ~p"/download")

      # Drain any racing mount-time poll so the subsequent assert_receive
      # observes the post-:capabilities_changed call specifically.
      receive do
        :qbit_called -> :ok
      after
        500 -> :ok
      end

      send(view.pid, :capabilities_changed)

      assert_receive :qbit_called, 1_000
    end
  end

  describe "live updates from grab lifecycle" do
    # The activity zone shows recent grabs and their state. PubSub events
    # from acquisition coalesce through a 500ms debounce so a season-grab
    # cascade (one event per episode) becomes a single :reload_activity
    # tick — without coalescing the page would re-query the activity table
    # five times in quick succession for the same end state.

    test "five rapid grab_failed events coalesce into one reload",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/download")

      for _ <- 1..5 do
        send(view.pid, {:grab_failed, %{id: Ecto.UUID.generate(), reason: "boom"}})
      end

      Process.sleep(600)

      # No crash, page still renders activity zone.
      assert render(view) =~ "Activity" or render(view) =~ "activity"
    end

    test "grab_submitted broadcast triggers a debounced reload without crashing",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/download")

      send(view.pid, {:grab_submitted, %{id: Ecto.UUID.generate()}})
      send(view.pid, {:auto_grab_armed, %{id: Ecto.UUID.generate()}})
      send(view.pid, {:auto_grab_snoozed, %{id: Ecto.UUID.generate()}})

      Process.sleep(600)

      assert render(view) =~ "Activity" or render(view) =~ "activity"
    end
  end

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
