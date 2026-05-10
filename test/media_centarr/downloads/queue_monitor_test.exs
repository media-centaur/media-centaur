defmodule MediaCentarr.Downloads.QueueMonitorTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Downloads.{QueueMonitor, QueueState}

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

  describe "cadence_ms/3" do
    # The cadence table is the contract: how often QueueMonitor hits
    # the download client. Picking the right cell matters because the
    # watched row polls qBittorrent ~3× more often than the idle row,
    # and we don't want to do that when nothing is watching.

    test "watched + ready + no error → 1.5 s (matches qBittorrent webUI's native cadence)" do
      # Any LiveView mounted on Acquisition / Library upcoming etc.
      # registers as a subscriber; while one is open the queue should
      # feel real-time. 1500 ms is qBittorrent webUI's default
      # `sync/maindata` interval — matching it gives the same "feel"
      # as the native UI without piling extra requests on the server.
      assert QueueMonitor.cadence_ms(1, true, nil) == 1_500
      assert QueueMonitor.cadence_ms(5, true, nil) == 1_500
    end

    test "unwatched + ready + no error → 5 s (keeps cache warm without burning the client)" do
      # Nobody is rendering downloads but the client is configured —
      # poll at a relaxed 5 s so the next mount sees fresh-ish data.
      assert QueueMonitor.cadence_ms(0, true, nil) == 5_000
    end

    test "not ready (regardless of subscribers / error) → 30 s" do
      # Capabilities.download_client_ready?/0 is false. There's nothing
      # useful to fetch; back off to one poll every 30 s so the eventual
      # reconfigure picks up within a reasonable window.
      assert QueueMonitor.cadence_ms(0, false, nil) == 30_000
      assert QueueMonitor.cadence_ms(3, false, nil) == 30_000
      assert QueueMonitor.cadence_ms(3, false, :auth_failed) == 30_000
    end

    test "auth_failed → 30 s even when ready and watched (don't hammer with bad creds)" do
      # Capabilities.last_test_ok? lags real auth state — a successful
      # test_connection at config time stays "ok" forever even if creds
      # later rotate. Without this row, polling continues at 1.5 s
      # against a broken auth, log-spamming until the user reconfigures.
      assert QueueMonitor.cadence_ms(5, true, :auth_failed) == 30_000
      assert QueueMonitor.cadence_ms(0, true, :auth_failed) == 30_000
    end
  end
end
