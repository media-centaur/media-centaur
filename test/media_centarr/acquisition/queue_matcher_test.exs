defmodule MediaCentarr.Acquisition.QueueMatcherTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.QueueMatcher
  alias MediaCentarr.Acquisition.ViewModels.{CurrentAction, PursuitRow, PursuitWithDownload}
  alias MediaCentarr.Downloads.QueueItem

  @stub_status %CurrentAction{verb: "Searching", description: "Looking.", severity: :info}

  defp row(id, release_title, opts \\ []) do
    %PursuitRow{
      id: id,
      title: Keyword.get(opts, :title, "Pursuit #{id}"),
      state: :active,
      detail_path: "/download/#{id}",
      release_title: release_title,
      status: @stub_status
    }
  end

  defp item(id, title, attrs \\ %{}) do
    base = %QueueItem{
      id: id,
      title: title,
      status: "downloading",
      state: :downloading,
      progress: 0.5,
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

    test "wraps QueueItem into a DownloadProgress with progress scaled to 0..100" do
      download = QueueMatcher.to_download(item("abc", "Sample.Movie", %{progress: 0.42}))

      assert download.state == :downloading
      assert download.progress_pct == 42.0
      assert download.client == "qBit"
      assert download.eta == "10m"
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
  end
end
