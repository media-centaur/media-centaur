defmodule MediaCentaurWeb.Storybook.Composites.StripChart do
  @moduledoc """
  Shell of the strip chart: card header, the window control on the house
  segmented pill, legend and footer slot. The strips themselves render
  from frames pushed to the `StripChart` hook under a live socket
  (`MediaCentaurWeb.Components.StripChart.Feed`); in isolation the hook
  container is empty, and the `phx-hook` / `phx-update="ignore"` wiring
  plus the pills' `aria-pressed` are the contract the story locks.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StripChart.strip_chart/1
  def render_source, do: :function
  def layout, do: :one_column

  @legend [
    %{label: "failed", tone: "error"},
    %{label: "went out", tone: "solid"},
    %{label: "from cache", tone: "muted"},
    %{label: "mean latency", tone: "line"}
  ]

  def variations do
    [
      %Variation{
        id: :default_window,
        description: "Default 1h window, four-item legend, no footer",
        attributes: %{
          id: "story-traffic",
          title: "Requests",
          lede: "Requests are what went out; cache is what was answered here instead.",
          window: :"1h",
          windows: [:"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"],
          legend: @legend
        }
      },
      %Variation{
        id: :month_with_footer,
        description: "1mo selected, footer slot filled",
        attributes: %{
          id: "story-traffic-month",
          title: "Requests",
          window: :"1mo",
          legend: @legend
        },
        slots: [
          """
          <:footer><span class="text-xs text-base-content/55">Recent requests ▸</span></:footer>
          """
        ]
      }
    ]
  end
end
