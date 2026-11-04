defmodule MediaCentaurWeb.Storybook.ReleaseTracking.CaughtUp do
  @moduledoc """
  The *Caught up through* row on a followed series' tracking card
  (campaign `discovery.md`, M16): the season and episode selects bounded
  by the latest aired episode, and the one-press Caught up button.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReleaseTracking.CaughtUp.caught_up_row/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-sm p-4 pb-64">
      <.psb-variation/>
    </div>
    """
  end

  defp base(overrides) do
    Map.merge(
      %{
        id: "caught-up-story",
        ref: "tv_series-1399",
        point: {2, 5},
        latest: {3, 4},
        season_sizes: %{"1" => 10, "2" => 10, "3" => 4}
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :behind,
        description:
          "Caught up through S02E05 of a show in its third season: episodes after the point are out.",
        attributes: base(%{})
      },
      %Variation{
        id: :at_latest,
        description: "Caught up to the latest aired episode — the usual state right after Follow.",
        attributes: base(%{point: {3, 4}})
      },
      %Variation{
        id: :season_open,
        description: "The season list open: every season up to the latest aired one.",
        attributes: base(%{open: :season})
      },
      %Variation{
        id: :episode_open,
        description: "The episode list open for the point's season, first to last aired.",
        attributes: base(%{open: :episode})
      },
      %Variation{
        id: :no_point,
        description: "A series TMDB has aired nothing of: no point to show, only the button.",
        attributes: base(%{point: nil, latest: nil})
      }
    ]
  end
end
