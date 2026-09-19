defmodule MediaCentaur.HttpClient.IncidentContext do
  @moduledoc """
  The `:http` subsystem's contribution to diagnostics, an
  `ErrorReports.IncidentContext`.

  `assess/0` raises one fault for the upstreams no other subsystem
  assesses: TMDB and its image CDN. Prowlarr and the download clients
  are graded by `MediaCentaur.Acquisition.IncidentContext` from their own
  polls, and GitHub by `MediaCentaur.SelfUpdate.IncidentContext` from its
  check history. Grading those here again would mint two incidents for
  one outage. Steam is not graded either: it has no panel row and a
  failed banner lookup falls back to local art.

  ## Two kinds of evidence, one per upstream

  **TMDB is graded by availability** (`MediaCentaur.IntegrationAvailability`),
  not by how much of its traffic failed. Since the recurring-traffic
  audit, work that needs TMDB is *held* while it is down — the refresh
  cycle, the artwork warm — so an outage produces almost no traffic to
  measure: the probe's one request every five minutes, three per
  fifteen-minute window, under any share floor. Request share would have
  read that silence as health. The value a probe keeps current is the
  evidence instead, and the grace window is longer than one probe
  cadence so a fault means a probe confirmed the outage rather than one
  request having timed out.

  **The image CDN is graded by request share**, because it writes no
  availability value of its own: `image.tmdb.org` is a different host
  from `api.themoviedb.org`, a failed download is no evidence about the
  API, and nothing probes the CDN. Failing traffic is all there is. The
  share is read from `MediaCentaur.HttpClient.Traffic.totals/2` over the
  last fifteen minutes.

  `vitals/0` attaches the per-upstream fifteen-minute figures and the
  cache size to every incident report, whichever subsystem raised it.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.HttpClient.{Cache, Traffic, Upstream}
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @assessed_by_share [:tmdb_images]
  @min_requests 10
  @failing_share 0.5
  @window_seconds 900

  # Longer than `TMDB.ProbeJob`'s five-minute cadence, so a fault means a
  # probe has confirmed the outage at least once — not that one request
  # timed out six minutes ago and nothing has asked since.
  @unavailable_grace_seconds 360

  @type fault :: {:fault, :upstream_failing | :upstream_unavailable, :warning, map()}

  @impl true
  def assess do
    assess(share_totals(), IntegrationAvailability.status(:tmdb), DateTime.utc_now())
  end

  @doc """
  Pure assessment: a TMDB outage past the grace window, else the worst
  share-failing upstream, else `:ok`. A down TMDB outranks a failing CDN
  — it is the one with a remedy the person can act on. `totals_by_upstream`
  maps an upstream id to its `Traffic.totals/0` over the window.
  """
  @spec assess(%{atom() => Traffic.totals()}, Status.t(), DateTime.t()) :: :ok | fault()
  def assess(totals_by_upstream, %Status{} = tmdb_status, %DateTime{} = now)
      when is_map(totals_by_upstream) do
    unavailable(tmdb_status, now) || failing_share(totals_by_upstream)
  end

  defp share_totals do
    Map.new(@assessed_by_share, &{&1, Traffic.totals(&1, seconds: @window_seconds)})
  end

  defp unavailable(%Status{state: {:down, since, reason}}, now) do
    if DateTime.diff(now, since, :second) >= @unavailable_grace_seconds do
      {:fault, :upstream_unavailable, :warning,
       %{upstream: :tmdb, headline: unavailable_headline(reason)}}
    end
  end

  defp unavailable(%Status{state: :up}, _now), do: nil

  defp unavailable_headline(:rejected), do: "#{Upstream.label(:tmdb)} rejected the API key"
  defp unavailable_headline(:rate_limited), do: "#{Upstream.label(:tmdb)} is rate-limiting requests"
  defp unavailable_headline(_unreachable), do: "#{Upstream.label(:tmdb)} is unreachable"

  defp failing_share(totals_by_upstream) do
    @assessed_by_share
    |> Enum.map(&{&1, Map.get(totals_by_upstream, &1, %{requests: 0, failed: 0})})
    |> Enum.filter(fn {_id, totals} -> totals.requests >= @min_requests end)
    |> Enum.map(fn {id, totals} -> {id, totals.failed / totals.requests} end)
    |> Enum.filter(fn {_id, share} -> share >= @failing_share end)
    |> Enum.max_by(fn {_id, share} -> share end, fn -> nil end)
    |> case do
      nil ->
        :ok

      {id, _share} ->
        {:fault, :upstream_failing, :warning,
         %{upstream: id, headline: "Most requests to #{Upstream.label(id)} are failing"}}
    end
  end

  @impl true
  def vitals do
    %{
      "upstreams" =>
        Map.new(Upstream.ids(), fn id ->
          totals = Traffic.totals(id, seconds: @window_seconds)

          {to_string(id),
           %{
             "window_requests" => totals.requests,
             "window_failed" => totals.failed,
             "window_cached" => totals.cached,
             "mean_latency_ms" => totals.mean_ms,
             "worst_latency_ms" => totals.worst_ms
           }}
        end),
      "cache_entries" => Cache.stats().entries
    }
  end
end
