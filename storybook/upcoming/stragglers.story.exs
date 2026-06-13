defmodule MediaCentaurWeb.Storybook.Upcoming.Stragglers do
  @moduledoc "Tracked titles with nothing scheduled yet — the quiet catch-all below the rail."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Straggler

  def function, do: &MediaCentaurWeb.Components.Upcoming.Stragglers.stragglers/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-md p-4 bg-base-100 rounded-xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :populated,
        description: "A hiatus show and a movie with no announced date",
        attributes: %{
          stragglers: [
            %Straggler{item_id: Ecto.UUID.generate(), name: "Evergreen Heights", media_type: :tv_series},
            %Straggler{item_id: Ecto.UUID.generate(), name: "Movie A", media_type: :movie}
          ]
        }
      },
      %Variation{
        id: :empty,
        description: "Nothing to show — renders nothing",
        attributes: %{stragglers: []}
      }
    ]
  end
end
