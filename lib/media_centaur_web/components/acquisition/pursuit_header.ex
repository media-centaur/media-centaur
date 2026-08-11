defmodule MediaCentaurWeb.Components.Acquisition.PursuitHeader do
  @moduledoc """
  The pursuit modal's presentation of the `PursuitHeader` view-model,
  split across the cinematic frame's two seatings: `pursuit_header/1`
  is the pinned identity for the `:orientation` slot (lockup, state
  badge, meta line), `pursuit_facts/1` is the search facts atop the
  scrolling body (release subtitle, literal indexer queries).
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Acquisition.ViewModels.PursuitHeader
  alias MediaCentaurWeb.Components.Acquisition.PursuitStyle
  alias MediaCentaurWeb.Components.Detail.TitleLayer

  attr :vm, PursuitHeader, required: true

  @doc """
  Pinned identity for the cinematic frame's `:orientation` slot: the
  shared `TitleLayer.lockup` (logo PNG when the artwork cache has one,
  logotype fallback), the state badge, and one meta line — type icon +
  label, scope (year / SxxExx), criteria. The frame supplies the
  backdrop; this block only reads `logo_url`.
  """
  def pursuit_header(assigns) do
    assigns = assign(assigns, :display_title, display_title(assigns.vm))

    ~H"""
    <div class="px-6">
      <div class="flex items-end justify-between gap-3">
        <div class="min-w-0">
          <TitleLayer.lockup title={@display_title} logo_url={@vm.logo_url} />
        </div>
        <PursuitStyle.state_badge state={@vm.state} awaiting_decision?={@vm.awaiting_decision?} />
      </div>
      <p class="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 pb-5 text-xs uppercase tracking-wider text-base-content/50 text-on-image">
        <.icon name={type_icon(@vm.recipe)} class="size-4" />
        <span>{type_label(@vm.recipe)}</span>
        <span :if={scope(@vm.recipe)}>· {scope(@vm.recipe)}</span>
        <span :if={@vm.criteria_summary} class="normal-case tracking-normal text-base-content/40">
          · {@vm.criteria_summary}
        </span>
      </p>
    </div>
    """
  end

  attr :vm, PursuitHeader, required: true

  @doc """
  The pursuit's search facts, seated at the top of the modal body: the
  release-filename subtitle (Prowlarr-query pursuits that already
  picked a release, demoted to monospace so the file stays visible
  without dominating) and the literal indexer queries — "Searching
  Prowlarr" should never be abstract; the user can compare these
  strings to what they'd paste into Prowlarr by hand. Renders nothing
  when there is nothing to show.
  """
  def pursuit_facts(assigns) do
    assigns = assign(assigns, :release_subtitle, release_subtitle(assigns.vm))

    ~H"""
    <div :if={@release_subtitle || @vm.search_queries != []} class="space-y-2">
      <div
        :if={@release_subtitle}
        class="text-xs font-mono text-base-content/50 truncate"
        title={@release_subtitle}
      >
        {@release_subtitle}
      </div>

      <div :if={@vm.search_queries != []} class="text-xs text-base-content/60 space-y-0.5">
        <div class="text-base-content/50">{search_label(@vm.search_queries)}</div>
        <ul class="space-y-0.5">
          <li
            :for={query <- @vm.search_queries}
            class="font-mono text-base-content/80 truncate"
            title={query}
          >
            {query}
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp search_label([_]), do: "Search query"
  defp search_label(_), do: "Search queries"

  defp type_icon(%{type: :prowlarr_query}), do: "hero-magnifying-glass"
  defp type_icon(%{tmdb_type: type}) when type in [:movie, "movie"], do: "hero-film"
  defp type_icon(_recipe), do: "hero-tv"

  defp type_label(%{type: :prowlarr_query}), do: "Prowlarr query"
  defp type_label(%{tmdb_type: type}) when type in [:movie, "movie"], do: "Movie"
  defp type_label(_recipe), do: "TV series"

  # The meta line already opens with the type label — this is only the
  # scope beyond it (year, SxxExx), so "Movie" never reads twice.
  defp scope(%{type: :prowlarr_query}), do: nil

  defp scope(%{tmdb_type: type, year: year}) when type in [:movie, "movie"], do: if(year, do: "#{year}")

  defp scope(%{season_number: nil}), do: nil
  defp scope(%{season_number: season, episode_number: nil}), do: "S#{pad(season)}"

  defp scope(%{season_number: season, episode_number: episode}), do: "S#{pad(season)}E#{pad(episode)}"

  defp scope(_recipe), do: nil

  # The heading text. For a Prowlarr-query pursuit, the manual query is
  # the human-meaningful identity; for everything else, `vm.title` is
  # already the show / movie name.
  defp display_title(%{recipe: %{type: :prowlarr_query, manual_query: q}, title: title}) do
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
  defp release_subtitle(%{recipe: %{type: :prowlarr_query, manual_query: q}, title: title})
       when is_binary(title) and title != "" do
    if title != q, do: title
  end

  defp release_subtitle(_), do: nil

  defp pad(num) when is_integer(num) and num < 10, do: "0#{num}"
  defp pad(num) when is_integer(num), do: "#{num}"
end
