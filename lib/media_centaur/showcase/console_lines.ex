defmodule MediaCentaur.Showcase.ConsoleLines do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Fills the demo instance's console rings at boot, so `/console` and each
  Status drill-in's log panel have something to show.

  `MediaCentaur.Console.Buffer` is, in its own words, "the runtime state
  of the console": one capped ring per component, in memory. Only the cap
  and the filter are persisted. The seeder used to emit these lines
  during `mix seed.showcase`, which wrote them into the *seed task's*
  ring and lost them when that VM exited — the demo booted with an empty
  console. They belong here, beside the other per-boot fabrication.

  Emitted through `MediaCentaur.Log` like any other line, so they carry
  real components and levels and are filtered exactly as real lines are.

  Every string is public-domain or Creative Commons, per the content
  policy in `MediaCentaur.Showcase`.
  """

  use Task, restart: :transient

  require MediaCentaur.Log

  alias MediaCentaur.Log

  def start_link(_opts \\ []), do: Task.start_link(__MODULE__, :run, [])

  @doc "Emits the fixture lines. Called once by the showcase supervisor."
  @spec run() :: :ok
  def run do
    Log.info(:watcher, "scanned 14 files in /showcase/media")
    Log.info(:pipeline, "processed 3 movies, 1 TV series, 2 extras in last batch")
    Log.info(:tmdb, "search hit: Nosferatu (1922) → TMDB 653")
    Log.info(:library, "linked watched file: Big Buck Bunny (2008).mkv")
    Log.info(:playback, "session stopped: position 1820s of 5400s")

    Log.warning(:tmdb, "rate limit window: 3 requests queued, backing off 250ms")

    Log.warning(
      :watcher,
      "file appeared then disappeared within debounce window: /showcase/tmp/.partial.mkv"
    )

    Log.warning(
      :pipeline,
      "no confident TMDB match for 'Ambiguous-RELEASE-GROUP.mkv' — escalated to review queue"
    )

    Log.error(:library, "image download failed for backdrop (404) — falling back to poster crop")

    :ok
  end
end
