defmodule MediaCentaurWeb.Components.Detail.MoreInfo.CastGrid do
  @moduledoc """
  Shared cast-grid component used by the More info panel for movies and
  TV series alike. Renders a responsive grid of poster-style cards
  (photo + name + character) with TMDB person links when a
  `tmdb_person_id` is present. Cards without a profile photo fall back
  to a silhouette so the layout stays steady.

  ## Visible-card cap

  At most `@max_cast_cards` cards render at once. TMDB
  `aggregate_credits.cast` for long-running TV series returns hundreds of
  entries; the first 24 by billing `order` covers the show's regulars +
  main recurring cast.

  When the cast exceeds the cap, the grid surfaces a filter input above it.
  The cap is enforced **after filtering** — only the first N matches render.
  Filtering searches the whole cast, not the visible window: the point is to
  find someone billed 300th.

  ## Why the filter is a server round-trip

  It used to be client-side. Every cast member was rendered, everything past
  the cap carrying `display: none`, so a JS hook could toggle visibility on
  each keystroke. The cost of that convenience was the full cast in the DOM
  and in the LiveView diff on every render — measured at **1.6 MB of HTML
  for one 899-member series**, to show 24 cards.

  Selecting the cast is now a `phx-change` away, so the server sends the 24
  cards it wants displayed and nothing else. This is a local desktop app
  talking over a local WebSocket; the round-trip it buys back is not one the
  user can perceive, and `phx-debounce` keeps it to one query per pause
  rather than one per keystroke.

  `visible_cast/3` is the whole selection rule, kept public and pure so it
  is tested directly rather than through rendered markup.

  Cast entries are `MediaCentaur.Library.Person` structs from the
  `embeds_many :cast` field on `Movie` and `TVSeries`.
  """

  use MediaCentaurWeb, :html

  # Maximum number of cast cards rendered at once on the More info grid.
  # See @moduledoc for rationale.
  @max_cast_cards 24

  @doc """
  The cast members to render for `query`, capped at `max`.

  An empty or nil query selects the first `max` entries. Otherwise, entries
  whose name or character contains `query` (case-insensitive, matched
  literally) are selected, in billing order, up to `max`.
  """
  @spec visible_cast([map()], String.t() | nil, non_neg_integer()) :: [map()]
  def visible_cast(cast, query, max) do
    case String.trim(query || "") do
      "" -> Enum.take(cast, max)
      trimmed -> cast |> Enum.filter(&matches?(&1, String.downcase(trimmed))) |> Enum.take(max)
    end
  end

  defp matches?(person, query) do
    String.contains?(searchable(person.name), query) or
      String.contains?(searchable(person.character), query)
  end

  defp searchable(value) when is_binary(value), do: String.downcase(value)
  defp searchable(_value), do: ""

  attr :cast, :list,
    required: true,
    doc:
      "list of `MediaCentaur.Library.Person` structs (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`)."

  attr :filter, :string,
    default: "",
    doc:
      "current cast filter query. Owned by the host LiveView (`EntityModal`), which resets it when the modal switches entities."

  def cast_grid(assigns) do
    assigns =
      assigns
      |> assign(:show_filter, length(assigns.cast) > @max_cast_cards)
      |> assign(:visible_cast, visible_cast(assigns.cast, assigns[:filter], @max_cast_cards))

    ~H"""
    <div :if={@cast != []} id="cast-grid-section">
      <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
        Cast
      </h3>

      <form :if={@show_filter} phx-change="filter_cast" class="mb-3">
        <div class="relative w-64 max-w-full">
          <.icon
            name="hero-magnifying-glass-mini"
            class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-base-content/40 pointer-events-none"
          />
          <input
            type="search"
            name="cast_filter"
            value={@filter}
            phx-debounce="150"
            class="library-filter w-full pl-9 bg-base-content/5"
            placeholder="Filter cast"
            aria-label="Filter cast members"
          />
        </div>
      </form>

      <div
        id="cast-grid-grid"
        class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3"
      >
        <.card :for={person <- @visible_cast} person={person} />
      </div>

      <p :if={@visible_cast == []} class="text-sm text-base-content/60 mt-3">
        No cast members match your filter.
      </p>
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "single `MediaCentaur.Library.Person` struct (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`)."

  defp card(assigns) do
    ~H"""
    <div>
      <.card_inner person={@person} />
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc: "same `MediaCentaur.Library.Person` struct shape as `card/1`."

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

  attr :person, :map, required: true, doc: "same `MediaCentaur.Library.Person` struct as `card/1`."

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
end
