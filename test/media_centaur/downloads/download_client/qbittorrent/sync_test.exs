defmodule MediaCentaur.Downloads.DownloadClient.QBittorrent.SyncTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Downloads.DownloadClient.QBittorrent.Sync
  alias MediaCentaur.Downloads.QueueItem

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

  describe "counts/3" do
    # The display fields for the one-line sync log. Movement detection
    # and the message text both read from this single computation so
    # they can't drift apart.

    test "full-update echo: stable torrent set reports no movement counts" do
      response = %{"full_update" => true, "rid" => 7, "torrents" => %{"a" => %{}, "b" => %{}}}
      before_torrents = %{"a" => %{}, "b" => %{}}
      after_torrents = %{"a" => %{}, "b" => %{}}

      assert Sync.counts(response, before_torrents, after_torrents) ==
               %{rid: 7, full?: true, total: 2, added: 0, changed: 2, removed: 0}
    end

    test "partial delta: one torrent's fields changed, set size unchanged" do
      response = %{"rid" => 8, "torrents" => %{"a" => %{"progress" => 0.5}}}
      torrents = %{"a" => %{}, "b" => %{}}

      counts = Sync.counts(response, torrents, torrents)
      assert counts.full? == false
      assert counts.changed == 1
      assert counts.added == 0
      assert counts.removed == 0
    end

    test "added torrent: after set is larger than before" do
      response = %{"full_update" => true, "torrents" => %{"a" => %{}}}
      counts = Sync.counts(response, %{}, %{"a" => %{}})
      assert counts.added == 1
    end

    test "removed torrent: counted from torrents_removed and excluded from added math" do
      response = %{"torrents_removed" => ["a"]}
      counts = Sync.counts(response, %{"a" => %{}, "b" => %{}}, %{"b" => %{}})
      assert counts.removed == 1
      assert counts.added == 0
    end
  end

  describe "movement?/1" do
    # Decides whether a tick reflects real queue movement worth an info
    # log. A full_update snapshot that simply repeats the prior set is
    # NOT movement — that's the line that was flooding the Console ring
    # buffer every 1.5 s.

    test "full-update echo with a stable set is not movement" do
      refute Sync.movement?(%{full?: true, added: 0, removed: 0, changed: 2})
    end

    test "a partial delta carrying changes is movement" do
      assert Sync.movement?(%{full?: false, added: 0, removed: 0, changed: 1})
    end

    test "an added torrent is movement (even on a full update)" do
      assert Sync.movement?(%{full?: true, added: 1, removed: 0, changed: 1})
    end

    test "a removed torrent is movement" do
      assert Sync.movement?(%{full?: false, added: 0, removed: 1, changed: 0})
    end
  end
end
