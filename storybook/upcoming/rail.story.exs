defmodule MediaCentaurWeb.Storybook.Upcoming.Rail do
  @moduledoc "The Upcoming timeline rail — bucket markers with proximity-scaled hero and compact events."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  def function, do: &MediaCentaurWeb.Components.Upcoming.Rail.rail/1
  def render_source, do: :function

  @today ~D[2026-06-14]

  def template do
    """
    <div class="max-w-3xl p-4 bg-base-100 rounded-xl">
      <.psb-variation/>
    </div>
    """
  end

  defp episode(status, name, season, episode, air_date, hero?, extra \\ %{}) do
    Map.merge(
      %Event{
        id: Ecto.UUID.generate(),
        item_id: Ecto.UUID.generate(),
        item_name: name,
        media_type: :tv_series,
        kind: :episode,
        season_number: season,
        episode_number: episode,
        air_date: air_date,
        status: status,
        hero?: hero?
      },
      extra
    )
  end

  defp populated_feed do
    %UpcomingFeed{
      buckets: %{
        today: [
          episode(:under_pursuit, "Nightfall Manor", 1, 8, ~D[2026-06-14], true, %{
            pursuit_id: Ecto.UUID.generate()
          })
        ],
        this_week: [
          episode(:armed, "Sample Show", 2, 4, ~D[2026-06-17], true),
          episode(:armed, "Detective Stories", 4, 2, ~D[2026-06-20], false)
        ],
        next_week: [
          %Event{
            id: Ecto.UUID.generate(),
            item_id: Ecto.UUID.generate(),
            item_name: "Another Series",
            media_type: :tv_series,
            kind: :season_drop,
            season_number: 2,
            episode_count: 8,
            air_date: ~D[2026-06-22],
            status: :armed,
            hero?: false
          }
        ],
        later: [
          %Event{
            id: Ecto.UUID.generate(),
            item_id: Ecto.UUID.generate(),
            item_name: "The Cartographer",
            media_type: :movie,
            kind: :movie,
            release_type: "theatrical",
            air_date: ~D[2026-06-30],
            status: :theatrical_info,
            hero?: false
          }
        ],
        beyond: []
      },
      unscheduled: []
    }
  end

  def variations do
    [
      %Variation{
        id: :populated,
        description: "A forecast with hero and compact events across buckets",
        attributes: %{feed: populated_feed(), today: @today}
      },
      %Variation{
        id: :empty,
        description: "Nothing scheduled — the calm empty state",
        attributes: %{feed: %UpcomingFeed{}, today: @today}
      }
    ]
  end
end
