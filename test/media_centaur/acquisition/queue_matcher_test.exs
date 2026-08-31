defmodule MediaCentaur.Acquisition.QueueMatcherTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.QueueMatcher
  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitRow, PursuitWithDownload}
  alias MediaCentaur.Downloads.QueueItem

  @stub_status %CurrentAction{verb: "Searching", description: "Looking.", severity: :info}

  defp row(id, release_title, opts \\ []) do
    %PursuitRow{
      id: id,
      title: Keyword.get(opts, :title, "Pursuit #{id}"),
      state: :active,
      release_title: release_title,
      torrent_hash: Keyword.get(opts, :torrent_hash),
      pairing_keys:
        Keyword.get(opts, :pairing_keys, [
          {Keyword.get(opts, :torrent_hash), release_title}
        ]),
      status: @stub_status
    }
  end

  defp item(id, title, attrs \\ %{}) do
    base = %QueueItem{
      id: id,
      title: title,
      status: "downloading",
      state: :downloading,
      # QueueItem.progress is ALREADY a percentage (0..100) — see
      # QueueItem.from_qbittorrent, which scales the qBittorrent 0..1
      # fraction by 100. Fixtures must use that unit.
      progress: 50.0,
      timeleft: "10m",
      download_client: "qBit"
    }

    struct!(base, attrs)
  end

  describe "normalize_title/1" do
    test "lowercases and strips non-alphanumeric" do
      assert QueueMatcher.normalize_title("Sample.Show.S01E03.1080p") ==
               "sampleshows01e031080p"
    end

    test "returns empty string for nil" do
      assert QueueMatcher.normalize_title(nil) == ""
    end

    test "matches across separator differences" do
      a = QueueMatcher.normalize_title("Sample.Movie.2010.1080p.WEB-DL")
      b = QueueMatcher.normalize_title("sample movie 2010 1080p web dl")
      assert a == b
    end
  end

  describe "to_download/1" do
    test "nil queue item returns nil" do
      assert QueueMatcher.to_download(nil) == nil
    end

    test "wraps QueueItem into a DownloadProgress, passing the already-percentage progress through unchanged" do
      download = QueueMatcher.to_download(item("abc", "Sample.Movie", %{progress: 42.0}))

      assert download.state == :downloading
      assert download.progress_pct == 42.0
      assert download.client == "qBit"
      assert download.eta == "10m"
      # The release name identifies the transfer — a pursuit with several
      # downloads renders one otherwise-identical strip per transfer.
      assert download.title == "Sample.Movie"
    end

    # Regression: QueueItem.progress is already 0..100, so `to_download`
    # must NOT multiply by 100 again. The double-scale showed up as a
    # "2330%" download in Active Pursuits (a torrent 23.3% complete).
    test "does not re-scale progress past 100%" do
      download = QueueMatcher.to_download(item("h", "Sample", %{progress: 23.3}))
      assert download.progress_pct == 23.3
    end

    # During the NZB-grab phase there is no content progress or meaningful
    # ETA yet — SABnzbd's percentage/timeleft describe the tiny .nzb fetch,
    # not the media. Suppress them so the card reads "Fetching NZB…" cleanly
    # instead of showing a misleading bar that appears to "start at 19%".
    test "suppresses progress and eta for :fetching_nzb" do
      download =
        QueueMatcher.to_download(
          item("g", "Sample", %{state: :fetching_nzb, progress: 0.0, timeleft: "0:00:05"})
        )

      assert download.state == :fetching_nzb
      assert download.progress_pct == nil
      assert download.eta == nil
    end
  end

  describe "match/2" do
    test "pairs each row with the queue item whose normalized title matches its release_title" do
      rows = [
        row("r1", "Sample.Movie.2010.1080p.WEB-DL"),
        row("r2", "sample.show.s01e03.720p.WEB")
      ]

      queue = [
        item("hash-a", "sample movie 2010 1080p web dl"),
        item("hash-b", "Sample.Show.S01E03.720p.WEB")
      ]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert orphans == []
      assert length(paired) == 2

      r1 = Enum.find(paired, fn %PursuitWithDownload{row: r} -> r.id == "r1" end)
      assert r1.queue_item_id == "hash-a"
      assert %{state: :downloading} = r1.download

      r2 = Enum.find(paired, fn %PursuitWithDownload{row: r} -> r.id == "r2" end)
      assert r2.queue_item_id == "hash-b"
    end

    test "rows without a matching queue item are paired with nil download" do
      rows = [row("r1", "Sample.Movie.2010.1080p")]
      queue = [item("hash-a", "Different.Title.2020")]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert [%PursuitWithDownload{download: nil, queue_item_id: nil}] = paired
      assert [%QueueItem{id: "hash-a"}] = orphans
    end

    test "rows with nil release_title are paired with nil download" do
      rows = [row("r1", nil)]
      queue = [item("hash-a", "Anything")]

      {paired, [%QueueItem{id: "hash-a"}]} = QueueMatcher.match(rows, queue)

      assert [%PursuitWithDownload{download: nil, queue_item_id: nil}] = paired
    end

    test "a composite row claims every queue item its in-flight targets grabbed (ADR-055)" do
      composite =
        row("p1", "Sample.Show.S01.1080p.BluRay",
          pairing_keys: [
            {nil, "Sample.Show.S01.1080p.BluRay"},
            {nil, "Sample.Show.S02.2160p.WEB-DL"}
          ]
        )

      queue = [
        item("q1", "Sample.Show.S01.1080p.BluRay"),
        item("q2", "Sample.Show.S02.2160p.WEB-DL"),
        item("q3", "Unrelated.Movie.2020.1080p")
      ]

      {[paired], orphans} = QueueMatcher.match([composite], queue)

      assert [%{queue_item_id: "q1"}, %{queue_item_id: "q2"}] = paired.downloads
      # The primary download stays the first key's match (the lead).
      assert paired.queue_item_id == "q1"
      assert paired.download.state == :downloading
      assert [%QueueItem{id: "q3"}] = orphans
    end

    test "pairing keys match by infohash first, title fallback per key" do
      composite =
        row("p1", "Sample.Show.S01.1080p",
          pairing_keys: [
            {"HASH-A", "Sample.Show.S01.1080p"},
            {nil, "Sample.Show.S02.2160p.WEB-DL"}
          ]
        )

      queue = [
        item("hash-a", "Renamed.By.Client"),
        item("q2", "Sample.Show.S02.2160p.WEB-DL")
      ]

      {[paired], orphans} = QueueMatcher.match([composite], queue)

      assert [%{queue_item_id: "hash-a"}, %{queue_item_id: "q2"}] = paired.downloads
      assert orphans == []
    end

    test "queue items unmatched by any row land in orphans" do
      rows = [row("r1", "Movie A")]
      queue = [item("a", "Movie A"), item("b", "Movie B"), item("c", "Movie C")]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert length(paired) == 1
      assert Enum.sort(Enum.map(orphans, & &1.id)) == ["b", "c"]
    end

    test "deterministic tie-break: first row in list wins on duplicate normalized titles" do
      rows = [
        row("r1", "Sample.Movie"),
        row("r2", "sample movie")
      ]

      queue = [item("hash-a", "sample.movie")]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      first = Enum.find(paired, &(&1.row.id == "r1"))
      second = Enum.find(paired, &(&1.row.id == "r2"))

      assert first.queue_item_id == "hash-a"
      assert second.queue_item_id == nil
      assert orphans == []
    end

    test "preserves the input row order in the paired list" do
      rows = [row("r1", "A"), row("r2", "B"), row("r3", "C")]
      queue = [item("b", "B"), item("a", "A"), item("c", "C")]

      {paired, _orphans} = QueueMatcher.match(rows, queue)

      assert Enum.map(paired, & &1.row.id) == ["r1", "r2", "r3"]
    end

    test "pairs by infohash when the row carries a torrent_hash, ignoring the title" do
      rows = [row("r1", "Sample Show S05E03 clean release", torrent_hash: "ABCDEF123")]
      # Torrent name bears a tracker prefix the title match could never bridge,
      # and qBittorrent reports the hash lowercase.
      queue = [item("abcdef123", "www.UIndex.org - Sample Show S05E03 something else entirely")]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert orphans == []

      assert [%PursuitWithDownload{queue_item_id: "abcdef123", download: %{state: :downloading}}] =
               paired
    end

    test "infohash wins over a title that matches a different queue item" do
      rows = [row("r1", "Same Title 1080p", torrent_hash: "hashA")]

      queue = [
        item("hashA", "www.tracker.org - completely different name"),
        item("hashB", "Same Title 1080p")
      ]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert [%PursuitWithDownload{queue_item_id: "hashA"}] = paired
      assert [%QueueItem{id: "hashB"}] = orphans
    end

    test "hash is authoritative — no fallback to a title match when the hash is absent from the queue" do
      # Torrent completed and was removed; only a same-titled stranger remains.
      rows = [row("r1", "Sample Movie 2010", torrent_hash: "gone")]
      queue = [item("other", "Sample Movie 2010")]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert [%PursuitWithDownload{download: nil, queue_item_id: nil}] = paired
      assert [%QueueItem{id: "other"}] = orphans
    end

    test "title fallback tolerates a tracker prefix on the torrent name (no hash captured yet)" do
      # The screenshot bug: pursuit has no hash yet, torrent name is prefixed.
      rows = [row("r1", "Sample.Show.S05E03.Every.Last.Bit.Of.It.2160p.AMZN.WEB-DL")]

      queue = [
        item("h3", "www.UIndex.org - Sample Show S05E03 Every Last Bit Of It 2160p AMZN WEB-DL")
      ]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert orphans == []
      assert [%PursuitWithDownload{queue_item_id: "h3"}] = paired
    end

    test "containment fallback does not fire for short release titles" do
      # "Movie A" -> "moviea" is too short to safely containment-match;
      # only an exact normalized match should pair it.
      rows = [row("r1", "Movie A")]
      queue = [item("h", "www.tracker.org - Movie ABCDEF Extended Edition")]

      {paired, orphans} = QueueMatcher.match(rows, queue)

      assert [%PursuitWithDownload{download: nil, queue_item_id: nil}] = paired
      assert [%QueueItem{id: "h"}] = orphans
    end
  end

  describe "finished downloads leave the in-flight strip (UIDR-029 follow-up)" do
    test "a finished file is excluded from downloads but stays claimed — never an orphan" do
      row =
        struct(MediaCentaur.Acquisition.ViewModels.PursuitRow,
          pursuit_id: "p-1",
          release_title: "Sample.Show.S01E01.x264",
          torrent_hash: nil,
          pairing_keys: [{nil, "Sample.Show.S01E01.x264"}, {nil, "Sample.Show.S01E02.x264"}]
        )

      done = item("qi-1", "Sample.Show.S01E01.x264", %{progress: 100.0})
      active = item("qi-2", "Sample.Show.S01E02.x264", %{progress: 40.0})

      {[entry], orphans} = QueueMatcher.match([row], [done, active])

      assert [%{queue_item_id: "qi-2"}] = entry.downloads
      assert orphans == []
    end
  end
end
