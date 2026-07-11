defmodule MediaCentaurWeb.Storybook.Upcoming.TitleDetail do
  @moduledoc "The per-title detail slide-over — automation, release timeline, activity, stop-tracking. Gated variant hides automation when acquisition is unconfigured."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.ReleaseTracking.Detail

  def function, do: &MediaCentaurWeb.Components.ReleaseTracking.TitleDetail.title_detail/1
  def render_source, do: :function

  @today ~D[2026-06-14]

  defp timeline do
    [
      %Event{
        id: Ecto.UUID.generate(),
        item_id: Ecto.UUID.generate(),
        item_name: "Sample Show",
        media_type: :tv_series,
        kind: :episode,
        season_number: 2,
        episode_number: 4,
        air_date: ~D[2026-06-17],
        status: :armed
      },
      %Event{
        id: Ecto.UUID.generate(),
        item_id: Ecto.UUID.generate(),
        item_name: "Sample Show",
        media_type: :tv_series,
        kind: :episode,
        season_number: 2,
        episode_number: 5,
        air_date: ~D[2026-06-24],
        status: :upcoming
      }
    ]
  end

  defp activity do
    [
      %{text: "New episodes announced", at: "2d ago"},
      %{text: "Began tracking", at: "3w ago"}
    ]
  end

  def variations do
    [
      %Variation{
        id: :acquisition_on,
        description: "Full detail — automation toggle on",
        attributes: %{
          today: @today,
          detail: %Detail{
            item_id: Ecto.UUID.generate(),
            name: "Sample Show",
            media_type: :tv_series,
            acquisition?: true,
            auto_grab: %{on?: true, label: "Auto-grabbing every release"},
            timeline: timeline(),
            activity: activity()
          }
        }
      },
      %Variation{
        id: :acquisition_gated,
        description: "Acquisition unconfigured — automation section hidden, pure info",
        attributes: %{
          today: @today,
          detail: %Detail{
            item_id: Ecto.UUID.generate(),
            name: "Sample Show",
            media_type: :tv_series,
            acquisition?: false,
            auto_grab: %{on?: false, label: "Acquisition not configured"},
            timeline: timeline(),
            activity: activity()
          }
        }
      }
    ]
  end
end
