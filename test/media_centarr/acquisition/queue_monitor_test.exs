defmodule MediaCentarr.Acquisition.QueueMonitorTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.QueueMonitor

  describe "cadence_ms/2" do
    # The cadence table is the contract: how often QueueMonitor hits
    # the download client. Picking the right cell matters because the
    # 1 s row hits qBittorrent six times more often than the 5 s row,
    # and we don't want to do that when nothing is watching.

    test "watched + ready → 1 s (fast pulse for live UIs)" do
      # Any LiveView mounted on Acquisition / Library upcoming etc.
      # registers as a subscriber; while one is open the queue should
      # feel real-time.
      assert QueueMonitor.cadence_ms(1, true) == 1_000
      assert QueueMonitor.cadence_ms(5, true) == 1_000
    end

    test "unwatched + ready → 5 s (keeps cache warm without burning the client)" do
      # Nobody is rendering downloads but the client is configured —
      # poll at a relaxed 5 s so the next mount sees fresh-ish data.
      assert QueueMonitor.cadence_ms(0, true) == 5_000
    end

    test "offline (regardless of subscribers) → 30 s (don't hammer an unconfigured client)" do
      # Capabilities.download_client_ready?/0 is false. There's
      # nothing useful to fetch; back off to one poll every 30 s so the
      # eventual reconfigure picks up within a reasonable window.
      assert QueueMonitor.cadence_ms(0, false) == 30_000
      assert QueueMonitor.cadence_ms(3, false) == 30_000
    end
  end
end
