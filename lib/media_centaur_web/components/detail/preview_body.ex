defmodule MediaCentaurWeb.Components.Detail.PreviewBody do
  @moduledoc """
  The facts of a `TitlePreview` below the cinematic frame's pinned
  lockup: the metadata row (with the media-type badge), the overview,
  the same facet strip the owned detail panel shows, and a top-cast
  strip (`Detail.CastStrip`). Identity (logo, title, tagline) and the
  hero imagery are the frame's, fed by the host; this is what sits under
  them. Worn by the plan modal's movie confirm stage.

  `library_state` adds the "in your library" line beside the metadata
  row for hosts whose action row does not already say it.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.CastStrip
  alias MediaCentaurWeb.Components.Detail.FacetStrip
  alias MediaCentaurWeb.Components.Detail.MetadataRow
  alias MediaCentaurWeb.Components.Detail.TitlePreview

  attr :preview, TitlePreview, required: true

  attr :library_state, :boolean,
    default: false,
    doc: "show the in-your-library line beside the metadata row"

  def preview_body(assigns) do
    ~H"""
    <div class="space-y-5" data-component="preview-body">
      <div class="flex items-center justify-between gap-3">
        <MetadataRow.metadata_row
          badge_text={TitlePreview.badge_text(@preview)}
          items={@preview.metadata_items}
        />
        <span
          :if={@library_state}
          class={[
            "flex-shrink-0 text-xs",
            if(@preview.in_library?, do: "text-warning/80", else: "text-base-content/55")
          ]}
        >
          {if @preview.in_library?, do: "Already in your library", else: "Not in your library"}
        </span>
      </div>

      <p :if={@preview.overview} class="text-sm text-base-content/70 line-clamp-6">
        {@preview.overview}
      </p>

      <FacetStrip.facet_strip :if={@preview.facets != []} facets={@preview.facets} />

      <CastStrip.cast_strip :if={@preview.cast != []} id="preview-cast" cast={@preview.cast} />
    </div>
    """
  end
end
