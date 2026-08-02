defmodule MediaCentaurWeb.Storybook.Acquisition.NeedsAttention do
  @moduledoc """
  The Heads-up glyph (UIDR-016) — acquisition capability faults
  compressed to one severity-tinted triangle in the tab row, absent
  while healthy. Hover or focus reveals the details panel; click pins
  it (the `open` attr renders the pinned state for the story matrix).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Search.IndexerHealth

  def function, do: &MediaCentaurWeb.Components.Acquisition.NeedsAttention.needs_attention/1
  def render_source, do: :function

  @gib 1_073_741_824
  # Far-future retry anchors so the relative "in ~N" phrase stays visible
  # regardless of when the story renders.
  @retry_soon DateTime.add(DateTime.utc_now(:second), 720, :second)
  @retry_later DateTime.add(DateTime.utc_now(:second), 5400, :second)

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

  defp health(state, attrs) do
    struct!(
      %IndexerHealth{state: state, checked_at: DateTime.utc_now(:second)},
      attrs
    )
  end

  def template do
    """
    <div class="max-w-2xl min-h-[22rem] flex justify-end">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :healthy_renders_nothing,
        description:
          "Healthy system → no glyph at all, not a gray one (silence is the healthy state). This preview is intentionally blank.",
        attributes: %{drives: [], search_health: health(:ok, enabled_count: 2)}
      },
      %Variation{
        id: :glyph_resting,
        description:
          "A condition exists but the panel isn't open — just the tinted triangle. Hover or focus it to peek; storybook renders the resting state.",
        attributes: %{
          drives: [
            drive("/mnt/media", 500, 420, 84)
          ],
          search_health: health(:ok, enabled_count: 2)
        }
      },
      %Variation{
        id: :prowlarr_unreachable,
        description: "Prowlarr API can't be reached — error tone, names the one fix",
        attributes: %{
          drives: [],
          search_health: health(:unreachable, reason: :econnrefused),
          open: true
        }
      },
      %Variation{
        id: :search_blind_single_indexer,
        description:
          "The only enabled indexer is backing off after failures — searches return empty without asking anyone",
        attributes: %{
          drives: [],
          search_health:
            health(:blind,
              enabled_count: 1,
              retry_at: @retry_soon,
              backed_off: [%{name: "Indexer A", retry_at: @retry_soon}]
            ),
          open: true
        }
      },
      %Variation{
        id: :search_blind_many_indexers,
        description: "Every enabled indexer backed off — hour-scale retry",
        attributes: %{
          drives: [],
          search_health:
            health(:blind,
              enabled_count: 3,
              retry_at: @retry_later,
              backed_off: [
                %{name: "Indexer A", retry_at: @retry_later},
                %{name: "Indexer B", retry_at: @retry_later},
                %{name: "Indexer C", retry_at: @retry_later}
              ]
            ),
          open: true
        }
      },
      %Variation{
        id: :search_degraded,
        description: "Some indexers backing off, others live — warning tone, searches still run",
        attributes: %{
          drives: [],
          search_health:
            health(:degraded,
              enabled_count: 3,
              retry_at: @retry_soon,
              backed_off: [%{name: "Indexer B", retry_at: @retry_soon}]
            ),
          open: true
        }
      },
      %Variation{
        id: :storage_low,
        description: "Two physical disks — one ample, one under 100 GiB free (amber warning)",
        attributes: %{
          drives: [
            drive("/mnt/media", 4000, 1200, 30),
            drive("/mnt/media2", 500, 420, 84)
          ],
          search_health: health(:ok, enabled_count: 2),
          open: true
        }
      },
      %Variation{
        id: :search_and_storage,
        description: "Both card kinds sharing the grid — search fault leads",
        attributes: %{
          drives: [drive("/mnt/media2", 500, 476, 95)],
          search_health:
            health(:blind,
              enabled_count: 1,
              retry_at: @retry_soon,
              backed_off: [%{name: "Indexer A", retry_at: @retry_soon}]
            ),
          open: true
        }
      }
    ]
  end
end
