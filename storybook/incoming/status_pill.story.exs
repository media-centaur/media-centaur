defmodule MediaCentaurWeb.Storybook.Incoming.StatusPill do
  @moduledoc """
  The Incoming page's shared status vocabulary — one pill rendered by
  both the Coming-up shelf card and the in-flight torrent row, so the
  two zoom levels of one object read as the same object. Color is
  state/health only.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Incoming.StatusPill.status_pill/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :all_statuses,
        description:
          "The full union. Will grab (:armed) and landed read success, in pursuit " <>
            "reads info, failed reads error, cancelled reads muted; in theaters / " <>
            "tracked / searching stay neutral (identity, not health).",
        variations:
          for status <- [
                :armed,
                :in_pursuit,
                :in_theaters,
                :tracked,
                :searching,
                :landed,
                :failed,
                :cancelled
              ] do
            %Variation{id: status, attributes: %{status: status}}
          end
      },
      %Variation{
        id: :in_pursuit_with_percent,
        description: "In pursuit carrying its download progress.",
        attributes: %{status: :in_pursuit, percent: 62}
      },
      %Variation{
        id: :in_pursuit_anchored,
        description:
          "With an anchor the pill is a link — the shelf card jumps down to its own " <>
            "torrent row (`#pursuit-<id>`). Hover shows the brighter info border.",
        attributes: %{status: :in_pursuit, percent: 62, anchor: "#pursuit-sample-show"}
      },
      %Variation{
        id: :anchored_without_percent,
        description: "Anchored but percent unknown yet — label stays bare.",
        attributes: %{status: :in_pursuit, anchor: "#pursuit-sample-show"}
      }
    ]
  end
end
