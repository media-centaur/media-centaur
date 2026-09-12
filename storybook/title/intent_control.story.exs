defmodule MediaCentaurWeb.Storybook.Title.IntentControl do
  @moduledoc """
  The one control for a title (UIDR-035, UIDR-036, UIDR-039). A title not
  on the list shows nothing here — the bookmark in the action strip lists
  it; a listed one shows the tracking controls — Ignore · Off · List ·
  Follow · Ask · Grab · Default, the pressed rung `aria-pressed`, with the
  selected rung's consequence, the notes and the quality acceptance row
  beneath. Ignore is the strongest no — a record that keeps friends'
  reviews and listings of the title off the Feed.

  One control replacing two: a watchlist Add/Remove *and* a tracking-mode
  strip used to express one record, and could contradict each other.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.IntentControl.intent_control/1

  defp base(overrides) do
    Map.merge(
      %{
        id: "intent-control-story",
        ref: "tv_series-1399",
        rung: :follow,
        default_grab_mode: "ask",
        acquisition?: true,
        lower_quality_accepted?: false
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :not_listed,
        description:
          "A title with no record (nil rung reads as Off): nothing — listing is the " <>
            "bookmark's act in the action strip, and nothing above List is reachable " <>
            "until it is on the list (UIDR-039).",
        attributes: base(%{rung: nil})
      },
      %Variation{
        id: :ignored,
        description: "An ignored title shows the one line that says the Feed is hiding it.",
        attributes: base(%{rung: :ignored})
      },
      %VariationGroup{
        id: :rungs,
        description:
          "A listed title's tracking controls: every rung, pressed, with its one-line consequence beneath.",
        variations:
          for rung <- [:list, :follow, :ask, :grab, :default] do
            %Variation{id: rung, attributes: base(%{rung: rung})}
          end
      },
      %Variation{
        id: :default_resolves_to_off,
        description: "The Default segment names what the global setting resolves to right now.",
        attributes: base(%{rung: :default, default_grab_mode: "off"})
      },
      %Variation{
        id: :acquisition_missing,
        description:
          "No indexer or download client yet: the grab rungs stay selectable, and the " <>
            "note says plainly that they download nothing until one is set up.",
        attributes: base(%{rung: :default, default_grab_mode: "all_releases", acquisition?: false})
      },
      %Variation{
        id: :lower_quality_accepted,
        description:
          "The per-title quality acceptance (ADR-063 §2) with its Reset. Keyed by TMDB " <>
            "identity, so it shows at any rung — including a title nobody follows.",
        attributes: base(%{rung: :grab, lower_quality_accepted?: true})
      }
    ]
  end
end
