defmodule MediaCentaurWeb.StatusLive.TrafficFrame do
  @moduledoc """
  Turns `MediaCentaur.HttpClient.Traffic` series into the strip chart
  frame the Connections drill-in pushes (contract in
  `MediaCentaurWeb.Components.StripChart.Feed`). Pure: every read has an
  injectable option so tests pass functions and fixed times.

  Strip membership: TMDB, TMDB images and GitHub always; Prowlarr and the
  two download clients when configured. Order is `Upstream.panel_ids/0`.
  The dot is the outcome of the upstream's last request. "Down since"
  from `IntegrationAvailability` replaces the last-success line while an
  integration is down. The TMDB strip adds the rate-limiter budget.
  """

  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]

  alias MediaCentaur.{Capabilities, IntegrationAvailability}
  alias MediaCentaur.HttpClient.{Traffic, Upstream}
  alias MediaCentaur.TimeSeries.Window

  @schema %{
    bars: [
      %{key: "failed", label: "failed", tone: "error"},
      %{key: "went_out", label: "went out", tone: "solid"},
      %{key: "cached", label: "from cache", tone: "muted"}
    ],
    bars_total_label: "requests",
    line: %{key: "mean_ms", worst_key: "worst_ms", label: "mean latency", unit: "ms"}
  }

  @legend Enum.map(@schema.bars, &%{label: &1.label, tone: &1.tone}) ++
            [%{label: @schema.line.label, tone: "line"}]

  @doc "The legend items the Connections widget renders."
  @spec legend() :: [map()]
  def legend, do: @legend

  @spec build(Window.t(), keyword()) :: map()
  def build(window, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    configured = Keyword.get_lazy(opts, :configured, &Capabilities.upstream_flags/0)
    series = Keyword.get(opts, :series, &Traffic.series/2)
    last = Keyword.get(opts, :last, &Traffic.last/1)
    last_success_at = Keyword.get(opts, :last_success_at, &Traffic.last_success_at/1)
    down_since = Keyword.get(opts, :down_since, &IntegrationAvailability.down_since/1)
    rate_limiter = Keyword.get_lazy(opts, :rate_limiter, &fetch_rate_limiter/0)

    strips =
      for upstream <- Upstream.active_ids(configured) do
        upstream_series = series.(upstream, window)

        %{
          id: Atom.to_string(upstream),
          label: Upstream.label(upstream),
          dot: dot(last.(upstream)),
          figures:
            figures(
              upstream,
              upstream_series.totals,
              last_success_at.(upstream),
              down_since_for(upstream, down_since),
              rate_limiter,
              now
            ),
          t: upstream_series.starts,
          failed: upstream_series.failed,
          went_out: upstream_series.went_out,
          cached: upstream_series.cached,
          mean_ms: upstream_series.mean_ms,
          worst_ms: upstream_series.worst_ms
        }
      end

    %{
      id: "traffic",
      window: Atom.to_string(window),
      bucket_seconds: Window.bar_seconds(window),
      schema: @schema,
      strips: strips
    }
  end

  # Only integrations with an availability value can be down here; the
  # image CDN, GitHub and the download clients have none.
  @with_availability [:tmdb, :prowlarr]

  defp down_since_for(upstream, down_since) when upstream in @with_availability,
    do: down_since.(upstream)

  defp down_since_for(_upstream, _down_since), do: nil

  defp dot(nil), do: "none"
  defp dot(%{outcome: :ok}), do: "ok"
  defp dot(%{outcome: :failed}), do: "failed"

  defp figures(upstream, totals, last_success, down_since, rate_limiter, now) do
    lines =
      if totals.requests == 0 and totals.cached == 0 do
        [[%{text: "No requests in this window"}]]
      else
        [
          [%{text: "#{fmt(totals.requests)} requests"}, failed(totals.failed)],
          second_line(totals)
        ]
      end

    lines ++ [[last_line(last_success, down_since, now)]] ++ slots(upstream, rate_limiter)
  end

  defp failed(0), do: %{text: "0 failed"}
  defp failed(count), do: %{text: "#{fmt(count)} failed", tone: "error"}

  defp second_line(totals) do
    cached = if totals.cached > 0, do: [%{text: "#{fmt(totals.cached)} cached"}], else: []
    mean = if totals.mean_ms, do: [%{text: "#{duration(totals.mean_ms)} mean"}], else: []

    case cached ++ mean do
      [] -> [%{text: "—"}]
      segments -> segments
    end
  end

  defp last_line(_last_success, %DateTime{} = since, _now),
    do: %{text: "Down since #{Calendar.strftime(since, "%H:%M")}", tone: "warning"}

  defp last_line(nil, nil, _now), do: %{text: "—"}
  defp last_line(%DateTime{} = at, nil, _now), do: %{text: "ok #{time_ago(at)}"}

  defp slots(:tmdb, %{available: available, total: total}),
    do: [[%{text: "#{available} of #{total} slots free"}]]

  defp slots(_upstream, _status), do: []

  defp fmt(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  # Integer tenths, rounded half up, so 1650 reads "1.7 s" and 3000 "3 s".
  defp duration(ms) when ms >= 1_000 do
    tenths = div(ms + 50, 100)

    case rem(tenths, 10) do
      0 -> "#{div(tenths, 10)} s"
      fraction -> "#{div(tenths, 10)}.#{fraction} s"
    end
  end

  defp duration(ms), do: "#{ms} ms"

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
