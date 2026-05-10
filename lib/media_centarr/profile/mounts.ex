defmodule MediaCentarr.Profile.Mounts do
  @moduledoc """
  Per-route LiveView mount timing harness (ADR-041).

  Uses `Phoenix.LiveViewTest.live/2` to mount each top-level
  LiveView in-process — no real HTTP, no socket roundtrip, no
  asset pipeline noise. The signal is the actual mount + first
  render path, which is where ETS-vs-DB differences manifest.
  Same pattern as `test/media_centarr_web/page_smoke_test.exs`.

  Each route runs `@warmup` un-timed mounts (BEAM JIT, query plan
  cache, schema cache), then `@runs` timed mounts. Reports
  min / p50 / p95 / max in microseconds.

  ## Output shape

      [
        %{
          route: "/",
          warm_cache?: true,
          runs: 30,
          min_us: 4_120,
          p50_us: 4_580,
          p95_us: 6_310,
          max_us: 8_990
        },
        ...
      ]

  `Profile.Reporter` formats this into the `## Page Mount Timing`
  section.
  """

  # Phoenix.LiveViewTest.live/2 expands to a Phoenix.ConnTest.get/2
  # call internally, so both imports are required at the call site.
  import Phoenix.ConnTest, only: [build_conn: 0, get: 2]
  import Phoenix.LiveViewTest, only: [live: 2]

  @endpoint MediaCentarrWeb.Endpoint

  @warmup 5
  @runs 30

  # Routes that mount a LiveView. Kept explicit (not derived from
  # the router) so we always know what we're measuring; new routes
  # require a deliberate addition here.
  @routes [
    {"/", warm_cache?: true},
    {"/library", warm_cache?: false},
    {"/upcoming", warm_cache?: false},
    {"/history", warm_cache?: false},
    {"/review", warm_cache?: false},
    {"/download", warm_cache?: false},
    {"/status", warm_cache?: false},
    {"/settings", warm_cache?: false},
    {"/console", warm_cache?: false}
  ]

  @doc "Times every route in `@routes`. Returns one result per route."
  @spec run_all() :: [map()]
  def run_all, do: Enum.map(@routes, fn {path, meta} -> time_route(path, meta) end)

  @doc "Times a single route. `meta` carries human-readable annotations for the report."
  @spec time_route(String.t(), keyword()) :: map()
  def time_route(path, meta \\ []) do
    Enum.each(1..@warmup, fn _ -> mount_once(path) end)

    timings = Enum.map(1..@runs, fn _ -> mount_once(path) end)
    sorted = Enum.sort(timings)
    n = length(sorted)

    %{
      route: path,
      warm_cache?: Keyword.get(meta, :warm_cache?, false),
      runs: n,
      min_us: Enum.at(sorted, 0),
      p50_us: Enum.at(sorted, div(n, 2)),
      p95_us: Enum.at(sorted, min(n - 1, div(n * 95, 100))),
      max_us: Enum.at(sorted, -1)
    }
  end

  # Mounts the LiveView at `path`, returning microseconds taken.
  # Errors are folded into a sentinel timing so a single broken
  # route doesn't kill the whole sweep — they show up in the report
  # as outliers (max_us == :error_marker), worth investigating but
  # not run-stopping.
  defp mount_once(path) do
    conn = build_conn()

    {us, _result} =
      :timer.tc(fn ->
        try do
          live(conn, path)
        rescue
          _ -> :error
        catch
          _, _ -> :error
        end
      end)

    us
  end
end
