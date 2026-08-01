defmodule MediaCentaurWeb.Storybook.Incoming.Shelf do
  @moduledoc """
  The Coming-up shelf — a nearness-ordered agenda list of date-led
  rows, the horizon action row after the last entry, the section
  header, and the quiet stragglers line.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Straggler
  alias MediaCentaurWeb.Components.Incoming.Shelf.Card

  def function, do: &MediaCentaurWeb.Components.Incoming.Shelf.shelf/1
  def render_source, do: :function
  def layout, do: :one_column

  defp full_mix do
    [
      %Card{
        key: "sample-show-s02e05",
        item_id: 1,
        pursuit_id: "0af1c2d3-0000-0000-0000-000000000001",
        title: "Sample Show",
        subtitle: "S02E05 · \"The Vanishing Reel\"",
        date_label: "Tonight",
        status: :in_pursuit,
        percent: 62,
        kind: :episode
      },
      %Card{
        key: "phantom-carriage-s01e03",
        item_id: 2,
        title: "The Phantom Carriage",
        subtitle: "S01E03 · Jul 14",
        date_label: "Tue",
        kind: :episode
      },
      %Card{
        key: "haxan-s01e06",
        item_id: 3,
        title: "Häxan",
        subtitle: "S01E06 · Jul 17",
        date_label: "Fri Jul 17",
        status: :armed,
        kind: :episode
      },
      %Card{
        key: "the-golem-s3",
        item_id: 4,
        title: "The Golem",
        subtitle: "S3",
        date_label: "Fri Jul 24",
        kind: :season_drop,
        episode_count: 8
      },
      %Card{
        key: "metropolis",
        item_id: 5,
        title: "Metropolis",
        subtitle: "Feature · home release TBA",
        date_label: "Now",
        status: :in_theaters,
        kind: :movie
      },
      %Card{
        key: "nosferatu",
        item_id: 6,
        title: "Nosferatu",
        subtitle: "Feature · home release",
        date_label: "Aug 6",
        status: :tracked,
        kind: :movie
      }
    ]
  end

  # The same forecast with acquisition off: no armed / in-pursuit pills —
  # armed rows degrade to plain dated rows so nothing surviving implies
  # grabbing. Watch-only identity (in theaters) stays.
  defp acquisition_off_mix do
    Enum.map(full_mix(), fn
      %Card{status: status} = card when status in [:in_pursuit, :armed, :tracked] ->
        %{card | status: nil, percent: nil, pursuit_id: nil}

      card ->
        card
    end)
  end

  def variations do
    [
      %Variation{
        id: :full_shelf,
        description:
          "Six rows, nearness-first with graduated date labels (Tonight → Tue → " <>
            "Fri Jul 17 → Fri Jul 24 → Now → Aug 6): tonight's episode in pursuit, a plain " <>
            "tracked episode, an armed episode, a season drop, an in-theaters feature, and a " <>
            "tracked feature.",
        attributes: %{cards: full_mix()}
      },
      %Variation{
        id: :acquisition_off,
        description: "Honest degradation: no armed or in-pursuit pills — plain dated rows only.",
        attributes: %{cards: acquisition_off_mix()}
      },
      %Variation{
        id: :empty_shelf,
        description:
          "Nothing tracked and nothing scheduled — the section renders nothing at " <>
            "all (no dead panels; the omnibox is the standing track affordance).",
        attributes: %{cards: []}
      },
      %Variation{
        id: :overflow,
        description:
          "More forecast than list: the horizon action grows the list in place " <>
            "(\"Show all N\") instead of claiming the horizon is empty.",
        attributes: %{cards: full_mix(), overflow_count: 4}
      },
      %Variation{
        id: :with_stragglers,
        description:
          "Tracked titles with nothing scheduled fold into a one-line disclosure under " <>
            "the shelf — expand for the names.",
        attributes: %{
          cards: full_mix(),
          stragglers: [
            %Straggler{item_id: 101, name: "Sherlock Jr.", media_type: :movie},
            %Straggler{item_id: 102, name: "Safety Last!", media_type: :movie},
            %Straggler{item_id: 103, name: "A Trip to the Moon", media_type: :movie}
          ]
        }
      }
    ]
  end
end
