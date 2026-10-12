defmodule MediaCentaurWeb.Components.Acquisition.DownloadStripTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.ViewModels.DownloadProgress
  alias MediaCentaur.Downloads.{Phase, QueueItem}
  alias MediaCentaurWeb.Components.Acquisition.DownloadStrip

  defp download(protocol, state, overrides) do
    item =
      struct!(
        %QueueItem{
          id: "job",
          title: "Sample.Show.S01E01.1080p.WEB-DL",
          state: state,
          protocol: protocol
        },
        overrides
      )

    %DownloadProgress{
      state: state,
      title: item.title,
      progress_pct: item.progress,
      size_bytes: item.size,
      eta: item.timeleft,
      client: if(protocol == :usenet, do: "SABnzbd", else: "qBittorrent"),
      protocol: protocol,
      phase: Phase.of(item)
    }
  end

  defp strip(download, attrs \\ []) do
    render_component(
      &DownloadStrip.download_strip/1,
      Keyword.merge([download: download, queue_item_id: "job", cancel_title: "Sample Show"], attrs)
    )
  end

  test "a transfer draws the word, the figure, the ETA, the size and the client" do
    html =
      strip(
        download(:torrent, :downloading, %{
          status: "downloading",
          progress: 42.0,
          size: 4_200_000_000,
          timeleft: "12m"
        })
      )

    assert html =~ "Downloading"
    assert html =~ "42%"
    assert html =~ "ETA 12m"
    assert html =~ "4.2 GB"
    assert html =~ "qBittorrent"
    assert html =~ ~s|style="width: 42%"|
  end

  test "the ladder lights the current step and fills the steps behind it" do
    html = strip(download(:usenet, :extracting, %{stage_line: "Unpacking: 45%", timeleft: "3m"}))

    assert html =~ ~s|data-step="fetch" data-step-state="landed"|
    assert html =~ ~s|data-step="download" data-step-state="landed"|
    assert html =~ ~s|data-step="verify" data-step-state="landed"|
    assert html =~ ~s|data-step="unpack" data-step-state="underway"|
    assert html =~ ~s|data-step="move" data-step-state="ahead"|
    assert html =~ "Unpacking"
    assert html =~ "45%"
    assert html =~ ~s|style="width: 45%"|
    refute html =~ "ETA"
  end

  test "a working step with no figure draws the indeterminate bar" do
    html = strip(download(:usenet, :moving, %{stage_line: nil}))

    assert html =~ "Moving"
    assert html =~ "progress-indeterminate"
    refute html =~ ~r/\d+%/
  end

  test "fetching the NZB is step one with the indeterminate bar and no figure" do
    html = strip(download(:usenet, :fetching_nzb, %{progress: 19.0}))

    assert html =~ ~s|data-step="fetch" data-step-state="underway"|
    assert html =~ "Fetching NZB"
    assert html =~ "progress-indeterminate"
    refute html =~ "19%"
  end

  test "a held job keeps its figure but gets no motion" do
    html = strip(download(:torrent, :paused, %{progress: 50.0}))

    assert html =~ "Paused"
    assert html =~ ~s|style="width: 50%"|
    refute html =~ "progress-indeterminate"
  end

  test "a failed job has no lit step and no bar" do
    html = strip(download(:usenet, :error, %{}))

    assert html =~ "Failed"
    refute html =~ ~s|data-step-state="underway"|
    refute html =~ "progress-fill"
    refute html =~ "progress-indeterminate"
  end

  test "the state word is plain text, never a badge" do
    html = strip(download(:usenet, :verifying, %{}))
    refute html =~ "badge"
  end

  test "cancel renders only with a queue item id, armed when the id matches" do
    download = download(:torrent, :downloading, %{progress: 10.0})

    refute strip(download, queue_item_id: nil) =~ "cancel_download"
    assert strip(download) =~ ~s|phx-value-id="job"|
    assert strip(download, cancel_armed_id: "job") =~ "Click again to cancel"
  end

  test "cancel carries the release name when the host gives no title" do
    html = strip(download(:torrent, :downloading, %{progress: 10.0}), cancel_title: nil)
    assert html =~ ~s|phx-value-title="Sample.Show.S01E01.1080p.WEB-DL"|
  end

  test "telemetry age qualifies the figures" do
    html =
      strip(download(:torrent, :downloading, %{progress: 10.0}), telemetry_age: "last seen 4m ago")

    assert html =~ "last seen 4m ago"
  end
end
