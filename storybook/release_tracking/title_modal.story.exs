defmodule MediaCentaurWeb.Storybook.ReleaseTracking.TitleModal do
  @moduledoc """
  The per-title depth surface — the centered modal every Coming-up row
  (dated or straggler) opens (UIDR-017). One idiom for depth: same
  physics as the pursuit modal on the same page. Featured next release
  first, then automation, timeline, activity, and the sole
  error-tinted Stop tracking.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.ReleaseTracking.Detail

  def function, do: &MediaCentaurWeb.Components.ReleaseTracking.TitleModal.title_modal/1
  def render_source, do: :function
  def layout, do: :one_column

  # The component renders the cinematic frame — a real `position: fixed`
  # overlay — so variations would stack in a shared DOM. Iframing
  # isolates them (same treatment as the detail_panel story).
  def container, do: {:iframe, style: "min-height: 720px; width: 100%;"}

  @today ~D[2026-08-03]

  defp scheduled_detail do
    %Detail{
      item_id: "sample-show",
      name: "Sample Show",
      media_type: :tv_series,
      backdrop_url: nil,
      logo_url: nil,
      acquisition?: true,
      auto_grab: %{on?: true, label: "Auto-grabbing every release"},
      tracking_since: ~N[2026-03-14 12:00:00],
      timeline: [
        %Event{
          id: "s02e05",
          item_id: "sample-show",
          item_name: "Sample Show",
          media_type: :tv_series,
          title: "The Vanishing Reel",
          air_date: @today,
          season_number: 2,
          episode_number: 5,
          status: :armed,
          kind: :episode
        },
        %Event{
          id: "s02e06",
          item_id: "sample-show",
          item_name: "Sample Show",
          media_type: :tv_series,
          air_date: ~D[2026-08-11],
          season_number: 2,
          episode_number: 6,
          status: :upcoming,
          kind: :episode
        },
        %Event{
          id: "s02e04",
          item_id: "sample-show",
          item_name: "Sample Show",
          media_type: :tv_series,
          air_date: ~D[2026-07-27],
          season_number: 2,
          episode_number: 4,
          status: :in_library,
          kind: :episode
        }
      ],
      activity: [
        %{text: "Grabbed S02E04", at: "6 days ago"},
        %{text: "Started tracking", at: "4 months ago"}
      ]
    }
  end

  defp straggler_detail do
    %Detail{
      item_id: "hiatus-show",
      name: "The Phantom Carriage",
      media_type: :tv_series,
      backdrop_url: nil,
      logo_url: nil,
      acquisition?: true,
      auto_grab: %{on?: false, label: "Not auto-grabbing"},
      tracking_since: ~N[2026-05-02 12:00:00],
      timeline: [],
      activity: [%{text: "Started tracking", at: "3 months ago"}]
    }
  end

  def variations do
    [
      %Variation{
        id: :scheduled_title,
        description:
          "A weekly show with releases ahead: the featured slot answers \"what's " <>
            "next\" (tonight's episode, Will grab), then automation, the timeline " <>
            "(landed entries keep their success label), activity, Stop tracking.",
        attributes: %{open: true, detail: scheduled_detail(), today: @today}
      },
      %Variation{
        id: :straggler_title,
        description:
          "A tracked title with nothing scheduled: the featured slot states the " <>
            "absence plainly instead of rendering empty — same shape, same verbs " <>
            "(UIDR-017).",
        attributes: %{open: true, detail: straggler_detail(), today: @today}
      },
      %Variation{
        id: :forecast_only,
        description:
          "Acquisition not configured: no automation section, and the timeline's " <>
            "statuses carry no grab implication (honest degradation).",
        attributes: %{
          open: true,
          detail: %{
            scheduled_detail()
            | acquisition?: false,
              timeline: Enum.map(scheduled_detail().timeline, &%{&1 | status: :upcoming})
          },
          today: @today
        }
      }
    ]
  end
end
