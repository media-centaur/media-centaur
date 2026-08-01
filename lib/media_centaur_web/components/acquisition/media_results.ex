defmodule MediaCentaurWeb.Components.Acquisition.MediaResults do
  @moduledoc """
  Flat media-search results — the TMDB answer sheet rendered as page
  content below the omnibox hero (UIDR-014). No floating overlay: the
  section exists exactly while the typed query is active
  (`active_query?/1`), and clearing the query is the one dismissal —
  no click-away, nothing to lose track of.

  While it renders, the search owns the page: the host hides the
  forecast, the same convention as the release-search zone — whose
  `grid` nav zone this reuses (the two modes are exclusive, so only
  one grid exists at a time).

  Each row is one verb: clicking plans the download (or tracks, when
  no indexer is configured) — the same `omnibox_pick` contract the
  popup rows carried. Pure rendering; events bubble to the parent
  LiveView (`omnibox_pick`, `omnibox_clear`).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.ReleaseTracking.TitleResult

  attr :query, :string,
    required: true,
    doc: "The live query — the section renders only while `active_query?/1` holds."

  attr :results, :list, required: true, doc: "`TitleResult.t()` rows, TMDB relevance order."
  attr :searching?, :boolean, required: true

  attr :release_mode_available, :boolean,
    required: true,
    doc: "Whether an indexer is configured — flips the row verb between plan and track."

  def media_results(assigns) do
    ~H"""
    <section
      :if={active_query?(@query)}
      data-component="media-results"
      data-nav-zone="grid"
      class="mx-auto w-full max-w-3xl space-y-2"
    >
      <div class="flex items-center justify-between gap-3 px-1">
        <span class="flex items-center gap-2 text-xs text-base-content/40">
          <span :if={@searching?} class="loading loading-spinner loading-xs"></span>
          <span :if={@searching?}>Searching TMDB…</span>
        </span>
        <%!-- The input is cleared client-side too (the app.js
              omnibox:clear-input listener): LiveView never overwrites a
              focused input's value, so the server-side query reset alone
              would leave stale text in the box. --%>
        <button
          id="media-results-clear"
          type="button"
          class="cursor-pointer text-xs text-base-content/30 transition-colors hover:text-base-content/60"
          phx-click={
            Phoenix.LiveView.JS.dispatch("omnibox:clear-input", to: "#omnibox-media-input")
            |> Phoenix.LiveView.JS.push("omnibox_clear")
          }
          data-nav-item
          tabindex="0"
        >
          Clear search
        </button>
      </div>

      <div
        :if={!@searching? && @results == []}
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
      >
        Nothing found on TMDB.
      </div>

      <.result_row
        :for={result <- @results}
        result={result}
        release_mode_available={@release_mode_available}
      />
    </section>
    """
  end

  attr :result, TitleResult, required: true
  attr :release_mode_available, :boolean, required: true

  defp result_row(assigns) do
    ~H"""
    <button
      id={"omnibox-result-#{@result.media_type}-#{@result.tmdb_id}"}
      type="button"
      class="glass-surface flex w-full cursor-pointer items-start gap-4 rounded-xl px-4 py-3 text-left transition-colors hover:bg-base-content/[0.05]"
      phx-click="omnibox_pick"
      phx-value-tmdb-id={@result.tmdb_id}
      phx-value-media-type={@result.media_type}
      data-nav-item
      tabindex="0"
    >
      <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
        <img
          :if={@result.poster_path}
          src={"https://image.tmdb.org/t/p/w92#{@result.poster_path}"}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <.icon
          :if={!@result.poster_path}
          name={if @result.media_type == :movie, do: "hero-film-mini", else: "hero-tv-mini"}
          class="size-5 text-base-content/25"
        />
      </span>

      <span class="min-w-0 flex-1 space-y-0.5 self-center">
        <span class="flex items-baseline gap-2">
          <span class="truncate text-sm font-semibold">{@result.name}</span>
          <%!-- Quiet text, not colored chips — type is metadata; color
                stays reserved for interaction and state. --%>
          <span class="shrink-0 text-xs text-base-content/50">
            {if @result.media_type == :movie, do: "Movie", else: "TV"}<span :if={@result.year}> · {@result.year}</span>
          </span>
          <span :if={@result.tracked?} class="shrink-0 text-xs text-success/70">Tracked</span>
        </span>
        <span
          :if={@result.overview}
          class="line-clamp-2 block text-xs leading-relaxed text-base-content/55"
        >
          {@result.overview}
        </span>
      </span>

      <span class="inline-flex shrink-0 items-center gap-1 self-center text-xs font-medium text-primary/70">
        {if @release_mode_available, do: "Plan download", else: "Track"}
        <.icon name="hero-chevron-right-mini" class="size-3.5" />
      </span>
    </button>
    """
  end

  @doc """
  Whether the typed query is active — two or more characters after
  trimming. The section (and the search's ownership of the page)
  exists exactly while this holds.
  """
  @spec active_query?(String.t()) :: boolean()
  def active_query?(query), do: String.length(String.trim(query)) >= 2
end
