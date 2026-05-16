defmodule MediaCentarrWeb.Components.Detail.MoreInfoPanel do
  @moduledoc """
  *More info* sub-view of the detail modal — opened from the PlayCard's
  *More info* button. Acts as a thin shell that composes per-type
  credit rendering with shared cast and external-link sub-components.

  Composition (top-to-bottom):

    1. **Headline credits** — `MovieCredits.headline/1` for movies
       (Directed by / Written by), `SeriesCredits.headline/1` for
       TV series (Created by). Dispatched by `entity.type`.
    2. **Cast grid** — shared `CastGrid.cast_grid/1`. Identical
       layout for movies and series.
    3. **Meta block** — `MovieCredits.meta_block/1` (Studio /
       Country / Language / Runtime / Released) for movies,
       `SeriesCredits.meta_block/1` (Network / First aired / Status
       / Country / Language) for series.
    4. **External links** — shared `ExternalLinks.external_links/1`
       (TMDB + IMDb).

  Person names link to TMDB person pages when `tmdb_person_id` is
  present; otherwise rendered as plain text. Profile photos hotlink
  from `image.tmdb.org/t/p/w185{path}` — same convention the rest of
  the app uses for unimported TMDB artwork.
  """

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.Components.Detail.MoreInfo.{
    CastGrid,
    ExternalLinks,
    MovieCredits,
    SeriesCredits
  }

  attr :entity, :map,
    required: true,
    doc:
      "entity view-model map (see `MediaCentarr.Library.EntityShape.to_view_model/2`). Loose-typed because it spans multiple Library schemas; the shell reads `:type` to dispatch and forwards the whole map to per-type sub-components."

  def more_info_panel(assigns) do
    ~H"""
    <section class="space-y-6 pt-2 pb-4">
      <.headline_for_type entity={@entity} />
      <CastGrid.cast_grid cast={@entity[:cast] || []} />
      <.meta_for_type entity={@entity} />
      <ExternalLinks.external_links tmdb_url={@entity[:url]} imdb_id={@entity[:imdb_id]} />
    </section>
    """
  end

  defp headline_for_type(%{entity: %{type: :movie}} = assigns) do
    MovieCredits.headline(assigns)
  end

  defp headline_for_type(%{entity: %{type: :tv_series}} = assigns) do
    SeriesCredits.headline(assigns)
  end

  defp headline_for_type(assigns) do
    ~H""
  end

  defp meta_for_type(%{entity: %{type: :movie}} = assigns) do
    MovieCredits.meta_block(assigns)
  end

  defp meta_for_type(%{entity: %{type: :tv_series}} = assigns) do
    SeriesCredits.meta_block(assigns)
  end

  defp meta_for_type(assigns) do
    ~H""
  end
end
