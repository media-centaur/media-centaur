defmodule MediaCentarrWeb.Components.Detail.ScoreCard do
  @moduledoc """
  TMDB Reception score card — rating value (0–10) shown as a tinted
  square plus an optional vote-count subtext. Visibility is decided
  upstream via `Detail.Logic.score_visible?/1`; this component renders
  unconditionally when given a rating.
  """
  use MediaCentarrWeb, :html

  attr :rating, :float, required: true
  attr :vote_count, :integer, default: nil
  attr :source, :string, default: "TMDB"

  def score_card(assigns) do
    ~H"""
    <div class="flex items-center gap-3 bg-base-content/[0.04] border border-base-content/[0.06] rounded-lg p-3 max-w-fit">
      <div class="size-11 rounded-lg bg-success/15 text-success font-bold flex items-center justify-center">
        {Float.round(@rating, 1)}
      </div>
      <div class="flex flex-col">
        <span class="text-sm font-medium text-base-content/85">{@source} rating</span>
        <span :if={is_integer(@vote_count) && @vote_count > 0} class="text-xs text-base-content/50">
          {format_votes(@vote_count)} votes
        </span>
      </div>
    </div>
    """
  end

  defp format_votes(count) when count >= 1000 do
    "#{Float.round(count / 1000, 1)}k"
  end

  defp format_votes(count), do: Integer.to_string(count)
end
