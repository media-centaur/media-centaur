defmodule MediaCentarr.Acquisition.DownloadClient.QBittorrent.SyncTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent.Sync
  alias MediaCentarr.Acquisition.QueueItem

  describe "apply_maindata/2" do
    test "full_update replaces the torrent map" do
      current = %{"old-hash" => %{"name" => "Old"}}

      response = %{
        "full_update" => true,
        "torrents" => %{
          "new-hash" => %{"name" => "New", "progress" => 0.5}
        }
      }

      assert %{
               "new-hash" => %{
                 "hash" => "new-hash",
                 "name" => "New",
                 "progress" => 0.5
               }
             } = Sync.apply_maindata(current, response)
    end

    test "partial torrents merges into existing entries, preserving untouched fields" do
      current = %{
        "abc" => %{
          "hash" => "abc",
          "name" => "Sample Movie",
          "size" => 1000,
          "progress" => 0.25,
          "state" => "downloading"
        }
      }

      response = %{
        "torrents" => %{
          "abc" => %{"progress" => 0.50, "dlspeed" => 1_500_000}
        }
      }

      assert %{
               "abc" => %{
                 "name" => "Sample Movie",
                 "size" => 1000,
                 "progress" => 0.50,
                 "state" => "downloading",
                 "dlspeed" => 1_500_000
               }
             } = Sync.apply_maindata(current, response)
    end

    test "torrents_removed drops the listed hashes" do
      current = %{
        "abc" => %{"hash" => "abc", "name" => "Keep"},
        "xyz" => %{"hash" => "xyz", "name" => "Drop"}
      }

      response = %{"torrents_removed" => ["xyz"]}

      assert %{"abc" => %{"name" => "Keep"}} = Sync.apply_maindata(current, response)
      refute Map.has_key?(Sync.apply_maindata(current, response), "xyz")
    end

    test "empty delta is a no-op" do
      current = %{"abc" => %{"hash" => "abc", "name" => "Stable"}}
      assert Sync.apply_maindata(current, %{}) == current
    end

    test "newly added torrent in delta gets the hash field set" do
      response = %{
        "torrents" => %{
          "fresh" => %{"name" => "Just Added", "progress" => 0.0}
        }
      }

      assert %{"fresh" => %{"hash" => "fresh", "name" => "Just Added"}} =
               Sync.apply_maindata(%{}, response)
    end
  end

  describe "to_queue_items/1" do
    test "converts each torrent map to a QueueItem via QueueItem.from_qbittorrent/1" do
      torrents = %{
        "abc" => %{
          "hash" => "abc",
          "name" => "Sample Movie",
          "size" => 1000,
          "amount_left" => 500,
          "progress" => 0.5,
          "state" => "downloading",
          "eta" => 120
        }
      }

      assert [%QueueItem{id: "abc", title: "Sample Movie", state: :downloading}] =
               Sync.to_queue_items(torrents)
    end

    test "empty map returns empty list" do
      assert Sync.to_queue_items(%{}) == []
    end
  end
end
