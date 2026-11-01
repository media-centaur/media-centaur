defmodule MediaCentaurWeb.Storybook.PosterRow.GroupedPosterRow do
  @moduledoc """
  One scroll row of labelled groups of poster tiles with a hairline
  between them — Discovery's Watchlist shelf, In Theaters · Coming Up.
  The tiles are `poster_row/1`'s; the groups are
  `%{label: String.t(), items: [Item.t()]}` in order. An empty group is
  omitted; a row whose groups are all empty renders nothing.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.PosterRow.Item

  def function, do: &MediaCentaurWeb.Components.PosterRow.grouped_poster_row/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :two_groups,
        description:
          "In Theaters with opening dates, then Coming Up with release months, " <>
            "one hairline between them; each tile a TMDB identity with its marker.",
        attributes: %{
          id: "story-grouped-row",
          show_play_button: false,
          groups: [
            %{label: "In Theaters", items: tiles(1..3, "Oct", "Tracking")},
            %{label: "Coming Up", items: tiles(4..9, "Dec", "On your list")}
          ]
        }
      },
      %Variation{
        id: :one_group,
        description: "An empty group drops out: only Coming Up is drawn, no hairline.",
        attributes: %{
          id: "story-grouped-one",
          show_play_button: false,
          groups: [
            %{label: "In Theaters", items: []},
            %{label: "Coming Up", items: tiles(1..4, "Jan 2027", nil)}
          ]
        }
      },
      %Variation{
        id: :empty,
        description: "Every group empty — the row renders nothing.",
        attributes: %{id: "story-grouped-empty", groups: [%{label: "In Theaters", items: []}]}
      }
    ]
  end

  defp tiles(range, chip, marker) do
    for i <- range do
      %Item{
        id: "tile-#{i}",
        ref: {300 + i, :movie},
        name: "Movie #{i}",
        year: "2026",
        poster_url: poster_placeholder(i),
        chip: if(chip == "Oct", do: "Oct #{i + 10}", else: chip),
        marker: marker
      }
    end
  end

  defp poster_placeholder(i) do
    shade = 100 + i * 10
    hex = shade |> min(255) |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.duplicate(3)
    "https://placehold.co/200x300/#{hex}/ffffff?text=#{i}"
  end
end
