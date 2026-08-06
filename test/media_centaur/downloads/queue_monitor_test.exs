defmodule MediaCentaur.Downloads.QueueMonitorTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.{QueueMonitor, QueueState}
  alias MediaCentaur.DownloadClientStubs
  alias MediaCentaur.Topics

  describe "register_subscriber/1" do
    setup do
      # The application-level QueueMonitor isn't started in test env. Start
      # a fresh one for this test; in the test config Capabilities reports
      # the download client as unconfigured, so init's first poll is a
      # no-op and won't fire HTTP calls.
      start_supervised!(QueueMonitor)
      :ok
    end

    test "sends the current queue state to the registering pid immediately" do
      QueueMonitor.register_subscriber(self())
      assert_receive {:queue_state, %QueueState{}}, 500
    end

    test "is idempotent — re-registering the same pid still sends state" do
      QueueMonitor.register_subscriber(self())
      assert_receive {:queue_state, %QueueState{}}, 500

      QueueMonitor.register_subscriber(self())
      assert_receive {:queue_state, %QueueState{}}, 500
    end
  end

  describe "connectivity grading (observed via PubSub broadcasts)" do
    # The monitor grades connectivity itself, from poll outcomes — never
    # from snapshot age. These tests drive polls deterministically with
    # poll_now/0 against a Req.Test-stubbed qBittorrent and observe the
    # graded %QueueState{} broadcasts; no sleeps, no cadence waits.
    @moduletag :capture_log

    setup do
      DownloadClientStubs.setup_qbittorrent_client()

      # The monitor GenServer isn't in this test's $callers chain, so the
      # Req.Test stub must be shared. The suite file is async: false, so
      # sharing can't leak across concurrently running tests.
      Req.Test.set_req_test_to_shared()
      on_exit(fn -> Req.Test.set_req_test_to_private() end)

      # Force the readiness flag without the settings DB — same cache key
      # Capabilities itself maintains. No cleanup here: every DataCase /
      # ConnCase test restores the whole term store before it runs
      # (`MediaCentaur.GlobalStateSandbox`).
      :persistent_term.put({Capabilities, :ready_flags}, %{
        tmdb: false,
        prowlarr: false,
        torrent_client: true,
        usenet_client: false,
        download_client: true,
        acquisition: false
      })

      stub_sync_success()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_queue())
      start_supervised!(QueueMonitor)

      # init schedules an immediate first poll — drain its broadcast so
      # each test starts from a known :live baseline.
      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000
      :ok
    end

    defp stub_sync_success do
      Req.Test.stub(:qbittorrent, fn conn ->
        Req.Test.json(conn, %{
          "rid" => 1,
          "full_update" => true,
          "torrents" => %{},
          "server_state" => %{}
        })
      end)
    end

    defp stub_sync_unreachable do
      Req.Test.stub(:qbittorrent, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)
    end

    test "a successful poll broadcasts :live" do
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000
      assert QueueMonitor.state().connectivity == :live
    end

    test "one failed poll is a transient blip — not yet an outage" do
      stub_sync_unreachable()
      QueueMonitor.poll_now()

      assert_receive {:queue_state, %QueueState{connectivity: {:transient_failure, %DateTime{}}}},
                     1000
    end

    test "two consecutive failed polls grade offline, dated from the first failure" do
      stub_sync_unreachable()
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: {:transient_failure, onset}}}, 1000

      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: {:offline, ^onset}}}, 1000
    end

    test "a successful poll after an outage recovers to :live" do
      stub_sync_unreachable()
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: {:transient_failure, _}}}, 1000
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: {:offline, _}}}, 1000

      stub_sync_success()
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000
    end

    test "registering the first subscriber triggers an immediate fresh poll" do
      # Beyond the direct cached-state send, the 0→1 subscriber transition
      # must poll right away — the pending timer may be up to an idle
      # cadence (30 s) out, and a freshly opened page shouldn't wait on it.
      QueueMonitor.register_subscriber(self())

      # Direct send of the cached snapshot…
      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000
      # …followed by a broadcast from the immediate poll (well under any cadence).
      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000
    end
  end

  describe "multi-client polling" do
    @moduletag :capture_log

    setup do
      DownloadClientStubs.setup_qbittorrent_client()
      DownloadClientStubs.setup_sabnzbd_client()

      Req.Test.set_req_test_to_shared()
      on_exit(fn -> Req.Test.set_req_test_to_private() end)

      # Force the readiness flag without the settings DB — same cache key
      # Capabilities itself maintains. Cleanup is the global-state
      # sandbox's job (`MediaCentaur.GlobalStateSandbox`), not this file's.
      :persistent_term.put({Capabilities, :ready_flags}, %{
        tmdb: false,
        prowlarr: false,
        torrent_client: true,
        usenet_client: true,
        download_client: true,
        acquisition: false
      })

      stub_qbit_with_torrent()
      stub_sab_with_download()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_queue())
      start_supervised!(QueueMonitor)

      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000
      :ok
    end

    defp stub_qbit_with_torrent do
      Req.Test.stub(:qbittorrent, fn conn ->
        Req.Test.json(conn, %{
          "rid" => 1,
          "full_update" => true,
          "torrents" => %{
            "hash-a" => %{
              "name" => "Sample.Show.S01E01.1080p.WEB-DL",
              "state" => "downloading",
              "size" => 1000,
              "amount_left" => 500,
              "progress" => 0.5
            }
          },
          "server_state" => %{}
        })
      end)
    end

    defp stub_sab_with_download do
      Req.Test.stub(:sabnzbd, fn conn ->
        case conn.params["mode"] do
          "history" ->
            Req.Test.json(conn, %{
              "history" => %{
                "slots" => [
                  %{
                    "nzo_id" => "SABnzbd_nzo_done",
                    "name" => "Sample.Show.S01E03.1080p.WEB-DL",
                    "status" => "Completed",
                    "storage" => "/downloads/complete/Sample.Show.S01E03.1080p.WEB-DL",
                    "bytes" => 900,
                    "category" => "tv",
                    "fail_message" => ""
                  }
                ]
              }
            })

          _other ->
            Req.Test.json(conn, %{
              "queue" => %{
                "slots" => [
                  %{
                    "nzo_id" => "SABnzbd_nzo_live",
                    "filename" => "Sample.Show.S01E02.1080p.WEB-DL",
                    "status" => "Downloading",
                    "mb" => "100.0",
                    "mbleft" => "40.0",
                    "percentage" => "60",
                    "timeleft" => "0:02:00",
                    "cat" => "tv"
                  }
                ]
              }
            })
        end
      end)
    end

    defp stub_sab_unreachable do
      Req.Test.stub(:sabnzbd, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    end

    test "merges both clients' items into one protocol-tagged snapshot, torrent slot first" do
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{items: items, connectivity: :live}}, 1000

      assert [
               %{id: "hash-a", protocol: :torrent},
               %{id: "SABnzbd_nzo_live", protocol: :usenet},
               %{id: "SABnzbd_nzo_done", protocol: :usenet}
             ] = Enum.map(items, &Map.take(&1, [:id, :protocol]))
    end

    test "completed usenet history items stay in the snapshot so completion (and its storage path) is observable" do
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{items: items}}, 1000

      completed = Enum.find(items, &(&1.id == "SABnzbd_nzo_done"))
      assert completed.state == :completed
      assert completed.content_path == "/downloads/complete/Sample.Show.S01E03.1080p.WEB-DL"
      assert completed.health == nil, "completed items are not health-classified"
    end

    test "one client down keeps the other live — merged grade degrades, per-client grades stay honest" do
      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: :live}}, 1000

      stub_sab_unreachable()
      QueueMonitor.poll_now()

      assert_receive {:queue_state, %QueueState{} = state}, 1000
      assert {:transient_failure, %DateTime{}} = state.connectivity
      assert state.client_connectivity[:torrent] == :live
      assert {:transient_failure, _} = state.client_connectivity[:usenet]

      # The healthy client's items are fresh; the failed client keeps
      # its last-known items rather than vanishing mid-outage.
      assert Enum.any?(state.items, &(&1.id == "hash-a"))
      assert Enum.any?(state.items, &(&1.id == "SABnzbd_nzo_live"))
    end

    test "an auth failure on one client grades the merged snapshot :auth_failed" do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "API Key Incorrect"})
      end)

      QueueMonitor.poll_now()
      assert_receive {:queue_state, %QueueState{connectivity: :auth_failed} = state}, 1000
      assert state.client_connectivity[:torrent] == :live
    end
  end

  describe "cadence_ms/3" do
    # The cadence table is the contract: how often QueueMonitor hits
    # the download client. Picking the right cell matters because the
    # watched row polls qBittorrent ~3× more often than the idle row,
    # and we don't want to do that when nothing is watching.

    test "watched + ready + live → 10 s (fresh enough without hammering the client)" do
      # Any LiveView mounted on Acquisition / Library upcoming etc.
      # registers as a subscriber; while one is open the queue polls
      # every 10 s — fresh enough for an open queue view without piling
      # requests on the client or flooding the logs.
      assert QueueMonitor.cadence_ms(1, true, :live) == 10_000
      assert QueueMonitor.cadence_ms(5, true, :live) == 10_000
    end

    test "watched + offline still polls at 10 s so recovery is noticed promptly" do
      assert QueueMonitor.cadence_ms(1, true, {:offline, DateTime.utc_now()}) == 10_000
      assert QueueMonitor.cadence_ms(1, true, {:transient_failure, DateTime.utc_now()}) == 10_000
    end

    test "unwatched + ready → 30 s (just keeps the cache from going stale)" do
      # Nobody is rendering downloads but the client is configured —
      # back off to 30 s; the next mount gets the current state pushed
      # immediately on register plus an immediate poll, so it doesn't
      # need eager idle polling.
      assert QueueMonitor.cadence_ms(0, true, :live) == 30_000
    end

    test "not ready (regardless of subscribers / connectivity) → 30 s" do
      # Capabilities.download_client_ready?/0 is false. There's nothing
      # useful to fetch; back off to one poll every 30 s so the eventual
      # reconfigure picks up within a reasonable window.
      assert QueueMonitor.cadence_ms(0, false, :live) == 30_000
      assert QueueMonitor.cadence_ms(3, false, :live) == 30_000
      assert QueueMonitor.cadence_ms(3, false, :auth_failed) == 30_000
    end

    test "auth_failed → 30 s even when ready and watched (don't hammer with bad creds)" do
      # Capabilities.last_test_ok? lags real auth state — a successful
      # test_connection at config time stays "ok" forever even if creds
      # later rotate. Without this row, polling continues at the watched
      # cadence against a broken auth, log-spamming until the user
      # reconfigures.
      assert QueueMonitor.cadence_ms(5, true, :auth_failed) == 30_000
      assert QueueMonitor.cadence_ms(0, true, :auth_failed) == 30_000
    end
  end

  describe "sync_log_level/3" do
    # Throttle: real movement always logs at :info; steady-state no-op
    # ticks are skipped except for a periodic heartbeat so "is the
    # subsystem still polling?" stays answerable without flooding.
    @heartbeat 60_000

    test "movement always logs at info" do
      assert QueueMonitor.sync_log_level(true, 0, @heartbeat) == :info
      assert QueueMonitor.sync_log_level(true, @heartbeat * 10, @heartbeat) == :info
    end

    test "no movement is skipped until the heartbeat interval elapses" do
      assert QueueMonitor.sync_log_level(false, 0, @heartbeat) == :skip
      assert QueueMonitor.sync_log_level(false, @heartbeat - 1, @heartbeat) == :skip
    end

    test "no movement logs an info heartbeat once the interval elapses" do
      assert QueueMonitor.sync_log_level(false, @heartbeat, @heartbeat) == :info
      assert QueueMonitor.sync_log_level(false, @heartbeat + 1, @heartbeat) == :info
    end
  end
end
