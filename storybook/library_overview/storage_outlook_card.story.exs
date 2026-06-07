defmodule MediaCentaurWeb.Storybook.LibraryOverview.StorageOutlookCard do
  @moduledoc """
  "Storage outlook" card — per-drive headroom bars plus a consolidated
  drive-offline at-risk warning. Fed `Storage.measure_all/0` drive maps and a
  summarized at-risk map (`StatusHelpers.summarize_at_risk/4`).
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.LibraryOverviewComponents.storage_outlook_card/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :healthy,
        description: "Two drives with comfortable headroom.",
        attributes: %{
          drives: [
            drive("Media", "/media", 42),
            drive("Database", "/var/lib/media-centaur", 18)
          ],
          at_risk: nil
        }
      },
      %Variation{
        id: :near_full,
        description: "A drive crossing the warning (75%) and error (90%) thresholds.",
        attributes: %{
          drives: [drive("Media", "/media", 92), drive("Backup", "/backup", 78)],
          at_risk: nil
        }
      },
      %Variation{
        id: :at_risk,
        description: "Offline-drive at-risk warning with a purge horizon.",
        attributes: %{
          drives: [drive("Media", "/media", 60)],
          at_risk: %{file_count: 14, purge_in_days: 4}
        }
      },
      %Variation{
        id: :purge_now,
        description: "At-risk files already purge-eligible (drive still offline).",
        attributes: %{
          drives: [drive("Media", "/media", 60)],
          at_risk: %{file_count: 3, purge_in_days: 0}
        }
      },
      %Variation{
        id: :measuring,
        description: "No drives measured yet — the card shows its loading line.",
        attributes: %{drives: [], at_risk: nil}
      }
    ]
  end

  defp drive(label, path, usage_percent) do
    total = 4_000_000_000_000
    used = round(total * usage_percent / 100)

    %{
      mount_point: path,
      device: "/dev/sample",
      used_bytes: used,
      total_bytes: total,
      usage_percent: usage_percent,
      roles: [%{label: label, path: path}]
    }
  end
end
