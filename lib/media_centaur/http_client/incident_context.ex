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
  API, and nothing probes the CDN. Failing traffic is all there is.

  `vitals/0` attaches the per-upstream figures and the cache size to
  every incident report, whichever subsystem raised it.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.HttpClient.{Cache, Stats, Upstream}
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @assessed_by_share [:tmdb_images]
  @min_requests 10
  @failing_share 0.5

  # Longer than `TMDB.ProbeJob`'s five-minute cadence, so a fault means a
  # probe has confirmed the outage at least once — not that one request
  # timed out six minutes ago and nothing has asked since.
  @unavailable_grace_seconds 360

  @type fault :: {:fault, :upstream_failing | :upstream_unavailable, :warning, map()}

  @impl true
  def assess do
    assess(Stats.snapshot(), IntegrationAvailability.status(:tmdb), DateTime.utc_now())
  end

  @doc """
  Pure assessment: a TMDB outage past the grace window, else the worst
  share-failing upstream, else `:ok`. A down TMDB outranks a failing CDN
  — it is the one with a remedy the person can act on.
  """
  @spec assess(map(), Status.t(), DateTime.t()) :: :ok | fault()
  def assess(%{upstreams: rows}, %Status{} = tmdb_status, %DateTime{} = now) do
    unavailable(tmdb_status, now) || failing_share(rows)
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

  defp failing_share(rows) do
    rows
    |> Enum.filter(&(&1.id in @assessed_by_share and &1.window.requests >= @min_requests))
    |> Enum.map(&{&1, &1.window.errors / &1.window.requests})
    |> Enum.filter(fn {_row, share} -> share >= @failing_share end)
    |> Enum.max_by(fn {_row, share} -> share end, fn -> nil end)
    |> case do
      nil ->
        :ok

      {row, _share} ->
        {:fault, :upstream_failing, :warning,
         %{upstream: row.id, headline: "Most requests to #{row.label} are failing"}}
    end
  end

  @impl true
  def vitals do
    snapshot = Stats.snapshot()

    %{
      "upstreams" =>
        Map.new(snapshot.upstreams, fn row ->
          {to_string(row.id),
           %{
             "window_requests" => row.window.requests,
             "window_errors" => row.window.errors,
             "median_latency_ms" => row.window.median_latency_ms,
             "session_requests" => row.session.requests,
             "session_errors" => row.session.errors
           }}
        end),
      "cache_entries" => Cache.stats().entries
    }
  end
end
