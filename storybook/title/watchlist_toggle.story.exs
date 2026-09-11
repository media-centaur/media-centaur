defmodule MediaCentaurWeb.Storybook.Title.WatchlistToggle do
  @moduledoc """
  The bookmark (UIDR-039): outline off the list, solid with the primary
  tint on it, `aria-pressed` carrying the state. It works the bottom of
  the record only — List for a title with no record or an ignored one,
  Off for one at List — and at Follow and above it is a marker with no
  click, because a one-click must not tear down a release calendar.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.WatchlistToggle.watchlist_toggle/1

  defp base(overrides) do
    Map.merge(
      %{id: "watchlist-toggle-story", rung: nil, event: "set_rung", "phx-value-ref": "movie-550"},
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :off_the_list,
        description: "No record: the outline bookmark, and a click sets List.",
        attributes: base(%{rung: nil})
      },
      %Variation{
        id: :ignored,
        description:
          "Ignored is off the list too: the same outline, and a click sets List — replacing Ignore.",
        attributes: base(%{rung: :ignored})
      },
      %Variation{
        id: :listed,
        description: "At List: filled, and a click sets Off — nothing tracked is torn down.",
        attributes: base(%{rung: :list})
      },
      %VariationGroup{
        id: :followed_marker,
        description:
          "At Follow and above: filled, and no click at all — the marker. Off is in the " <>
            "tracking controls, which state that they delete the calendar.",
        variations:
          for rung <- [:follow, :ask, :grab, :default] do
            %Variation{id: rung, attributes: base(%{rung: rung})}
          end
      }
    ]
  end
end
