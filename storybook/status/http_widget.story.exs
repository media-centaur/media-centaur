defmodule MediaCentaurWeb.Storybook.Status.HttpWidget do
  @moduledoc """
  Connections Activity widget: the request strip chart shell over the
  selected window plus the recent-requests feed. Strips render from
  frames under a live socket (`StripChart.Feed`); here the hook container
  is empty and the window pills, legend and feed are the contract.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Http.http_widget/1
  def render_source, do: :function
  def layout, do: :one_column

  defp seconds_ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp recent do
    [
      %{
        seq: 3,
        at: seconds_ago(3),
        upstream: :tmdb,
        method: :get,
        path: "/3/tv/1/season/1",
        status: 200,
        error: nil,
        duration_ms: 180,
        cache: :miss
      },
      %{
        seq: 2,
        at: seconds_ago(9),
        upstream: :tmdb_images,
        method: :get,
        path: "/t/p/w500/sample.jpg",
        status: 200,
        error: nil,
        duration_ms: 95,
        cache: :uncached
      },
      %{
        seq: 1,
        at: seconds_ago(40),
        upstream: :prowlarr,
        method: :get,
        path: "/api/v1/search",
        status: nil,
        error: "timeout",
        duration_ms: 5_000,
        cache: :uncached
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :hour,
        description: "1h window, feed collapsed",
        attributes: %{traffic_window: :"1h", traffic_recent: recent()}
      },
      %Variation{
        id: :month_empty_feed,
        description: "1mo window, no recent requests",
        attributes: %{traffic_window: :"1mo", traffic_recent: []}
      },
      %Variation{
        id: :windows,
        description: ~s(Every window value the pill offers: :"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"),
        attributes: %{traffic_window: :"5m", traffic_recent: []}
      }
    ]
  end
end
