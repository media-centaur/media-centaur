defmodule MediaCentaurWeb.StatusLive.HealthBoard do
  @moduledoc """
  Pure view-model helpers for the Subsystem Health Board. Turns the
  `ErrorReports` store rollups into renderable per-subsystem view-models.
  No DB, no rendering — unit-tested in isolation (ADR-030).
  """

  @board_subsystems [:watcher, :pipeline, :tmdb, :playback, :library, :acquisition, :system]

  @labels %{
    watcher: "Watcher",
    pipeline: "Import",
    tmdb: "Metadata",
    playback: "Playback",
    library: "Library",
    acquisition: "Downloads",
    system: "System"
  }

  @glyphs %{
    watcher: "hero-eye",
    pipeline: "hero-arrow-down-on-square-stack",
    tmdb: "hero-film",
    playback: "hero-play-circle",
    library: "hero-rectangle-stack",
    acquisition: "hero-arrow-down-tray",
    system: "hero-cpu-chip"
  }

  alias MediaCentaur.ErrorReports.Bucket

  @spec board_subsystems() :: [atom()]
  def board_subsystems, do: @board_subsystems

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

  # Framework + unknown components fold under :system on the board.
  defp normalize(component) when component in @board_subsystems, do: component
  defp normalize(_), do: :system
end
