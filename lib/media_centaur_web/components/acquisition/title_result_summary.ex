defmodule MediaCentaurWeb.Components.Acquisition.TitleResultSummary do
  @moduledoc """
  The identity summary of one TMDB title-search hit — poster thumbnail
  (icon fallback), name, type chip, year. The shared rendering unit of
  every title-result row: the omnibox dropdown and the Track modal wrap
  it in their own row chrome (whole-row pick button vs. Track action),
  which is where their behavior differs.

  Renders sibling `<span>`s (no root element) so it can live inside a
  `<button>` row — the caller owns the flex container.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.ReleaseTracking.TitleResult

  @doc """
  Identity summary for a `TitleResult` row: poster (or type-icon
  fallback), truncating name, Movie/TV chip, year when known.
  """
  attr :result, TitleResult, required: true

  def title_result_summary(assigns) do
    ~H"""
    <span class="flex-shrink-0 w-9 h-[54px] rounded bg-base-content/10 overflow-hidden flex items-center justify-center">
      <img
        :if={@result.poster_path}
        src={"https://image.tmdb.org/t/p/w92#{@result.poster_path}"}
        alt=""
        class="w-full h-full object-cover"
        loading="eager"
        decoding="sync"
      />
      <.icon
        :if={!@result.poster_path}
        name={if @result.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
        class="size-4 text-base-content/25"
      />
    </span>
    <span class="flex-1 min-w-0">
      <span class="block truncate text-sm font-medium">{@result.name}</span>
      <%!-- Quiet text, not colored chips — twenty amber MOVIE chips in a
            result list is noise; type is metadata, color stays reserved
            for interaction and state. --%>
      <span class="flex items-center gap-1.5 text-xs text-base-content/50">
        <span>{if @result.media_type == :movie, do: "Movie", else: "TV"}</span>
        <span :if={@result.year}>· {@result.year}</span>
      </span>
    </span>
    """
  end
end
