defmodule MediaCentaurWeb.Storybook.Incoming.Ledger do
  @moduledoc """
  The History archive — the History tab's whole content, always open:
  lifecycle filter chips (All leading and default) + title/release
  search, the caller's grouped rows in the `:archive` slot, and storage
  as the ambient foot line. No glimpse, no disclosure — the zone tab
  already did the quieting the old shared-page treatment existed for.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Incoming.Ledger.ledger/1
  def render_source, do: :function
  def layout, do: :one_column

  @gib 1_073_741_824

  defp drives do
    [
      %{
        mount_point: "/mnt/media",
        device: "/dev/sda",
        total_bytes: 4000 * @gib,
        used_bytes: 1200 * @gib,
        usage_percent: 30,
        roles: [%{label: "Media dir", path: "/mnt/media"}]
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :archive,
        description:
          "The open archive: chips with All active, search on the right, the caller's " <>
            "grouped rows below, storage on the foot line.",
        attributes: %{
          filter: :all,
          search: "",
          storage_drives: drives()
        },
        slots: [
          """
          <:archive>
            <div class="scrim-surface rounded-xl px-4 py-3 text-sm">Sample Show — grouped archive rows render here</div>
          </:archive>
          """
        ]
      },
      %Variation{
        id: :filtered,
        description: "A lifecycle slice active — the chip row shows where you are.",
        attributes: %{
          filter: :failed,
          search: "",
          storage_drives: drives()
        },
        slots: [
          """
          <:archive>
            <div class="scrim-surface rounded-xl px-4 py-3 text-sm">Sample Documentary — failed rows render here</div>
          </:archive>
          """
        ]
      },
      %Variation{
        id: :empty_filter,
        description:
          "A filter that matches nothing — the filter-specific honest answer; the chips " <>
            "stay so widening the filter stays possible.",
        attributes: %{
          filter: :cancelled,
          search: "",
          archive_empty?: true
        }
      },
      %Variation{
        id: :no_history_at_all,
        description: "Nothing on record yet — All's own empty state, no storage line without data.",
        attributes: %{
          filter: :all,
          search: "",
          archive_empty?: true
        }
      }
    ]
  end
end
