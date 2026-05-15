defmodule MediaCentarrWeb.Components.Detail.MoreInfo.CastGrid do
  @moduledoc """
  Shared cast-grid component used by the More info panel for movies and
  TV series alike. Renders a responsive grid of poster-style cards
  (photo + name + character) with TMDB person links when a
  `tmdb_person_id` is present. Cards without a profile photo fall back
  to a silhouette so the layout stays steady.

  ## Visible-card cap

  At most `@max_cast_cards` cards are visible at once. TMDB
  `aggregate_credits.cast` for long-running TV series (e.g. The
  Simpsons) returns hundreds of entries; the first 24 by billing
  `order` covers the show's regulars + main recurring cast.

  When the cast exceeds the cap, the grid surfaces a real-time filter
  input above it. The cap is enforced **even after filtering** — only
  the first N matches render. The whole list is rendered server-side
  (cards past the cap have `display: none` inline) so the JS hook in
  `assets/js/hooks/cast_grid_filter.js` can toggle visibility on each
  keystroke without a server round-trip.

  Cast entries are `MediaCentarr.Library.Person` structs from the
  `embeds_many :cast` field on `Movie` and `TVSeries`.
  """

  use MediaCentarrWeb, :html

  # Maximum number of cast cards visible at once on the More info grid.
  # See @moduledoc for rationale. Tune here if the visible count needs
  # to change; an inline expander/search can be layered on top later
  # without touching the data layer.
  @max_cast_cards 24

  attr :cast, :list,
    required: true,
    doc:
      "list of `MediaCentarr.Library.Person` structs (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`)."

  def cast_grid(assigns) do
    show_filter = length(assigns.cast) > @max_cast_cards

    assigns =
      assigns
      |> assign(:show_filter, show_filter)
      |> assign(:max_cast_cards, @max_cast_cards)
      |> assign(:indexed_cast, Enum.with_index(assigns.cast))

    ~H"""
    <div :if={@cast != []} id="cast-grid-section">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
        Cast
      </h3>

      <div
        :if={@show_filter}
        id="cast-grid-filter"
        phx-hook="CastGridFilter"
        phx-update="ignore"
        data-grid-id="cast-grid-grid"
        data-max-visible={@max_cast_cards}
        data-empty-state-id="cast-grid-empty"
        class="mb-3"
      >
        <div class="relative w-64 max-w-full">
          <.icon
            name="hero-magnifying-glass-mini"
            class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-base-content/40 pointer-events-none"
          />
          <input
            type="search"
            class="library-filter w-full pl-9 bg-base-content/5"
            placeholder="Filter cast"
            aria-label="Filter cast members"
          />
        </div>
      </div>

      <div
        id="cast-grid-grid"
        class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3"
      >
        <.card
          :for={{person, i} <- @indexed_cast}
          person={person}
          hidden={i >= @max_cast_cards}
        />
      </div>

      <p
        :if={@show_filter}
        id="cast-grid-empty"
        hidden
        class="text-sm text-base-content/60 mt-3"
      >
        No cast members match your filter.
      </p>
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "single `MediaCentarr.Library.Person` struct (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`)."

  attr :hidden, :boolean,
    default: false,
    doc:
      "render the card with `display: none` initially. Used for cards past the visible cap so they're already hidden before the JS filter hook mounts (no flash of full grid)."

  defp card(assigns) do
    ~H"""
    <div
      data-cast-card
      data-cast-name={searchable(@person.name)}
      data-cast-character={searchable(@person.character)}
      style={if @hidden, do: "display: none", else: nil}
    >
      <.card_inner person={@person} />
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc: "same `MediaCentarr.Library.Person` struct shape as `card/1`."

  defp card_inner(%{person: %{tmdb_person_id: id}} = assigns) when is_integer(id) do
    ~H"""
    <a
      href={"https://www.themoviedb.org/person/#{@person.tmdb_person_id}"}
      target="_blank"
      rel="noopener noreferrer"
      class="group focus:outline-none focus:ring-2 focus:ring-primary rounded-md block"
    >
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2 group-hover:text-primary transition-colors">
        {@person.name}
      </p>
      <p
        :if={@person.character}
        class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
      >
        {@person.character}
      </p>
    </a>
    """
  end

  defp card_inner(assigns) do
    ~H"""
    <div>
      <.photo person={@person} />
      <p class="mt-1.5 text-xs font-semibold leading-tight text-base-content line-clamp-2">
        {@person.name}
      </p>
      <p
        :if={@person.character}
        class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
      >
        {@person.character}
      </p>
    </div>
    """
  end

  attr :person, :map, required: true, doc: "same `MediaCentarr.Library.Person` struct as `card/1`."

  defp photo(%{person: %{profile_path: path}} = assigns) when is_binary(path) do
    ~H"""
    <img
      src={"https://image.tmdb.org/t/p/w185#{@person.profile_path}"}
      alt={@person.name}
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

  # Pre-lowercase name/character for the JS filter hook so it can do
  # cheap case-insensitive substring matching without re-lowercasing
  # every card on every keystroke.
  defp searchable(nil), do: ""
  defp searchable(""), do: ""
  defp searchable(value) when is_binary(value), do: String.downcase(value)
  defp searchable(_), do: ""
end
