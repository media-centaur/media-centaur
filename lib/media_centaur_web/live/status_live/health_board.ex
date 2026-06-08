defmodule MediaCentaurWeb.StatusLive.HealthBoard do
  @moduledoc """
  Pure view-model helpers for the Subsystem Health Board. Turns the
  `ErrorReports` store rollups into renderable per-subsystem view-models.
  No DB, no rendering — unit-tested in isolation (ADR-030).
  """

  @board_subsystems [
    :watcher,
    :pipeline,
    :tmdb,
    :playback,
    :library,
    :acquisition,
    :self_update,
    :system
  ]

  @labels %{
    watcher: "Watcher",
    pipeline: "Import",
    tmdb: "Metadata",
    playback: "Playback",
    library: "Library",
    acquisition: "Downloads",
    self_update: "Updates",
    system: "System"
  }

  @glyphs %{
    watcher: "hero-eye",
    pipeline: "hero-arrow-down-on-square-stack",
    tmdb: "hero-film",
    playback: "hero-play-circle",
    library: "hero-rectangle-stack",
    acquisition: "hero-arrow-down-tray",
    self_update: "hero-arrow-down-circle",
    system: "hero-cpu-chip"
  }

  # Plain-language briefing for each subsystem: what it is responsible for and
  # what the experience degrades to when it isn't working. Shown at the top of
  # the drill-in so the board reads as an explanation, not just a status light.
  @descriptions %{
    watcher:
      "Watches your media folders for files that appear, move, or vanish and hands new arrivals to Import. " <>
        "If it stalls, newly added media won't show up in your library until the next manual scan.",
    pipeline:
      "Turns raw files into library entries — parsing filenames, matching them to the right movie or episode, and fetching artwork. " <>
        "If it falls behind, files land on disk but never become browsable, fully identified entries with posters.",
    tmdb:
      "Fetches titles, descriptions, cast, and images from The Movie Database, staying within its rate limits. " <>
        "If it's degraded, entries appear with missing or stale details and blank artwork.",
    playback:
      "Tracks what's playing and records your watch progress. " <>
        "If it's off, resume points and Continue Watching stop updating and in-app playback control gets unreliable.",
    library:
      "The catalog of everything you own — entities, files, watch state, and storage. " <>
        "If it's unhealthy, library counts and browse results can be wrong or incomplete.",
    acquisition:
      "Drives acquisitions through your download client and Prowlarr — sending grabs, tracking progress, and linking finished downloads back into the library. " <>
        "If it breaks, requested media never downloads or never gets linked once it lands.",
    self_update:
      "Checks for new Media Centaur releases and applies in-app updates. " <>
        "If it fails, you stay on an old version or an update stalls partway through.",
    system:
      "Overall application-runtime health and anything not owned by a specific subsystem. " <>
        "If it's flagging problems, the app itself may be unstable — crashes, restarts, or framework-level errors."
  }

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.StatusLive.SubsystemView

  @spec board_subsystems() :: [atom()]
  def board_subsystems, do: @board_subsystems

  @doc "Builds the ordered list of subsystem tile view-models from all buckets."
  @spec build_board([Bucket.t()]) :: [SubsystemView.t()]
  def build_board(buckets) do
    grouped = group_buckets(buckets)

    Enum.map(@board_subsystems, fn component ->
      %{state: state, error_count: error_count, warning_count: warning_count} =
        tile_state(grouped[component])

      %SubsystemView{
        component: component,
        label: label(component),
        glyph: glyph(component),
        state: state,
        error_count: error_count,
        warning_count: warning_count
      }
    end)
  end

  @doc """
  Groups buckets by board subsystem. Framework/unknown components fold under
  `:system`. Every board subsystem is present with at least an empty list.
  """
  @spec group_buckets([Bucket.t()]) :: %{atom() => [Bucket.t()]}
  def group_buckets(buckets) do
    base = Map.new(@board_subsystems, &{&1, []})

    buckets
    |> Enum.group_by(fn %Bucket{component: c} -> normalize(c) end)
    |> then(&Map.merge(base, &1))
  end

  @type tile_state :: %{
          state: :ok | :warning | :error,
          error_count: non_neg_integer(),
          warning_count: non_neg_integer()
        }

  @doc "Derives a tile's health state from its buckets. critical+error => :error."
  @spec tile_state([Bucket.t()]) :: tile_state()
  def tile_state(buckets) do
    error_count = Enum.count(buckets, &(&1.severity in [:error, :critical]))
    warning_count = Enum.count(buckets, &(&1.severity == :warning))

    state =
      cond do
        error_count > 0 -> :error
        warning_count > 0 -> :warning
        true -> :ok
      end

    %{state: state, error_count: error_count, warning_count: warning_count}
  end

  @spec label(atom()) :: String.t()
  def label(component), do: Map.fetch!(@labels, normalize(component))

  @spec glyph(atom()) :: String.t()
  def glyph(component), do: Map.fetch!(@glyphs, normalize(component))

  @doc "Plain-language briefing: what the subsystem does and how it degrades if it fails."
  @spec description(atom()) :: String.t()
  def description(component), do: Map.fetch!(@descriptions, normalize(component))

  @doc "Plain-language one-line summary of a tile's state (e.g. `2 errors · 1 warning`)."
  @spec tile_summary(SubsystemView.t()) :: String.t()
  def tile_summary(%SubsystemView{state: :ok}), do: "No issues"

  def tile_summary(%SubsystemView{error_count: error_count, warning_count: warning_count}) do
    [count_phrase(error_count, "error"), count_phrase(warning_count, "warning")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc "Newest-first, formatted log lines drawn from a subsystem's buckets (capped at 20)."
  @spec log_lines([Bucket.t()]) :: [String.t()]
  def log_lines(buckets) do
    buckets
    |> Enum.flat_map(& &1.sample_entries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(20)
    |> Enum.map(fn %{timestamp: timestamp, message: message} ->
      "#{Calendar.strftime(timestamp, "%H:%M:%S")}  #{message}"
    end)
  end

  defp count_phrase(0, _word), do: nil
  defp count_phrase(1, word), do: "1 #{word}"
  defp count_phrase(n, word), do: "#{n} #{word}s"

  # Framework + unknown components fold under :system on the board.
  defp normalize(component) when component in @board_subsystems, do: component
  defp normalize(_), do: :system
end
