defmodule MediaCentarrWeb.Components.Acquisition.PursuitHeader do
  @moduledoc "Identity card for `/download/:pursuit_id` — title, state, recipe, criteria."

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

      <div :if={recipe_summary(@vm.recipe)} class="text-xs text-base-content/70">
        {recipe_summary(@vm.recipe)}
      </div>

      <div :if={@vm.criteria_summary} class="text-xs text-base-content/60">
        Criteria: {@vm.criteria_summary}
      </div>
    </header>
    """
  end

  defp recipe_summary(%{recipe_type: :prowlarr_query, manual_query: q}) when is_binary(q),
    do: "Query • #{q}"

  defp recipe_summary(%{recipe_type: :prowlarr_query}), do: "Query"
  defp recipe_summary(%{tmdb_type: "movie", year: nil}), do: "Movie"
  defp recipe_summary(%{tmdb_type: "movie", year: year}), do: "Movie • #{year}"
  defp recipe_summary(%{tmdb_type: "tv", season_number: nil}), do: "TV"

  defp recipe_summary(%{tmdb_type: "tv", season_number: season, episode_number: nil}),
    do: "TV • S#{pad(season)}"

  defp recipe_summary(%{tmdb_type: "tv", season_number: season, episode_number: episode}),
    do: "TV • S#{pad(season)}E#{pad(episode)}"

  defp recipe_summary(%{tmdb_type: type}) when is_binary(type), do: type
  defp recipe_summary(_), do: nil

  defp pad(num) when is_integer(num) and num < 10, do: "0#{num}"
  defp pad(num) when is_integer(num), do: "#{num}"
end
