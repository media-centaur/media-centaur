defmodule MediaCentaur.Downloads.QueueItemTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Downloads.QueueItem

  describe "from_qbittorrent/1" do
    test "parses a downloading torrent" do
      raw = %{
        "hash" => "abc123def456",
        "name" => "Some.Movie.2024.2160p.UHD.BluRay-FGT",
        "state" => "downloading",
        "size" => 100_000_000_000,
        "amount_left" => 25_000_000_000,
        "progress" => 0.75,
        "eta" => 1800,
        "category" => "movies"
      }

      item = QueueItem.from_qbittorrent(raw)

      assert %QueueItem{} = item
      assert item.id == "abc123def456"
      assert item.title == "Some.Movie.2024.2160p.UHD.BluRay-FGT"
      assert item.status == "downloading"
      assert item.state == :downloading
      assert item.download_client == "qBittorrent"
      assert item.indexer == "movies"
      assert item.size == 100_000_000_000
      assert item.size_left == 25_000_000_000
      assert item.progress == 75.0
      assert item.timeleft == "30m"
    end

    test "captures content_path from qBittorrent" do
      item =
        QueueItem.from_qbittorrent(%{
          "hash" => "h",
          "name" => "Some.Movie.2024-FGT",
          "state" => "downloading",
          "content_path" => "/downloads/Some.Movie.2024-FGT.mkv"
        })

      assert item.content_path == "/downloads/Some.Movie.2024-FGT.mkv"
    end

    test "content_path is nil when absent or blank" do
      assert QueueItem.from_qbittorrent(%{"hash" => "h", "name" => "X", "state" => "downloading"}).content_path ==
               nil

      assert QueueItem.from_qbittorrent(%{
               "hash" => "h",
               "name" => "X",
               "state" => "downloading",
               "content_path" => ""
             }).content_path == nil
    end

    test "leaves :health nil — only QueueMonitor sets it (it's the only thing with history)" do
      item = QueueItem.from_qbittorrent(base_torrent(%{}))
      assert item.health == nil
    end

    test "maps qbittorrent active states to :downloading" do
      for state <- ~w(downloading metaDL forcedDL allocating checkingResumeData checkingDL) do
        item = QueueItem.from_qbittorrent(base_torrent(%{"state" => state}))
        assert item.state == :downloading, "expected #{state} → :downloading"
      end
    end

    test "maps qbittorrent seeding/done states to :completed" do
      for state <- ~w(uploading forcedUP pausedUP queuedUP stalledUP checkingUP) do
        item = QueueItem.from_qbittorrent(base_torrent(%{"state" => state}))
        assert item.state == :completed, "expected #{state} → :completed"
      end
    end

    test "maps pausedDL to :paused" do
      item = QueueItem.from_qbittorrent(base_torrent(%{"state" => "pausedDL"}))
      assert item.state == :paused
    end

    test "maps stalledDL to :stalled" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"state" => "stalledDL"})).state == :stalled
    end

    test "maps queuedDL to :queued — distinct from :stalled (waiting in qBittorrent's queue, not started yet)" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"state" => "queuedDL"})).state == :queued
    end

    test "maps error and missingFiles to :error" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"state" => "error"})).state == :error

      assert QueueItem.from_qbittorrent(base_torrent(%{"state" => "missingFiles"})).state ==
               :error
    end

    test "maps unknown state to :other and preserves the raw status string" do
      item = QueueItem.from_qbittorrent(base_torrent(%{"state" => "futureState"}))
      assert item.state == :other
      assert item.status == "futureState"
    end

    test "progress is the qbittorrent fraction multiplied by 100" do
      item = QueueItem.from_qbittorrent(base_torrent(%{"progress" => 0.42}))
      assert item.progress == 42.0
    end

    test "progress is nil when missing" do
      raw = Map.delete(base_torrent(%{}), "progress")
      item = QueueItem.from_qbittorrent(raw)
      assert item.progress == nil
    end

    # qBittorrent's JSON sometimes serialises `progress` as an integer
    # (0 or 1) rather than a float. `Float.round/2` rejects integers in
    # Elixir 1.19+, which crashed the /download poller. Ensure integer
    # progress is coerced to float.
    test "progress accepts integer 0 and returns a float" do
      item = QueueItem.from_qbittorrent(base_torrent(%{"progress" => 0}))
      assert item.progress === 0.0
    end

    test "progress accepts integer 1 and returns a float" do
      item = QueueItem.from_qbittorrent(base_torrent(%{"progress" => 1}))
      assert item.progress === 100.0
    end

    test "timeleft is nil when eta is the qbittorrent infinite sentinel" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"eta" => 8_640_000})).timeleft == nil
    end

    test "timeleft formats short durations as seconds" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"eta" => 45})).timeleft == "45s"
    end

    test "timeleft formats minutes" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"eta" => 600})).timeleft == "10m"
    end

    test "timeleft formats hours and minutes" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"eta" => 5400})).timeleft == "1h 30m"
    end

    test "timeleft formats days for very long etas" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"eta" => 200_000})).timeleft == "2d"
    end

    test "indexer is nil when category is empty" do
      item = QueueItem.from_qbittorrent(base_torrent(%{"category" => ""}))
      assert item.indexer == nil
    end

    test "substitutes a friendly placeholder when name equals the info-hash" do
      # qBittorrent reports `name` as the info-hash itself until the
      # `.torrent` metadata downloads (typically during `metaDL`).
      # Showing the bare hex string in the Downloads UI confuses users
      # — substitute a friendly placeholder until a real name arrives.
      hash = "ad0352787544b70df51dc696b9e0f99add01acd4"
      raw = base_torrent(%{"hash" => hash, "name" => hash, "state" => "metaDL"})
      item = QueueItem.from_qbittorrent(raw)
      assert item.id == hash
      assert item.title == "Fetching torrent details…"
    end

    test "keeps a real qBittorrent name even when it's hash-shaped but not the hash" do
      # Don't false-positive on legitimate titles that happen to look
      # hash-like — only substitute when name == hash exactly.
      raw = base_torrent(%{"hash" => "abc", "name" => "Sample.Show.S01E01.mkv"})
      assert QueueItem.from_qbittorrent(raw).title == "Sample.Show.S01E01.mkv"
    end
  end

  describe "protocol tagging" do
    test "from_qbittorrent tags items :torrent" do
      assert QueueItem.from_qbittorrent(base_torrent(%{})).protocol == :torrent
    end
  end

  describe "from_sabnzbd_queue/1" do
    test "parses a downloading queue slot" do
      raw = %{
        "nzo_id" => "SABnzbd_nzo_p86tgx",
        "filename" => "Sample.Show.S01E01.1080p.WEB-DL",
        "status" => "Downloading",
        "mb" => "1277.76",
        "mbleft" => "756.40",
        "percentage" => "40",
        "timeleft" => "0:12:44",
        "cat" => "tv"
      }

      item = QueueItem.from_sabnzbd_queue(raw)

      assert %QueueItem{} = item
      assert item.id == "SABnzbd_nzo_p86tgx"
      assert item.title == "Sample.Show.S01E01.1080p.WEB-DL"
      assert item.status == "Downloading"
      assert item.state == :downloading
      assert item.protocol == :usenet
      assert item.download_client == "SABnzbd"
      assert item.indexer == "tv"
      assert item.size == 1_339_828_470
      assert item.size_left == 793_142_886
      assert item.progress == 40.0
      assert item.timeleft == "0:12:44"
      assert item.normalized_title == "sampleshows01e011080pwebdl"
    end

    test "content_path stays nil for live queue slots — the incomplete dir must never be pinned" do
      assert QueueItem.from_sabnzbd_queue(base_sab_slot(%{})).content_path == nil
    end

    test "Downloading maps to :downloading" do
      item = QueueItem.from_sabnzbd_queue(base_sab_slot(%{"status" => "Downloading"}))
      assert item.state == :downloading
    end

    # "Grabbing" is SABnzbd fetching the .nzb from the indexer — the content
    # download has NOT started. Collapsing it into :downloading made the card
    # claim "Downloading" (with a meaningless %) before a byte of media moved.
    test "Grabbing (fetching the NZB, pre-download) maps to :fetching_nzb, not :downloading" do
      item = QueueItem.from_sabnzbd_queue(base_sab_slot(%{"status" => "Grabbing"}))
      assert item.state == :fetching_nzb
    end

    # "Fetching" is SABnzbd pulling extra par2 blocks to repair a damaged
    # download — a repair-phase activity, not content download.
    test "Fetching (extra repair blocks) maps to :repairing, not :downloading" do
      item = QueueItem.from_sabnzbd_queue(base_sab_slot(%{"status" => "Fetching"}))
      assert item.state == :repairing
    end

    test "maps waiting statuses to :queued" do
      for status <- ~w(Queued Propagating) do
        item = QueueItem.from_sabnzbd_queue(base_sab_slot(%{"status" => status}))
        assert item.state == :queued, "expected #{status} → :queued"
      end
    end

    test "maps Paused to :paused and unknown statuses to :other" do
      assert QueueItem.from_sabnzbd_queue(base_sab_slot(%{"status" => "Paused"})).state == :paused

      item = QueueItem.from_sabnzbd_queue(base_sab_slot(%{"status" => "FutureStatus"}))
      assert item.state == :other
      assert item.status == "FutureStatus"
    end

    test "tolerates numeric mb/percentage values — SABnzbd serialises these as strings, but don't depend on it" do
      item =
        QueueItem.from_sabnzbd_queue(base_sab_slot(%{"mb" => 100.0, "mbleft" => 50, "percentage" => 50}))

      assert item.size == 104_857_600
      assert item.size_left == 52_428_800
      assert item.progress == 50.0
    end

    test "size fields are nil when unparseable" do
      item = QueueItem.from_sabnzbd_queue(base_sab_slot(%{"mb" => "??", "mbleft" => nil}))
      assert item.size == nil
      assert item.size_left == nil
    end
  end

  describe "from_sabnzbd_history/1" do
    test "a Completed entry is :completed with content_path from storage" do
      raw = %{
        "nzo_id" => "SABnzbd_nzo_done1",
        "name" => "Sample.Show.S01E02.1080p.WEB-DL",
        "status" => "Completed",
        "storage" => "/downloads/complete/Sample.Show.S01E02.1080p.WEB-DL",
        "bytes" => 1_339_664_772,
        "category" => "tv",
        "fail_message" => ""
      }

      item = QueueItem.from_sabnzbd_history(raw)

      assert item.id == "SABnzbd_nzo_done1"
      assert item.title == "Sample.Show.S01E02.1080p.WEB-DL"
      assert item.state == :completed
      assert item.protocol == :usenet
      assert item.download_client == "SABnzbd"
      assert item.content_path == "/downloads/complete/Sample.Show.S01E02.1080p.WEB-DL"
      assert item.size == 1_339_664_772
      assert item.size_left == 0
      assert item.progress == 100.0
      assert item.failure_message == nil
    end

    test "a Failed entry is :error and carries the fail_message" do
      raw =
        base_sab_history(%{
          "status" => "Failed",
          "fail_message" => "Repair failed, not enough repair blocks"
        })

      item = QueueItem.from_sabnzbd_history(raw)

      assert item.state == :error
      assert item.failure_message == "Repair failed, not enough repair blocks"
      assert item.content_path == nil, "failed storage points at cruft, never pin it"
    end

    test "post-processing statuses map to their own states so the UI doesn't read them as stalled" do
      assert QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Verifying"})).state ==
               :verifying

      assert QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Repairing"})).state ==
               :repairing

      assert QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Extracting"})).state ==
               :extracting
    end

    test "post-processing entries never carry content_path — the file only exists after Completed" do
      item = QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Extracting"}))
      assert item.content_path == nil
    end

    test "history Queued (retry queue) maps to :queued; unknown statuses to :other" do
      assert QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Queued"})).state ==
               :queued

      assert QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Running"})).state ==
               :other
    end

    test "Moving maps to :moving — minutes-long for a large job crossing mounts, not a blip" do
      item = QueueItem.from_sabnzbd_history(base_sab_history(%{"status" => "Moving"}))
      assert item.state == :moving
      assert item.content_path == nil, "the file is mid-relocation — no final path yet"
    end
  end

  defp base_sab_slot(overrides) do
    Map.merge(
      %{
        "nzo_id" => "SABnzbd_nzo_base",
        "filename" => "Sample.Show.S01E01.1080p.WEB-DL",
        "status" => "Downloading",
        "mb" => "100.0",
        "mbleft" => "50.0",
        "percentage" => "50",
        "timeleft" => "0:01:00",
        "cat" => "tv"
      },
      overrides
    )
  end

  defp base_sab_history(overrides) do
    Map.merge(
      %{
        "nzo_id" => "SABnzbd_nzo_hist",
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

  defp base_torrent(overrides) do
    Map.merge(
      %{
        "hash" => "h",
        "name" => "x",
        "state" => "downloading",
        "size" => 100,
        "amount_left" => 50,
        "progress" => 0.5,
        "eta" => 60,
        "category" => "movies"
      },
      overrides
    )
  end
end
