defmodule MediaCentaurWeb.Components.Detail.MoreInfo.FileDetails do
  @moduledoc """
  Technical facts probed from the entry's backing file(s)
  (`Library.FileMediaInfo`), rendered in the More-info pane: the
  container's own embedded title, measured duration, video codec +
  resolution, and the audio-track summary.

  Display-only — no judgement, no thresholds. The point is that the
  file's *own claims* sit next to the matched metadata: a renamed fake
  release usually still carries its original container title, and a
  duration that disagrees with the runtime is visible at a glance
  instead of only at playback.

  Renders nothing when no file has been probed (missing ffprobe,
  pre-feature import) — absence of data is not a state worth chrome.
  """

  use Phoenix.Component

  alias MediaCentaur.Library.Views.DetailItem

  attr :files, :list,
    required: true,
    doc:
      "[%DetailItem.WatchedFile{}] — only files whose :media_info is present render; an empty or unprobed list renders nothing."

  def file_details(assigns) do
    assigns = assign(assigns, :probed, Enum.filter(assigns.files, & &1.media_info))

    ~H"""
    <section :if={@probed != []} class="space-y-2">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">File details</h3>
      <div
        :for={file <- @probed}
        id={"file-details-#{:erlang.phash2(file.path)}"}
        class="glass-inset rounded-lg px-3 py-2.5 space-y-1"
      >
        <div :if={file.media_info.container_title} class="flex items-baseline gap-2 min-w-0">
          <span class="text-xs uppercase tracking-wider text-base-content/40 shrink-0">
            Container title
          </span>
          <span class="truncate text-sm text-base-content/80" title={file.media_info.container_title}>
            {file.media_info.container_title}
          </span>
        </div>
        <div :if={tech_line(file.media_info) != ""} class="text-sm text-base-content/60">
          {tech_line(file.media_info)}
        </div>
      </div>
    </section>
    """
  end

  @doc """
  One compact " · "-joined line of the probed technical facts, e.g.
  `"1h 41m · HEVC · 3840×2160 · DTS-HD MA 5.1"`. Empty string when
  nothing was probed. Public for unit tests (ADR-030).
  """
  @spec tech_line(DetailItem.WatchedFile.media_info()) :: String.t()
  def tech_line(media_info) do
    [
      format_duration(media_info.duration_seconds),
      media_info.video_codec,
      resolution(media_info),
      media_info.audio_summary
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # UIDR-004: `Xh Ym`, hours omitted when zero, no seconds.
  defp format_duration(nil), do: nil

  defp format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if hours > 0, do: "#{hours}h #{minutes}m", else: "#{minutes}m"
  end

  defp resolution(%{width: width, height: height}) when is_integer(width) and is_integer(height) do
    "#{width}×#{height}"
  end

  defp resolution(_media_info), do: nil
end
