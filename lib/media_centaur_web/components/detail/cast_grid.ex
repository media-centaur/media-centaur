defmodule MediaCentaurWeb.Components.Detail.CastGrid do
  @moduledoc """
  Cast grid for the detail modal's Cast view — movies and TV series
  alike. Renders a responsive grid of poster-style cards (photo + name +
  character) with TMDB person links when a `tmdb_person_id` is present.
  Cards without a profile photo fall back to a silhouette so the layout
  stays steady.

  ## Paging

  At most `limit` cards render at once, `page_size/0` (24) at first. TMDB
  `aggregate_credits.cast` for long-running TV series returns hundreds of
  entries; the first 24 by billing `order` covers the show's regulars +
  main recurring cast. A *Show more* disclosure pages in the next 24 —
  the host LiveView owns the limit (`EntityModal`'s `cast_limit`) and
  bumps it on `show_more_cast`, so paging survives re-renders and resets
  on entity switch alongside the filter.

  When the cast exceeds one page, the grid surfaces a filter input above
  it. The limit is enforced **after filtering** — only the first N
  matches render. Filtering searches the whole cast, not the visible
  window: the point is to find someone billed 300th.

  ## Why the filter is a server round-trip

  It used to be client-side. Every cast member was rendered, everything past
  the cap carrying `display: none`, so a JS hook could toggle visibility on
  each keystroke. The cost of that convenience was the full cast in the DOM
  and in the LiveView diff on every render — measured at **1.6 MB of HTML
  for one 899-member series**, to show 24 cards.

  Selecting the cast is now a `phx-change` away, so the server sends the
  cards it wants displayed and nothing else. This is a local desktop app
  talking over a local WebSocket; the round-trip it buys back is not one the
  user can perceive, and `phx-debounce` keeps it to one query per pause
  rather than one per keystroke. The same holds for *Show more* — each
  click is one round-trip for one more page.

  `visible_cast/3` and `match_count/2` are the whole selection rule, kept
  public and pure so they are tested directly rather than through rendered
  markup.

  Cast entries are `MediaCentaur.Library.Person` structs from the
  `embeds_many :cast` field on `Movie` and `TVSeries`.
  """

  use MediaCentaurWeb, :html

  # Cast cards added per page — the initial render and each Show more click.
  @page_size 24

  @doc "Cast cards per page — the initial limit and the Show more increment."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc """
  The cast members to render for `query`, capped at `limit`.

  An empty or nil query selects the first `limit` entries. Otherwise, entries
  whose name or character contains `query` (case-insensitive, matched
  literally) are selected, in billing order, up to `limit`.
  """
  @spec visible_cast([map()], String.t() | nil, non_neg_integer()) :: [map()]
  def visible_cast(cast, query, limit), do: Enum.take(matching_cast(cast, query), limit)

  @doc """
  How many cast members match `query` — the whole cast for an empty query.
  With `visible_cast/3` this yields the *Show more* remainder count.
  """
  @spec match_count([map()], String.t() | nil) :: non_neg_integer()
  def match_count(cast, query), do: length(matching_cast(cast, query))

  defp matching_cast(cast, query) do
    case String.trim(query || "") do
      "" -> cast
      trimmed -> Enum.filter(cast, &matches?(&1, String.downcase(trimmed)))
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

  attr :limit, :integer,
    default: @page_size,
    doc:
      "how many matches to render. Owned by the host LiveView (`EntityModal`'s `cast_limit`), bumped by `show_more_cast` and reset on entity switch."

  def cast_grid(assigns) do
    visible = visible_cast(assigns.cast, assigns[:filter], assigns.limit)
    remaining = match_count(assigns.cast, assigns[:filter]) - length(visible)

    assigns =
      assigns
      |> assign(:show_filter, length(assigns.cast) > @page_size)
      |> assign(:visible_cast, visible)
      |> assign(:remaining, remaining)

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

      <div :if={@remaining > 0} class="mt-4">
        <.button
          variant="neutral"
          size="sm"
          phx-click="show_more_cast"
          data-nav-item
          tabindex="0"
        >
          Show more ({@remaining} more)
        </.button>
      </div>
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
