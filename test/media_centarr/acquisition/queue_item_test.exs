defmodule MediaCentarr.Acquisition.QueueItemTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.QueueItem

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

    test "maps stalledDL and queuedDL to :stalled" do
      assert QueueItem.from_qbittorrent(base_torrent(%{"state" => "stalledDL"})).state == :stalled
      assert QueueItem.from_qbittorrent(base_torrent(%{"state" => "queuedDL"})).state == :stalled
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
      raw = base_torrent(%{}) |> Map.delete("progress")
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
