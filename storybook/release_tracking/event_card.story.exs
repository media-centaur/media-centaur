defmodule MediaCentaurWeb.Storybook.Upcoming.EventCard do
  @moduledoc "A release event on the Upcoming rail — hero and compact variants across every status (colour reserved for status)."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  def function, do: &MediaCentaurWeb.Components.ReleaseTracking.EventCard.event_card/1
  def render_source, do: :function

  @today ~D[2026-06-14]

  def template do
    """
    <div class="max-w-2xl space-y-3 p-4 bg-base-100 rounded-xl">
      <.psb-variation/>
    </div>
    """
  end

  defp episode(status, name, season, episode, air_date, extra \\ %{}) do
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
        status: status
      },
      extra
    )
  end

  defp movie(status, name, release_type, air_date) do
    %Event{
      id: Ecto.UUID.generate(),
      item_id: Ecto.UUID.generate(),
      item_name: name,
      media_type: :movie,
      kind: :movie,
      release_type: release_type,
      air_date: air_date,
      status: status
    }
  end

  def variations do
    [
      %VariationGroup{
        id: :compact_statuses,
        description: "Compact rows across every status — colour appears only on the status affordance",
        variations: [
          %Variation{
            id: :armed,
            attributes: %{
              variant: :compact,
              today: @today,
              event: episode(:armed, "Sample Show", 2, 4, ~D[2026-06-17])
            }
          },
          %Variation{
            id: :under_pursuit,
            attributes: %{
              variant: :compact,
              today: @today,
              event:
                episode(:under_pursuit, "Nightfall Manor", 1, 8, ~D[2026-06-14], %{
                  pursuit_id: Ecto.UUID.generate()
                })
            }
          },
          %Variation{
            id: :in_library,
            attributes: %{
              variant: :compact,
              today: @today,
              event: episode(:in_library, "Harbor Lights", 3, 1, ~D[2026-06-14])
            }
          },
          %Variation{
            id: :theatrical_info,
            attributes: %{
              variant: :compact,
              today: @today,
              event: movie(:theatrical_info, "The Cartographer", "theatrical", ~D[2026-06-30])
            }
          },
          %Variation{
            id: :upcoming_neutral,
            attributes: %{
              variant: :compact,
              today: @today,
              event: episode(:upcoming, "Evergreen Heights", 1, 1, ~D[2026-06-21])
            }
          },
          %Variation{
            id: :season_drop,
            attributes: %{
              variant: :compact,
              today: @today,
              event: %Event{
                id: Ecto.UUID.generate(),
                item_id: Ecto.UUID.generate(),
                item_name: "Another Series",
                media_type: :tv_series,
                kind: :season_drop,
                season_number: 2,
                episode_count: 8,
                air_date: ~D[2026-06-22],
                status: :armed
              }
            }
          }
        ]
      },
      %VariationGroup{
        id: :hero_variants,
        description: "Proximity-scaled hero cards for the nearest releases",
        variations: [
          %Variation{
            id: :hero_armed,
            attributes: %{
              variant: :hero,
              today: @today,
              event: movie(:armed, "The Cartographer", "digital", ~D[2026-06-17])
            }
          },
          %Variation{
            id: :hero_under_pursuit,
            attributes: %{
              variant: :hero,
              today: @today,
              event:
                episode(:under_pursuit, "Nightfall Manor", 1, 8, ~D[2026-06-14], %{
                  pursuit_id: Ecto.UUID.generate()
                })
            }
          },
          %Variation{
            id: :feature,
            description: "The second-nearest release — a smaller feature banner",
            attributes: %{
              variant: :feature,
              today: @today,
              event: episode(:armed, "Sample Show", 2, 4, ~D[2026-06-17])
            }
          }
        ]
      }
    ]
  end
end
