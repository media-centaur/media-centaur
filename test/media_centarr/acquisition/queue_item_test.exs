defmodule MediaCentarr.Acquisition.QueueItemTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.QueueItem

  describe "from_prowlarr/1" do
    test "parses a typical queue entry" do
      raw = %{
        "id" => 42,
        "title" => "Some.Movie.2024.2160p.UHD.BluRay-FGT",
        "status" => "downloading",
        "downloadClient" => "qBittorrent",
        "indexer" => "1337x",
        "size" => 100_000_000_000,
        "sizeleft" => 25_000_000_000,
        "timeleft" => "00:30:00"
      }

      item = QueueItem.from_prowlarr(raw)

      assert %QueueItem{} = item
      assert item.id == 42
      assert item.title == "Some.Movie.2024.2160p.UHD.BluRay-FGT"
      assert item.status == "downloading"
      assert item.download_client == "qBittorrent"
      assert item.indexer == "1337x"
      assert item.size == 100_000_000_000
      assert item.size_left == 25_000_000_000
      assert item.timeleft == "00:30:00"
      assert item.progress == 75.0
    end

    test "computes progress as percent (size minus size_left divided by size)" do
      item =
        QueueItem.from_prowlarr(%{
          "id" => 1,
          "title" => "x",
          "size" => 200,
          "sizeleft" => 50
        })

      assert item.progress == 75.0
    end

    test "progress is nil when size is missing" do
      item = QueueItem.from_prowlarr(%{"id" => 1, "title" => "x", "sizeleft" => 100})
      assert item.progress == nil
    end

    test "progress is nil when size_left is missing" do
      item = QueueItem.from_prowlarr(%{"id" => 1, "title" => "x", "size" => 100})
      assert item.progress == nil
    end

    test "progress is nil when size is zero" do
      item =
        QueueItem.from_prowlarr(%{"id" => 1, "title" => "x", "size" => 0, "sizeleft" => 0})

      assert item.progress == nil
    end

    test "title defaults to empty string when missing" do
      item = QueueItem.from_prowlarr(%{"id" => 1})
      assert item.title == ""
    end

    test "preserves unknown status values verbatim" do
      item =
        QueueItem.from_prowlarr(%{
          "id" => 1,
          "title" => "x",
          "status" => "some-future-status"
        })

      assert item.status == "some-future-status"
    end
  end
end
