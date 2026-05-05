defmodule MediaCentarrWeb.Components.Detail.MoreInfo.CastGrid do
  @moduledoc """
  Shared cast-grid component used by the More info panel for movies and
  TV series alike. Renders a responsive grid of poster-style cards
  (photo + name + character) with TMDB person links when a
  `tmdb_person_id` is present. Cards without a profile photo fall back
  to a silhouette so the layout stays steady.

  Cast entries come from a `{:array, :map}` column with JSON-serialised
  string keys — the `:list` attr is loose-typed accordingly.
  """

  use MediaCentarrWeb, :html

  attr :cast, :list,
    required: true,
    doc:
      "list of cast maps (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`). Loose-typed because entries originate in a JSON-serialised :array, :map column."

  def cast_grid(assigns) do
    ~H"""
    <div :if={@cast != []}>
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
        Cast
      </h3>
      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
        <.card :for={person <- @cast} person={person} />
      </div>
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "single cast entry — string-keyed map matching the `cast` column shape (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`)."

  defp card(%{person: %{"tmdb_person_id" => id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person["tmdb_person_id"]}"}
      target="_blank"
      rel="noopener noreferrer"
      class="group focus:outline-none focus:ring-2 focus:ring-primary rounded-md"
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
    <div>
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

  attr :person, :map, required: true, doc: "same string-keyed map as `card/1`."

  defp photo(%{person: %{"profile_path" => path}} = assigns) when is_binary(path) do
    ~H"""
    <img
      src={"https://image.tmdb.org/t/p/w185#{@person["profile_path"]}"}
      alt={@person["name"]}
      loading="lazy"
      class="w-full aspect-[5/7] rounded-md object-cover bg-base-300"
    />
    """
  end

  defp photo(assigns) do
    ~H"""
    <div class="w-full aspect-[5/7] rounded-md bg-base-300/60 flex items-center justify-center">
      <.icon name="hero-user" class="size-10 text-base-content/30" />
    </div>
    """
  end
end
