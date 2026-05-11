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
  defp target_summary(%{tmdb_type: "movie", year: y}), do: "Movie • #{y}"
  defp target_summary(%{tmdb_type: "tv", season_number: nil}), do: "TV"

  defp target_summary(%{tmdb_type: "tv", season_number: s, episode_number: nil}), do: "TV • S#{pad(s)}"

  defp target_summary(%{tmdb_type: "tv", season_number: s, episode_number: e}),
    do: "TV • S#{pad(s)}E#{pad(e)}"

  defp target_summary(%{tmdb_type: type}), do: type
  defp target_summary(_), do: nil

  defp pad(n) when is_integer(n) and n < 10, do: "0#{n}"
  defp pad(n) when is_integer(n), do: "#{n}"
end
