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

  @spec board_subsystems() :: [atom()]
  def board_subsystems, do: @board_subsystems

  @spec label(atom()) :: String.t()
  def label(component), do: Map.fetch!(@labels, normalize(component))

  @spec glyph(atom()) :: String.t()
  def glyph(component), do: Map.fetch!(@glyphs, normalize(component))

  # Framework + unknown components fold under :system on the board.
  defp normalize(component) when component in @board_subsystems, do: component
  defp normalize(_), do: :system
end
