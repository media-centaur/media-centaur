defmodule MediaCentarrWeb.Components.Detail.CastStrip do
  @moduledoc """
  Horizontal scrollable strip of cast cards rendered at the bottom of
  the movie detail modal. Each card shows a TMDB profile photo, actor
  name, and character name; clicking opens the TMDB person page in a
  new tab.

  Photos are hotlinked from `image.tmdb.org/t/p/w185{path}` — same
  pattern the review UI uses for unimported posters. Cast members
  without a `profile_path` get a silhouette icon. Cards without a
  `tmdb_person_id` (defensive) render as non-interactive.
  """

  use MediaCentarrWeb, :html

  @cast_doc "list of maps as stored on `MediaCentarr.Library.Movie.cast` — string keys: `name`, `character`, `tmdb_person_id`, `profile_path`, `order`."

  attr :cast, :list, required: true, doc: @cast_doc

  def cast_strip(assigns) do
    ~H"""
    <section :if={@cast != []} class="pt-4 pb-2">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
        Cast
      </h3>
      <div class="flex gap-3 overflow-x-auto pb-2 -mx-1 px-1 scroll-smooth">
        <.card :for={person <- @cast} person={person} />
      </div>
    </section>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "single cast entry — string-keyed map matching `MediaCentarr.Library.Movie.cast` shape (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`). Loose-typed because the value lives inside a `{:array, :map}` Ecto column where keys are JSON-serialised; tightening to a struct would require a normalisation step at the Library boundary that v1 deliberately defers."

  defp card(%{person: %{"tmdb_person_id" => id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person["tmdb_person_id"]}"}
      target="_blank"
      rel="noopener noreferrer"
      class="shrink-0 w-[110px] group focus:outline-none focus:ring-2 focus:ring-primary rounded-md"
    >
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2 group-hover:text-primary transition-colors">
        {@person["name"]}
      </p>
      <p
        :if={@person["character"]}
        class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
      >
        {@person["character"]}
      </p>
    </a>
    """
  end

  defp card(assigns) do
    ~H"""
    <div class="shrink-0 w-[110px]">
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2">
        {@person["name"]}
      </p>
      <p
        :if={@person["character"]}
        class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
      >
        {@person["character"]}
      </p>
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc: "same string-keyed cast entry as `card/1`'s `person` attr — see that doc for shape rationale."

  defp photo(%{person: %{"profile_path" => path}} = assigns) when is_binary(path) do
    ~H"""
    <img
      src={"https://image.tmdb.org/t/p/w185#{@person["profile_path"]}"}
      alt={@person["name"]}
      loading="lazy"
      class="w-[110px] h-[140px] rounded-md object-cover bg-base-300"
    />
    """
  end

  defp photo(assigns) do
    ~H"""
    <div class="w-[110px] h-[140px] rounded-md bg-base-300/60 flex items-center justify-center">
      <.icon name="hero-user" class="size-10 text-base-content/30" />
    </div>
    """
  end
end
