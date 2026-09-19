defmodule MediaCentaurWeb.Components.StatusWidgets.Http do
  @moduledoc """
  Connections (`:http`) Activity widget: the request strip charts — one
  strip per upstream over the selected window — with the collapsed feed
  of the most recent requests in the chart's footer.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1. The
  strips themselves come from frames (`StatusLive.TrafficFrame`) pushed
  by `StripChart.Feed`; this widget renders the shell and the feed list.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.StripChart, only: [strip_chart: 1]

  alias MediaCentaur.HttpClient.Upstream
  alias MediaCentaur.TimeSeries.Window
  alias MediaCentaurWeb.StatusLive.TrafficFrame

  @doc "Connections Activity widget: request strip charts + recent-request feed."
  attr :traffic_window, :atom, required: true, values: Window.all()
  attr :traffic_recent, :list, default: [], doc: "Traffic.recent/0 — newest first"

  def http_widget(assigns) do
    # The bundle is a plain map (no change tracking) — derive with Map.put/3.
    assigns = Map.put(assigns, :legend, TrafficFrame.legend())

    ~H"""
    <div data-testid="http-widget">
      <.strip_chart
        id="traffic"
        title="Requests"
        lede="Requests are what went out; cache is what was answered here instead. Hover a bar to read that bucket."
        window={@traffic_window}
        legend={@legend}
      >
        <:footer>
          <details :if={@traffic_recent != []} class="strip-chart-recent" data-component="http-recent">
            <summary class="cursor-pointer text-xs text-base-content/55">Recent requests</summary>
            <ul class="mt-2 space-y-0.5 font-mono text-xs">
              <li
                :for={entry <- @traffic_recent}
                id={recent_row_id(entry)}
                class="flex items-baseline gap-2"
              >
                <span class="text-base-content/55 shrink-0">
                  {Calendar.strftime(entry.at, "%H:%M:%S")}
                </span>
                <span class="text-base-content/60 shrink-0">{Upstream.label(entry.upstream)}</span>
                <span class="truncate text-base-content/80">
                  {entry.method |> to_string() |> String.upcase()} {entry.path}
                </span>
                <span class={["ml-auto shrink-0", outcome_class(entry)]}>{outcome_label(entry)}</span>
                <span class="text-base-content/55 shrink-0 tabular-nums">{entry.duration_ms}ms</span>
                <span class="text-base-content/55 shrink-0">{cache_label(entry.cache)}</span>
              </li>
            </ul>
          </details>
        </:footer>
      </.strip_chart>
    </div>
    """
  end

  defp outcome_label(%{error: error}) when is_binary(error), do: error
  defp outcome_label(%{status: status}), do: to_string(status)

  defp outcome_class(%{error: error}) when is_binary(error), do: "text-error"
  defp outcome_class(%{status: status}) when status >= 400, do: "text-error"
  defp outcome_class(_entry), do: "text-base-content/60"

  defp cache_label(:uncached), do: ""
  defp cache_label(outcome), do: to_string(outcome)

  # Stable iterator id (UIDR-012). Requests are milliseconds apart at most,
  # so the second stamp plus path hash is collision-proof in practice.
  defp recent_row_id(%{at: %DateTime{} = at, path: path}) do
    "http-recent-#{DateTime.to_unix(at, :microsecond)}-#{:erlang.phash2(path)}"
  end
end
