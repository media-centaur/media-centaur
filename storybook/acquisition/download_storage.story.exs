defmodule MediaCentaurWeb.Storybook.Acquisition.DownloadStorage do
  @moduledoc "Remaining-storage indicator for the download screen — per-drive free space (grouped by mount point), coloured by headroom severity."

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Acquisition.DownloadStorage.download_storage/1
  def render_source, do: :function

  @gib 1_073_741_824

  defp drive(mount_point, total_gib, used_gib, usage_percent) do
    %{
      mount_point: mount_point,
      device: "/dev/sd" <> String.slice(mount_point, -1..-1),
      total_bytes: round(total_gib * @gib),
      used_bytes: round(used_gib * @gib),
      usage_percent: usage_percent,
      roles: [%{label: "Media dir", path: mount_point}]
    }
  end

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :healthy,
        description: "Plenty of headroom — calm green bars",
        attributes: %{drives: [drive("/mnt/media", 4000, 1200, 30)]}
      },
      %Variation{
        id: :multiple_drives,
        description:
          "Two physical disks — one with ample room (calm), one under 100 GiB free (amber warning)",
        attributes: %{
          drives: [
            drive("/mnt/media", 4000, 1200, 30),
            drive("/mnt/media2", 500, 420, 84)
          ]
        }
      },
      %Variation{
        id: :critical_percent,
        description: "Large disk, 96% full — red on the usage backstop despite a big free number",
        attributes: %{drives: [drive("/mnt/media", 8000, 7680, 96)]}
      },
      %Variation{
        id: :critical_absolute,
        description: "Small disk at 50% usage but under 20 GiB free — the absolute floor fires",
        attributes: %{drives: [drive("/mnt/scratch", 30, 15, 50)]}
      },
      %Variation{
        id: :empty,
        description: "No measured drives (still measuring / none configured) — renders nothing",
        attributes: %{drives: []}
      }
    ]
  end
end
