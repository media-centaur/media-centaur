defmodule MediaCentaurWeb.Storybook.Incoming.Shelf do
  @moduledoc """
  The Coming-up shelf — a nearness-ordered agenda list of date-led
  rows, the horizon action row after the last entry, and the undated
  straggler rows under a "Not scheduled yet" hairline (UIDR-017). No
  section header: the zone tab (or, forecast-only, the rows
  themselves) names the view.
  """

  use PhoenixStorybook.Story, :component

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

  defp straggler_rows do
    [
      %Card{
        key: "straggler-101",
        item_id: 101,
        title: "Sherlock Jr.",
        subtitle: "Movie",
        status: :tracked,
        kind: :title
      },
      %Card{
        key: "straggler-102",
        item_id: 102,
        title: "Safety Last!",
        subtitle: "Movie",
        status: :tracked,
        kind: :title
      },
      %Card{
        key: "straggler-103",
        item_id: 103,
        title: "A Trip to the Moon",
        subtitle: "Movie",
        status: :tracked,
        kind: :title
      }
    ]
  end

  # The same forecast with acquisition off: no will-grab / in-pursuit pills —
  # will-grab rows degrade to plain dated rows so nothing surviving implies
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
            "tracked episode, a will-grab episode, a season drop, an in-theaters feature, " <>
            "and a tracked feature.",
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
        id: :stragglers_collapsed,
        description:
          "The default: tracked titles with nothing scheduled sit collapsed behind " <>
            "the \"Not scheduled yet · N\" toggle row — quiet bookkeeping until asked " <>
            "for (UIDR-017).",
        attributes: %{cards: full_mix(), stragglers: straggler_rows()}
      },
      %Variation{
        id: :stragglers_expanded,
        description:
          "Expanded: real rows under the hairline — empty date slot (muted em-dash " <>
            "keeps the columns aligned), media type as the subtitle, neutral Tracked " <>
            "pill; same anatomy, same click-through as dated rows.",
        attributes: %{
          cards: full_mix(),
          stragglers: straggler_rows(),
          stragglers_expanded?: true
        }
      },
      %Variation{
        id: :stragglers_only,
        description:
          "Nothing dated but titles still tracked: the toggle (and, expanded, the " <>
            "rows) renders on its own — presence never depends on the schedule.",
        attributes: %{cards: [], stragglers: straggler_rows(), stragglers_expanded?: true}
      }
    ]
  end
end
