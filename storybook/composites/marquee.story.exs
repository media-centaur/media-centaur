defmodule MediaCentaurWeb.Storybook.Composites.Marquee do
  @moduledoc """
  The marquee: the lead tile, then columns of up to three tiles, ending in
  the See all tile, which takes the slot after the last tile. One variation
  per show count Home's Coming Up can produce (it caps at 10). Widths come
  from the row's width (`.row-scroll-marquee`), so resize the browser to see
  the formula hold. No artwork in the catalog: the tiles show their glass
  and text.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.Marquee
  alias MediaCentaurWeb.Components.Marquee.Item

  def function, do: &Marquee.marquee/1
  def render_source, do: :function
  def layout, do: :one_column

  # A full-width block gives the row the sandbox's width, as a page's column
  # does in the app (the sandbox centres its items).
  def template do
    """
    <div class="w-full" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  @shows [
    {"Sample Show A", "Tonight · S05E04", "+ 6 more this season", nil},
    {"Sample Show B", "Tomorrow", "S02E08", %{label: "Downloading", variant: :info}},
    {"Movie C", "In theaters · Sat", nil, nil},
    {"Sample Show D", "Sun", "+ 3 more", nil},
    {"Sample Show E", "Mon", "S01E01", %{label: "Acquired", variant: :success}},
    {"Movie F", "Nov 14", nil, nil},
    {"Sample Show G", "Nov 15", "+ 9 more", nil},
    {"Sample Show H", "Nov 18", "S03E02", nil},
    {"Sample Show I", "Nov 21", "+ 1 more", %{label: "Seeking", variant: :info}},
    {"Sample Show J", "Nov 27", "S04E10", nil}
  ]

  def variations do
    for(
      count <- [1, 2, 3, 4, 5, 6, 7, 8, 10],
      do: %Variation{
        id: String.to_atom("shows_#{count}"),
        description: description(count),
        attributes: %{id: "marquee-#{count}", items: items(count), see_all_href: "/watchlist"}
      }
    ) ++
      [
        %Variation{
          id: :no_page,
          description: "No page to see — the columns hold the tiles alone",
          attributes: %{id: "marquee-no-page", items: items(5), see_all_href: nil}
        }
      ]
  end

  defp description(1), do: "1 show — See all alone in the column beside the lead tile"
  defp description(10), do: "10 shows, the cap — three full columns, See all alone in a fourth"
  defp description(count), do: "#{count} shows"

  defp items(count) do
    @shows
    |> Enum.take(count)
    |> Enum.with_index(1)
    |> Enum.map(fn {{name, eyebrow, line, badge}, index} ->
      %Item{
        entity_id: "story-#{index}",
        ref: {index, :tv_series},
        name: name,
        eyebrow: eyebrow,
        badge: badge,
        backdrop_url: nil,
        logo_url: nil,
        line: line
      }
    end)
  end
end
