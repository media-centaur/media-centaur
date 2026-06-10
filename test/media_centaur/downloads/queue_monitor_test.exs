defmodule MediaCentaur.Downloads.QueueMonitorTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Downloads.{QueueMonitor, QueueState}

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

    test "watched + ready + no error → 10 s (fresh enough without hammering the client)" do
      # Any LiveView mounted on Acquisition / Library upcoming etc.
      # registers as a subscriber; while one is open the queue polls
      # every 10 s — fresh enough for an open queue view without piling
      # requests on the client or flooding the logs.
      assert QueueMonitor.cadence_ms(1, true, nil) == 10_000
      assert QueueMonitor.cadence_ms(5, true, nil) == 10_000
    end

    test "unwatched + ready + no error → 30 s (just keeps the cache from going stale)" do
      # Nobody is rendering downloads but the client is configured —
      # back off to 30 s; the next mount gets the current state pushed
      # immediately on register, so it doesn't need eager idle polling.
      assert QueueMonitor.cadence_ms(0, true, nil) == 30_000
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
