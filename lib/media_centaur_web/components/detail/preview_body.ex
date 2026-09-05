defmodule MediaCentaurWeb.Components.Detail.PreviewBody do
  @moduledoc """
  The facts of a `TitlePreview` below the cinematic frame's pinned
  lockup: the metadata row (with the media-type badge), the overview,
  the same facet strip the owned detail panel shows, and a top-cast
  strip. Identity (logo, title, tagline) and the hero imagery are the
  frame's, fed by the host; this is what sits under them. Shared by the
  plan modal's movie confirm stage and the Discovery title detail
  modal, so a title reads the same on both.

  `library_state` adds the "in your library" line beside the metadata
  row for hosts whose action row does not already say it.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [tmdb_cdn_url: 2]

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

      <.cast_strip :if={@preview.cast != []} cast={@preview.cast} />
    </div>
    """
  end

  attr :cast, :list,
    required: true,
    doc: "top-billed `MediaCentaur.Library.Person` structs (capped by `TitlePreview`)."

  # Circular thumbs with name and character — a confirmation strip, not
  # the full cast grid the owned detail panel offers.
  defp cast_strip(assigns) do
    ~H"""
    <div>
      <h3 class="text-[0.65rem] uppercase tracking-wider text-base-content/55 font-semibold mb-2">
        Top cast
      </h3>
      <div class="flex gap-3 overflow-x-auto thin-scrollbar pb-1">
        <div :for={person <- @cast} class="flex-shrink-0 w-16 text-center">
          <img
            :if={person.profile_path}
            src={tmdb_cdn_url(person.profile_path, :w185)}
            alt={person.name}
            loading="eager"
            decoding="sync"
            class="w-16 h-16 rounded-full object-cover bg-base-300"
          />
          <div
            :if={!person.profile_path}
            class="w-16 h-16 rounded-full bg-base-300/60 flex items-center justify-center"
          >
            <.icon name="hero-user" class="size-6 text-base-content/30" />
          </div>
          <p class="mt-1 text-[11px] leading-tight text-base-content/80 line-clamp-2">
            {person.name}
          </p>
          <p
            :if={person.character}
            class="text-[10px] leading-tight text-base-content/55 line-clamp-1"
          >
            {person.character}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
