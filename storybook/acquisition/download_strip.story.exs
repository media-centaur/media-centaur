defmodule MediaCentaurWeb.Storybook.Acquisition.DownloadStrip do
  @moduledoc """
  The one drawing of a download-client job. One variation per phase per
  protocol, then the conditions, then the strip's extras (telemetry age,
  cancel armed, no cancel). Each builds a `DownloadProgress` the way
  `QueueMatcher.to_download/1` would, from a `QueueItem` literal.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.DownloadProgress
  alias MediaCentaur.Downloads.{Phase, QueueItem}

  def function, do: &MediaCentaurWeb.Components.Acquisition.DownloadStrip.download_strip/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-xl identity-row rounded-lg px-4 py-3" style="--banner-hue: 210">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :usenet_ladder,
        description: "A usenet job at each step of its ladder.",
        variations: [
          variation(
            :fetching_nzb,
            "Fetching NZB — step one, no figure, the indeterminate bar.",
            usenet(:fetching_nzb, title: "Fetching NZB…")
          ),
          variation(
            :downloading,
            "Downloading — the client's percentage and ETA.",
            usenet(:downloading, progress: 42.0, timeleft: "12m")
          ),
          variation(
            :verifying,
            "Verifying — figure from the stage line's n/m count.",
            usenet(:verifying, stage_line: "Verifying: 14/56")
          ),
          variation(
            :repairing,
            "Repairing — the step appears on the ladder only while it happens.",
            usenet(:repairing, stage_line: "Repairing: 12%")
          ),
          variation(
            :unpacking,
            "Unpacking — figure from the stage line's percentage.",
            usenet(:extracting, stage_line: "Unpacking: 45%")
          ),
          variation(
            :moving,
            "Moving — minutes-long for a large file, no figure, indeterminate.",
            usenet(:moving, stage_line: nil)
          ),
          variation(:done, "Done.", usenet(:completed, progress: 100.0))
        ]
      },
      %VariationGroup{
        id: :torrent_ladder,
        description: "A torrent at each step of its shorter ladder.",
        variations: [
          variation(
            :metadata,
            "Fetching metadata — qBittorrent's metaDL.",
            torrent(:downloading, status: "metaDL", title: "Fetching torrent details…")
          ),
          variation(
            :downloading,
            "Downloading.",
            torrent(:downloading, progress: 42.0, timeleft: "12m")
          ),
          variation(:done, "Done.", torrent(:completed, progress: 100.0))
        ]
      },
      %VariationGroup{
        id: :conditions,
        description: "A condition speaks before the step; a held job keeps its figure without motion.",
        variations: [
          variation(:queued, "Queued — passive waiting, muted.", torrent(:queued)),
          variation(:paused, "Paused.", torrent(:paused, progress: 67.0)),
          variation(
            :stalled,
            "Stalled — the client can't make progress.",
            torrent(:stalled, progress: 12.0)
          ),
          variation(:failed, "Failed — nothing lit, no bar.", usenet(:error))
        ]
      },
      %VariationGroup{
        id: :extras,
        variations: [
          variation(
            :stale,
            "The client is lagging — figures qualified with a last-seen age.",
            torrent(:downloading, progress: 42.0, timeleft: "12m"),
            telemetry_age: "last seen 4m ago"
          ),
          variation(
            :cancel_armed,
            "Cancel armed — the control relabels and turns danger.",
            torrent(:downloading, progress: 42.0),
            cancel_armed_id: "job"
          ),
          variation(
            :no_cancel,
            "No queue item id — the modal cancels the pursuit, not the job.",
            torrent(:downloading, progress: 42.0),
            queue_item_id: nil
          ),
          variation(
            :framed,
            "Framed — without `bare`, the strip draws its own top border (the query-door pursuit row).",
            torrent(:downloading, progress: 42.0),
            bare: false
          )
        ]
      }
    ]
  end

  defp variation(id, description, download, extra \\ []) do
    %Variation{
      id: id,
      description: description,
      attributes:
        Map.merge(
          %{download: download, queue_item_id: "job", cancel_title: "Sample Show", bare: true},
          Map.new(extra)
        )
    }
  end

  defp usenet(state, opts \\ []), do: build(:usenet, "SABnzbd", state, opts)
  defp torrent(state, opts \\ []), do: build(:torrent, "qBittorrent", state, opts)

  defp build(protocol, client, state, opts) do
    item = %QueueItem{
      id: "job",
      title: Keyword.get(opts, :title, "Sample.Show.S01E01.1080p.WEB-DL"),
      status: Keyword.get(opts, :status),
      state: state,
      protocol: protocol,
      download_client: client,
      size: 4_200_000_000,
      progress: Keyword.get(opts, :progress),
      timeleft: Keyword.get(opts, :timeleft),
      stage_line: Keyword.get(opts, :stage_line)
    }

    %DownloadProgress{
      state: state,
      title: item.title,
      progress_pct: item.progress,
      size_bytes: item.size,
      eta: item.timeleft,
      client: client,
      protocol: protocol,
      phase: Phase.of(item)
    }
  end
end
