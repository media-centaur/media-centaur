defmodule MediaCentaurWeb.Components.Acquisition.PursuitHeader do
  @moduledoc "Identity card shown inside the pursuit detail modal — title, state, recipe, criteria."

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [badge: 1]
  import MediaCentaurWeb.LiveHelpers, only: [banner_hue: 1]

  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader
  alias MediaCentaurWeb.Components.Acquisition.PursuitStyle

  attr :vm, PursuitHeader, required: true

  def pursuit_header(assigns) do
    assigns =
      assigns
      |> Phoenix.Component.assign(:display_title, display_title(assigns.vm))
      |> Phoenix.Component.assign(:release_subtitle, release_subtitle(assigns.vm))

    ~H"""
    <%!-- Flat section, not its own card (a nested glass-surface here
          created card-on-card-on-card with the rows below). TMDB-door
          pursuits get a real hero: the cached backdrop as the panel's
          background with logo PNG (or logotype fallback) and the
          identity facts — type, state, criteria, the literal search
          queries — overlaid on the scrim (UIDR-011/014). The synthetic
          gradient remains the no-artwork fallback. Query-door pursuits
          keep the flat title row: imagery means a title you chose. --%>
    <header>
      <div
        :if={@vm.recipe.recipe_type == :tmdb}
        class="relative flex items-end"
        style={"--banner-hue: #{banner_hue(@display_title)}; min-height: 13rem;"}
      >
        <%!-- With cached artwork the panel itself carries the backdrop +
              atmosphere (pursuit_modal); this block only supplies the
              synthetic fallback. --%>
        <div :if={!@vm.backdrop_url} class="identity-backdrop absolute inset-0"></div>

        <div class="relative z-[1] w-full space-y-2 px-6 pb-4 pt-14">
          <div class="flex items-end justify-between gap-3">
            <img
              :if={@vm.logo_url}
              src={@vm.logo_url}
              alt={@display_title}
              title={@display_title}
              class="text-on-image-lg max-h-16 max-w-[55%] object-contain object-left"
              loading="eager"
              decoding="sync"
            />
            <h2 :if={!@vm.logo_url} class="identity-logotype min-w-0 truncate text-2xl leading-tight">
              {@display_title}
            </h2>
            <PursuitStyle.state_badge state={@vm.state} awaiting_decision?={@vm.awaiting_decision?} />
          </div>

          <div class="text-on-image flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
            <.badge variant="type" size="xs">
              {if @vm.recipe.tmdb_type in [:movie, "movie"], do: "Movie", else: "TV"}
            </.badge>
            <span :if={recipe_summary(@vm.recipe)} class="text-base-content/80">
              {recipe_summary(@vm.recipe)}
            </span>
            <span :if={@vm.criteria_summary} class="text-base-content/70">
              {@vm.criteria_summary}
            </span>
          </div>

          <div
            :if={@vm.recipe.search_queries != []}
            class="text-on-image space-y-0.5 text-xs text-base-content/70"
          >
            <ul class="space-y-0.5">
              <li
                :for={query <- @vm.recipe.search_queries}
                class="truncate font-mono text-base-content/80"
                title={query}
              >
                {query}
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div
        :if={@vm.recipe.recipe_type != :tmdb}
        class="flex items-baseline justify-between gap-3 px-6 pt-6"
      >
        <h2 class="text-lg font-medium truncate">{@display_title}</h2>
        <PursuitStyle.state_badge state={@vm.state} awaiting_decision?={@vm.awaiting_decision?} />
      </div>

      <div class="px-6 pt-2 space-y-2">
        <%!-- Prowlarr-query pursuits store the picked release filename in
            `vm.title` once an alternative is chosen, but the user-meaningful
            identity is the query they typed. We hoist the query to the
            heading and demote the release filename to a monospace
            subtitle so the file is still visible but doesn't dominate. --%>
        <div
          :if={@release_subtitle}
          class="text-xs font-mono text-base-content/50 truncate"
          title={@release_subtitle}
        >
          {@release_subtitle}
        </div>

        <div
          :if={@vm.recipe.recipe_type != :tmdb && recipe_summary(@vm.recipe)}
          class="text-xs text-base-content/70"
        >
          {recipe_summary(@vm.recipe)}
        </div>

        <div
          :if={@vm.recipe.recipe_type != :tmdb && @vm.criteria_summary}
          class="text-xs text-base-content/60"
        >
          Criteria: {@vm.criteria_summary}
        </div>

        <%!-- The literal Prowlarr query/queries this pursuit runs. Always
            visible — "Searching Prowlarr" should never be abstract; the
            user can compare these strings to what they'd paste into
            Prowlarr by hand. TMDB recipes carry them on the hero above;
            this block covers query-door pursuits (the brace-expanded
            list, or the literal query when expansion fails). --%>
        <div
          :if={@vm.recipe.recipe_type != :tmdb && @vm.recipe.search_queries != []}
          class="text-xs text-base-content/60 space-y-0.5"
        >
          <div class="text-base-content/50">{search_label(@vm.recipe.search_queries)}</div>
          <ul class="space-y-0.5">
            <li
              :for={query <- @vm.recipe.search_queries}
              class="font-mono text-base-content/80 truncate"
              title={query}
            >
              {query}
            </li>
          </ul>
        </div>
      </div>
    </header>
    """
  end

  defp search_label([_]), do: "Search query"
  defp search_label(_), do: "Search queries"

  # The heading text. For a Prowlarr-query pursuit, the manual query is
  # the human-meaningful identity; for everything else, `vm.title` is
  # already the show / movie name.
  defp display_title(%{recipe: %{recipe_type: :prowlarr_query, manual_query: q}, title: title}) do
    cond do
      is_binary(q) and q != "" -> q
      is_binary(title) and title != "" -> title
      true -> "(untitled pursuit)"
    end
  end

  defp display_title(%{title: title}) when is_binary(title), do: title
  defp display_title(_), do: "(untitled pursuit)"

  # The release filename — shown as a demoted subtitle for Prowlarr-query
  # pursuits only. TMDB pursuits don't carry a release filename as `title`.
  defp release_subtitle(%{recipe: %{recipe_type: :prowlarr_query, manual_query: q}, title: title})
       when is_binary(title) and title != "" do
    if title != q, do: title
  end

  defp release_subtitle(_), do: nil

  # The recipe_summary line for prowlarr_query just labels the kind —
  # the manual_query is already shown as the heading.
  defp recipe_summary(%{recipe_type: :prowlarr_query}), do: "Prowlarr query"
  defp recipe_summary(%{tmdb_type: "movie", year: nil}), do: "Movie"
  defp recipe_summary(%{tmdb_type: "movie", year: year}), do: "Movie • #{year}"
  defp recipe_summary(%{tmdb_type: "tv", season_number: nil}), do: "TV"

  defp recipe_summary(%{tmdb_type: "tv", season_number: season, episode_number: nil}),
    do: "TV • S#{pad(season)}"

  defp recipe_summary(%{tmdb_type: "tv", season_number: season, episode_number: episode}),
    do: "TV • S#{pad(season)}E#{pad(episode)}"

  defp recipe_summary(%{tmdb_type: type}) when is_binary(type), do: type
  defp recipe_summary(_), do: nil

  defp pad(num) when is_integer(num) and num < 10, do: "0#{num}"
  defp pad(num) when is_integer(num), do: "#{num}"
end
