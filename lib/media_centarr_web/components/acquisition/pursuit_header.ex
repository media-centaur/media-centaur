defmodule MediaCentarrWeb.Components.Acquisition.PursuitHeader do
  @moduledoc "Identity card for `/download/:pursuit_id` — title, state, target, criteria."

  use Phoenix.Component

  alias MediaCentarr.Acquisition.ViewModels.PursuitHeader
  alias MediaCentarrWeb.Components.Acquisition.PursuitStyle

  attr :vm, PursuitHeader, required: true

  def pursuit_header(assigns) do
    ~H"""
    <header class="glass-surface rounded-xl p-5 space-y-2">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-lg font-medium truncate">{@vm.title}</h2>
        <PursuitStyle.state_badge state={@vm.state} />
      </div>

      <div :if={target_summary(@vm.target)} class="text-xs text-base-content/70">
        {target_summary(@vm.target)}
      </div>

      <div :if={@vm.criteria_summary} class="text-xs text-base-content/60">
        Criteria: {@vm.criteria_summary}
      </div>
    </header>
    """
  end

  defp target_summary(%{tmdb_type: "movie", year: nil}), do: "Movie"
  defp target_summary(%{tmdb_type: "movie", year: year}), do: "Movie • #{year}"
  defp target_summary(%{tmdb_type: "tv", season_number: nil}), do: "TV"

  defp target_summary(%{tmdb_type: "tv", season_number: season, episode_number: nil}),
    do: "TV • S#{pad(season)}"

  defp target_summary(%{tmdb_type: "tv", season_number: season, episode_number: episode}),
    do: "TV • S#{pad(season)}E#{pad(episode)}"

  defp target_summary(%{tmdb_type: type}), do: type
  defp target_summary(_), do: nil

  defp pad(num) when is_integer(num) and num < 10, do: "0#{num}"
  defp pad(num) when is_integer(num), do: "#{num}"
end
