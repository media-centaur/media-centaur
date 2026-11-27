defmodule MediaCentaurWeb.Components.Detail.CastStrip do
  @moduledoc """
  *Top cast*: one row of round headshots with each person's name and
  character, scrolling sideways when it is wider than its column. A
  compact strip for a title the library does not own, not the Cast
  view's grid (`Detail.CastPanel`), which an owned title opens.

  Two surfaces draw it: the plan modal's movie confirm stage
  (`Detail.PreviewBody`) and the body of the title detail for a title
  the library does not own (`DetailPanel`). The cast arrives capped at
  the top-billed few (`Detail.TitlePreview`).
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [tmdb_cdn_url: 2]

  attr :id, :string, required: true, doc: "prefix for each person's stable element id."

  attr :cast, :list,
    required: true,
    doc: "top-billed `MediaCentaur.Library.Person` structs, in billing order."

  def cast_strip(assigns) do
    ~H"""
    <div data-component="cast-strip">
      <h3 class="text-[0.65rem] uppercase tracking-wider text-base-content/55 font-semibold mb-2">
        Top cast
      </h3>
      <div class="flex gap-3 overflow-x-auto thin-scrollbar pb-1">
        <div
          :for={person <- @cast}
          id={"#{@id}-#{:erlang.phash2({person.tmdb_person_id, person.name})}"}
          class="flex-shrink-0 w-16 text-center"
        >
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
