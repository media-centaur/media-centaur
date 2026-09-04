defmodule MediaCentaur.HttpClient.IncidentContext do
  @moduledoc """
  The `:http` subsystem's contribution to diagnostics, an
  `ErrorReports.IncidentContext`.

  `assess/0` raises one fault when most recent requests to an upstream
  are failing. It covers only the upstreams no other subsystem
  assesses: Prowlarr and the download clients are graded by
  `MediaCentaur.Acquisition.IncidentContext` from their own polls, and
  GitHub by `MediaCentaur.SelfUpdate.IncidentContext` from its check
  history. Grading those here again would mint two incidents for one
  outage. Steam is not graded either: it has no panel row and a failed
  banner lookup falls back to local art.

  `vitals/0` attaches the per-upstream figures and the cache size to
  every incident report, whichever subsystem raised it.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.HttpClient.{Cache, Stats}

  @assessed [:tmdb, :tmdb_images]
  @min_requests 10
  @failing_share 0.5

  @impl true
  def assess, do: assess(Stats.snapshot())

  @doc "Pure assessment of a stats snapshot: the worst failing upstream, or `:ok`."
  @spec assess(map()) :: :ok | {:fault, :upstream_failing, :warning, map()}
  def assess(%{upstreams: rows}) do
    rows
    |> Enum.filter(&(&1.id in @assessed and &1.window.requests >= @min_requests))
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
