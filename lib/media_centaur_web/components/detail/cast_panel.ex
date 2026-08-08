defmodule MediaCentaurWeb.Components.Detail.CastPanel do
  @moduledoc """
  *Cast* sub-view of the detail modal — the people behind the title.

  ## What leads

  For a TV series the view leads, unlabelled, with the cast of the
  episode Play would start (the resume target, or the first present
  episode) — that ordering is simply how the page is, not an announced
  feature. Everyone else follows under *Other episodes*. Both sections
  are ordered by total appearances (`CastSelection.order_by_appearances/1`);
  the lead section renders in full, and the *Show more* disclosure pages
  only the second. Membership comes from `Episode.cast_person_ids`
  (season regulars + guest stars, TMDB person ids referencing the series'
  aggregate-cast embeds).

  With no membership data (pre-backfill library, no present episodes) or
  an active filter, the view degrades to a single appearance-ordered
  list — filtering searches the whole cast, so sections would only hide
  matches. Movies are always the single list, in billing order (their
  cast carries no appearance counts), under a *Directed by / Written by*
  headline — the only show-level credit worth a line.

  Selection rules are pure functions in `CastSelection`; this module is
  the markup. `lead_cast_ids/2` is public for its unit tests (ADR-030).
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.{CastSelection, People}

  attr :entity, :map,
    required: true,
    doc:
      "entity-map produced by `MediaCentaur.Library.Views.DetailItem.to_entity_map/1`. Reads `:type`, `:crew`, `:cast`, and `:seasons` (episode cast membership)."

  attr :cast_filter, :string,
    default: "",
    doc: "current cast filter query, owned by the host LiveView."

  attr :cast_limit, :integer,
    default: nil,
    doc:
      "how many paged cast matches to render, owned by the host LiveView (`EntityModal`); `nil` falls back to one page."

  attr :resume_episode_key, :any,
    default: nil,
    doc:
      "`{season_number, episode_number}` of the episode Play would start, or nil — same value the episode list highlights."

  def cast_panel(assigns) do
    cast = assigns.entity[:cast] || []
    filter = assigns[:cast_filter] || ""
    limit = assigns.cast_limit || CastSelection.page_size()
    filtering? = CastSelection.filtering?(filter)

    lead_ids =
      if filtering?, do: [], else: lead_cast_ids(assigns.entity, assigns.resume_episode_key)

    {lead, rest} = CastSelection.partition_by_membership(cast, lead_ids)

    {single_visible, rest_visible, remaining} =
      if lead == [] do
        ordered = CastSelection.order_by_appearances(cast)
        visible = CastSelection.visible_cast(ordered, filter, limit)
        {visible, [], CastSelection.match_count(ordered, filter) - length(visible)}
      else
        rest_visible = Enum.take(rest, limit)
        {nil, rest_visible, length(rest) - length(rest_visible)}
      end

    assigns =
      assigns
      |> assign(:cast, cast)
      |> assign(:filter, filter)
      |> assign(:filtering?, filtering?)
      |> assign(:show_filter, length(cast) > CastSelection.page_size())
      |> assign(:lead, lead)
      |> assign(:single_visible, single_visible)
      |> assign(:rest_visible, rest_visible)
      |> assign(:remaining, remaining)

    ~H"""
    <section class="space-y-6 pt-2 pb-4">
      <.movie_headline entity={@entity} />
      <div :if={@cast != []} id="cast-grid-section">
        <.filter_form :if={@show_filter} filter={@filter} />
        <%= if @single_visible do %>
          <.card_grid id="cast-grid-grid" cast={@single_visible} />
          <p :if={@single_visible == [] && @filtering?} class="text-sm text-base-content/60 mt-3">
            No cast members match your filter.
          </p>
        <% else %>
          <.card_grid id="cast-grid-lead" cast={@lead} />
          <div :if={@rest_visible != []} class="mt-6">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/60 mb-3">
              Other episodes
            </h3>
            <.card_grid id="cast-grid-rest" cast={@rest_visible} />
          </div>
        <% end %>
        <.show_more :if={@remaining > 0} remaining={@remaining} />
      </div>
    </section>
    """
  end

  @doc """
  The membership ids (`Episode.cast_person_ids`) of the episode Play
  would start: the resume-target episode when its key matches a loaded
  episode, otherwise the first episode with a present file — the same
  episode `Playback.play/1`'s resolver would pick for a fresh series.
  Returns `[]` for movies, series without loaded seasons, or episodes
  without membership data — the panel then degrades to the single list.
  """
  @spec lead_cast_ids(map(), {non_neg_integer(), non_neg_integer()} | nil) :: [integer()]
  def lead_cast_ids(entity, resume_episode_key) do
    episodes =
      for season <- entity[:seasons] || [],
          episode <- season[:episodes] || [],
          do: {season[:season_number], episode}

    target =
      find_by_key(episodes, resume_episode_key) ||
        Enum.find(episodes, fn {_season_number, episode} -> episode[:content_url] end)

    case target do
      {_season_number, episode} -> episode[:cast_person_ids] || []
      nil -> []
    end
  end

  defp find_by_key(_episodes, nil), do: nil

  defp find_by_key(episodes, {season_number, episode_number}) do
    Enum.find(episodes, fn {sn, episode} ->
      sn == season_number and episode[:episode_number] == episode_number
    end)
  end

  defp movie_headline(%{entity: %{type: :movie}} = assigns) do
    crew = assigns.entity[:crew] || []

    assigns =
      assigns
      |> assign(:directors, filter_crew(crew, ["Director"]))
      |> assign(:writers, filter_crew(crew, ["Screenplay", "Writer", "Story"]))

    ~H"""
    <div :if={@directors != [] or @writers != []} class="space-y-1.5 text-sm">
      <p :if={@directors != []}>
        <span class="text-base-content/60">Directed by</span>
        <People.people people={@directors} />
      </p>
      <p :if={@writers != []}>
        <span class="text-base-content/60">Written by</span>
        <People.people people={@writers} />
      </p>
    </div>
    """
  end

  defp movie_headline(assigns), do: ~H""

  defp filter_crew(crew, jobs), do: Enum.filter(crew, &(&1.job in jobs))

  attr :filter, :string, required: true

  defp filter_form(assigns) do
    ~H"""
    <form phx-change="filter_cast" class="mb-3">
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
    """
  end

  attr :id, :string, required: true

  attr :cast, :list,
    required: true,
    doc: "the `MediaCentaur.Library.Person` structs to render, already selected and ordered."

  defp card_grid(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
      <.card :for={person <- @cast} person={person} />
    </div>
    """
  end

  attr :remaining, :integer, required: true

  defp show_more(assigns) do
    ~H"""
    <div class="mt-4">
      <.button variant="neutral" size="sm" phx-click="show_more_cast" data-nav-item tabindex="0">
        Show more ({@remaining} more)
      </.button>
    </div>
    """
  end

  attr :person, :map,
    required: true,
    doc:
      "single `MediaCentaur.Library.Person` struct (`name`, `character`, `tmdb_person_id`, `profile_path`, `order`, `total_episode_count`)."

  defp card(assigns) do
    ~H"""
    <div>
      <.card_inner person={@person} />
    </div>
    """
  end

  attr :person, :map, required: true, doc: "same `MediaCentaur.Library.Person` struct as `card/1`."

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
      <.card_details person={@person} />
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
      <.card_details person={@person} />
    </div>
    """
  end

  attr :person, :map, required: true, doc: "same `MediaCentaur.Library.Person` struct as `card/1`."

  defp card_details(assigns) do
    ~H"""
    <p
      :if={@person.character}
      class="mt-0.5 text-[11px] leading-tight text-base-content/60 line-clamp-2"
    >
      {@person.character}
    </p>
    <p :if={@person.total_episode_count} class="mt-0.5 text-[11px] leading-tight text-base-content/40">
      {episode_count_label(@person.total_episode_count)}
    </p>
    """
  end

  defp episode_count_label(1), do: "1 episode"
  defp episode_count_label(count), do: "#{count} episodes"

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
