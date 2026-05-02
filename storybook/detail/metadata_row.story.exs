defmodule MediaCentarrWeb.Storybook.Detail.MetadataRow do
  @moduledoc """
  Horizontal metadata row used inside the entity detail panel — a type
  badge followed by dotted text items (year, runtime, rating, status…).

  `items` is a flat list of strings; the component silently drops `nil`
  and blank entries, so calling templates don't need to guard against
  missing metadata. The `:missing_rating` and `:missing_runtime`
  variations pin that contract.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.MetadataRow.metadata_row/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :minimal,
        description:
          "Badge plus a single year — the smallest realistic strip. " <>
            "No separator dot is rendered before the first item.",
        attributes: %{
          badge_text: "Movie",
          items: ["2024"]
        }
      },
      %Variation{
        id: :full,
        description:
          "Badge plus the full quartet of items (year, runtime, rating, status). " <>
            "Items are joined with the middle-dot separator.",
        attributes: %{
          badge_text: "Movie",
          items: ["2024", "2h 8m", "PG-13", "Released"]
        }
      },
      %Variation{
        id: :missing_rating,
        description:
          "Full strip minus the rating — pins the contract that callers can pass " <>
            "`nil` for unknown fields and the row collapses gracefully.",
        attributes: %{
          badge_text: "Movie",
          items: ["2024", "2h 8m", nil, "Released"]
        }
      },
      %Variation{
        id: :missing_runtime,
        description:
          "Full strip minus the runtime — same `nil`-tolerance contract, this " <>
            "time dropping the second item.",
        attributes: %{
          badge_text: "Movie",
          items: ["2024", nil, "PG-13", "Released"]
        }
      },
      %Variation{
        id: :very_long_title,
        description:
          "Long badge text plus many items — the row uses `flex-wrap`, so items " <>
            "spill onto a second line rather than overflowing the container.",
        attributes: %{
          badge_text: "Limited Series",
          items: [
            "2024",
            "8 episodes",
            "Approximately 1h 2m",
            "TV-MA",
            "Returning Series",
            "Country of Origin"
          ]
        }
      }
    ]
  end
end
