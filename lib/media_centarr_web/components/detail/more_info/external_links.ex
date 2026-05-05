defmodule MediaCentarrWeb.Components.Detail.MoreInfo.ExternalLinks do
  @moduledoc """
  Shared external-links footer for the More info panel — TMDB and IMDb
  out-links rendered as a compact row at the bottom of the panel for
  movies and series alike. Each link is hidden when its source URL/id is
  absent, so a movie or series with no IMDb id collapses to TMDB only.
  """

  use MediaCentarrWeb, :html

  attr :tmdb_url, :string, default: nil, doc: "TMDB web URL for the entity (movie or TV series)."
  attr :imdb_id, :string, default: nil, doc: "IMDb title id (e.g. tt0000001) — link is hidden when nil."

  def external_links(assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-sm border-t border-base-content/10 pt-4">
      <a
        :if={@tmdb_url}
        href={@tmdb_url}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-base-content/70 hover:text-primary transition-colors"
      >
        TMDB <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
      </a>
      <a
        :if={@imdb_id}
        href={"https://www.imdb.com/title/#{@imdb_id}/"}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-base-content/70 hover:text-primary transition-colors"
      >
        IMDb <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
      </a>
    </div>
    """
  end
end
