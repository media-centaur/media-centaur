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
