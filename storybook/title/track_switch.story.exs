defmodule MediaCentaurWeb.Storybook.Title.TrackSwitch do
  @moduledoc """
  The Track release dates switch (UIDR-042): on at Follow and above,
  held on at Grab. Drawn by the tracking controls and by the finish
  prompt for a show the person is caught up on, where the title may not
  be on the list yet — switching it on from Off lists it at Follow.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.TrackingControls.track_switch/1
  def render_source, do: :function

  def template do
    """
    <div class="w-64">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :rungs,
        description: "Each rung, for a series.",
        variations:
          for rung <- [nil, :ignored, :list, :follow, :grab] do
            %Variation{
              id: rung || :off,
              attributes: %{
                id: "track-switch-#{rung || :off}",
                ref: "tv_series-1399",
                rung: rung,
                media_type: :tv_series
              }
            }
          end
      },
      %Variation{
        id: :movie,
        description: "A movie's line names its release dates.",
        attributes: %{id: "track-switch-movie", ref: "movie-603", rung: :list, media_type: :movie}
      }
    ]
  end
end
