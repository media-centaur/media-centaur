defmodule MediaCentaurWeb.Components.StatusWidgets.Http do
  @moduledoc """
  Connections (`:http`) Activity widget: one row per upstream with the
  last fifteen minutes of requests, errors, latency, and cache hits,
  plus a collapsed feed of the most recent requests.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]

  alias MediaCentaur.HttpClient.{Stats, Upstream}

  @doc "Connections Activity widget: per-upstream request figures + recent-request feed."
  attr :http_stats, :map,
    required: true,
    doc: "HttpClient.Stats.snapshot/0 — %{window_minutes, upstreams, recent}"

  attr :rate_limiter, :map,
    default: nil,
    doc:
      "TMDB.RateLimiter.status/0 result (%{used, total}) shown on the TMDB row, or nil when not started"

  def http_widget(assigns) do
    ~H"""
    <div class="card glass-inset" data-testid="http-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">Outbound requests</h2>
        <p class="text-xs text-base-content/50">
          Last {@http_stats.window_minutes} minutes, with session totals in grey. Cache is the share of requests answered without going out.
        </p>

        <div class="overflow-x-auto" data-component="http-upstreams">
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/50">
                <th>Upstream</th>
                <th class="text-right">Requests</th>
                <th class="text-right">Errors</th>
                <th class="text-right">Latency</th>
                <th class="text-right">Cache</th>
                <th class="text-right">Last success</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- panel_rows(@http_stats.upstreams)} id={"http-upstream-#{row.id}"}>
                <td>
                  <span class="text-base-content/80">{row.label}</span>
                  <span
                    :if={row.id == :tmdb and @rate_limiter}
                    class="ml-2 font-mono text-xs text-base-content/40"
                    data-component="tmdb-rate-budget"
                  >
                    {@rate_limiter.used}/{@rate_limiter.total} slots
                  </span>
                </td>
                <td class="text-right tabular-nums">
                  {row.window.requests}
                  <span class="text-base-content/40">· {row.session.requests}</span>
                </td>
                <td class={["text-right tabular-nums", row.window.errors > 0 && "text-error"]}>
                  {row.window.errors}
                  <span class="text-base-content/40">· {row.session.errors}</span>
                </td>
                <td class="text-right tabular-nums">{latency_label(row.window.median_latency_ms)}</td>
                <td class="text-right tabular-nums">{hit_ratio_label(row.window.cache)}</td>
                <td class="text-right text-base-content/60">{last_label(row.last_success_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <details :if={@http_stats.recent != []} class="mt-3" data-component="http-recent">
          <summary class="cursor-pointer text-xs uppercase tracking-wide text-base-content/50">
            Recent requests
          </summary>
          <ul class="mt-2 space-y-0.5 font-mono text-xs">
            <li
              :for={entry <- @http_stats.recent}
              id={recent_row_id(entry)}
              class="flex items-baseline gap-2"
            >
              <span class="text-base-content/40 shrink-0">{Calendar.strftime(entry.at, "%H:%M:%S")}</span>
              <span class="text-base-content/60 shrink-0">{upstream_label(entry.upstream)}</span>
              <span class="truncate text-base-content/80">
                {entry.method |> to_string() |> String.upcase()} {entry.path}
              </span>
              <span class={["ml-auto shrink-0", outcome_class(entry)]}>{outcome_label(entry)}</span>
              <span class="text-base-content/40 shrink-0 tabular-nums">{entry.duration_ms}ms</span>
              <span class="text-base-content/40 shrink-0">{cache_label(entry.cache)}</span>
            </li>
          </ul>
        </details>
      </div>
    </div>
    """
  end

  defp panel_rows(rows), do: Enum.filter(rows, &(&1.id in Upstream.panel_ids()))

  defp latency_label(nil), do: "—"
  defp latency_label(ms), do: "#{ms} ms"

  defp hit_ratio_label(cache) do
    case Stats.hit_ratio(cache) do
      nil -> "—"
      ratio -> "#{round(ratio * 100)}%"
    end
  end

  defp last_label(nil), do: "—"
  defp last_label(%DateTime{} = at), do: time_ago(at)

  defp upstream_label(id), do: Upstream.label(id)

  defp outcome_label(%{error: error}) when is_binary(error), do: error
  defp outcome_label(%{status: status}), do: to_string(status)

  defp outcome_class(%{error: error}) when is_binary(error), do: "text-error"
  defp outcome_class(%{status: status}) when status >= 400, do: "text-error"
  defp outcome_class(_entry), do: "text-base-content/60"

  defp cache_label(:uncached), do: ""
  defp cache_label(outcome), do: to_string(outcome)

  # Stable iterator id (UIDR-012). Requests are milliseconds apart at most,
  # so the microsecond stamp plus path is collision-proof in practice.
  defp recent_row_id(%{at: %DateTime{} = at, path: path}) do
    "http-recent-#{DateTime.to_unix(at, :microsecond)}-#{:erlang.phash2(path)}"
  end
end
