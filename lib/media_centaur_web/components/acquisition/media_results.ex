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

  Each row leads with one verb: clicking downloads the title — opening
  the plan flow, which is a step toward it, not the goal — or tracks it
  when no indexer is configured. Same `omnibox_pick` contract the popup
  rows carried. A sibling bookmark button toggles the title on the
  watchlist (`watchlist_toggle`), and rows the library already presents
  carry a quiet "In library" marker. Pure rendering; events bubble to
  the parent LiveView (`omnibox_pick`, `omnibox_clear`,
  `watchlist_toggle`).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [tmdb_cdn_url: 2]

  alias MediaCentaur.ReleaseTracking.TitleResult

  attr :query, :string,
    required: true,
    doc: "The live query — the section renders only while `active_query?/1` holds."

  attr :results, :list, required: true, doc: "`TitleResult.t()` rows, TMDB relevance order."
  attr :searching?, :boolean, required: true

  attr :release_mode_available, :boolean,
    required: true,
    doc: "Whether an indexer is configured — flips the row verb between download and track."

  attr :scope, :atom,
    default: :all,
    values: [:all, :upcoming, :released],
    doc: "Release-status filter — the chips between the box and the rows; `:all` shows everything."

  attr :today, :any,
    default: nil,
    doc: "`Date.t()` the upcoming/released split compares against — nil means today (fixed in stories)."

  attr :watchlisted_refs, :any,
    default: MapSet.new(),
    doc: "`{tmdb_id, media_type}` refs on the watchlist."

  attr :in_library_refs, :any,
    default: MapSet.new(),
    doc: "`{tmdb_id, media_type}` refs the library has a presentable container for."

  def media_results(assigns) do
    today = assigns.today || Date.utc_today()

    assigns =
      assigns
      |> assign(:today, today)
      |> assign(:visible, scope(assigns.results, assigns.scope, today))
      |> assign(:upcoming_count, Enum.count(assigns.results, &(release_status(&1, today) == :upcoming)))
      |> assign(:released_count, Enum.count(assigns.results, &(release_status(&1, today) == :released)))

    ~H"""
    <section
      :if={active_query?(@query)}
      data-component="media-results"
      data-nav-zone="grid"
      class="mx-auto w-full max-w-3xl space-y-2"
    >
      <div class="flex items-center justify-between gap-3 px-1">
        <span class="flex items-center gap-2 text-xs text-base-content/40">
          <.scope_chip
            scope={:upcoming}
            label="Upcoming"
            count={@upcoming_count}
            active={@scope == :upcoming}
          />
          <.scope_chip
            scope={:released}
            label="Released"
            count={@released_count}
            active={@scope == :released}
          />
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

      <div
        :if={!@searching? && @results != [] && @visible == []}
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
      >
        No {if @scope == :upcoming, do: "upcoming", else: "released"} titles in these results.
      </div>

      <.result_row
        :for={result <- @visible}
        result={result}
        status={release_status(result, @today)}
        release_mode_available={@release_mode_available}
        watchlisted?={MapSet.member?(@watchlisted_refs, {result.tmdb_id, result.media_type})}
        in_library?={MapSet.member?(@in_library_refs, {result.tmdb_id, result.media_type})}
      />
    </section>
    """
  end

  attr :scope, :atom, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active, :boolean, required: true

  # One filter chip. Rendered while it has anything to offer or is the
  # active scope (so toggling off stays possible when a refined query
  # empties its side). Clicking the active chip returns to everything —
  # the host's `omnibox_scope` handler owns that toggle.
  defp scope_chip(assigns) do
    ~H"""
    <button
      :if={@count > 0 || @active}
      type="button"
      class={[
        "cursor-pointer rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors",
        @active && "border-primary/50 bg-primary/10 text-primary",
        !@active &&
          "border-base-content/15 text-base-content/50 hover:border-base-content/30 hover:text-base-content/70"
      ]}
      phx-click="omnibox_scope"
      phx-value-scope={@scope}
      aria-pressed={to_string(@active)}
      data-nav-item
      tabindex="0"
    >
      {@label} <span class="opacity-60">{@count}</span>
    </button>
    """
  end

  attr :result, TitleResult, required: true

  attr :status, :atom,
    required: true,
    values: [:upcoming, :released],
    doc: "`release_status/2` of this row — picks the verb the click honestly performs."

  attr :release_mode_available, :boolean, required: true

  attr :watchlisted?, :boolean,
    required: true,
    doc: "Whether this title is on the watchlist — fills the bookmark."

  attr :in_library?, :boolean,
    required: true,
    doc: "Whether the library already presents this title — the quiet In library marker."

  # A wrapper div owns the row surface: the main pick button and the
  # bookmark toggle are siblings — nested interactive elements are
  # invalid HTML.
  defp result_row(assigns) do
    assigns =
      assign(assigns, :verb, verb(assigns.result, assigns.status, assigns.release_mode_available))

    ~H"""
    <div class="glass-surface flex w-full items-start gap-1 rounded-xl pr-2 transition-colors hover:bg-base-content/[0.05]">
      <button
        id={"omnibox-result-#{@result.media_type}-#{@result.tmdb_id}"}
        type="button"
        class="flex min-w-0 flex-1 cursor-pointer items-start gap-4 py-3 pl-4 text-left"
        phx-click="omnibox_pick"
        phx-value-tmdb-id={@result.tmdb_id}
        phx-value-media-type={@result.media_type}
        data-nav-item
        tabindex="0"
      >
        <span class="flex h-[72px] w-12 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-base-content/10">
          <img
            :if={@result.poster_path}
            src={tmdb_cdn_url(@result.poster_path, :w92)}
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
            <%!-- Quiet neutral, deliberately unlike Tracked's success tint —
                in-library is metadata here, not a state this page owns. --%>
            <span :if={@in_library?} class="shrink-0 text-xs text-base-content/50">In library</span>
          </span>
          <span
            :if={@result.overview}
            class="line-clamp-2 block text-xs leading-relaxed text-base-content/55"
          >
            {@result.overview}
          </span>
        </span>

        <span
          :if={@verb}
          class="inline-flex shrink-0 items-center gap-1 self-center text-xs font-medium text-primary/70"
        >
          {@verb}
          <.icon name="hero-chevron-right-mini" class="size-3.5" />
        </span>
      </button>

      <button
        id={"omnibox-watchlist-#{@result.media_type}-#{@result.tmdb_id}"}
        type="button"
        class={[
          "cursor-pointer self-center px-2 py-2 transition-colors",
          @watchlisted? && "text-primary",
          !@watchlisted? && "text-base-content/30 hover:text-base-content/60"
        ]}
        phx-click="watchlist_toggle"
        phx-value-tmdb-id={@result.tmdb_id}
        phx-value-media-type={@result.media_type}
        aria-pressed={to_string(@watchlisted?)}
        title={if @watchlisted?, do: "Remove from watchlist", else: "Add to watchlist"}
        data-nav-item
        tabindex="0"
      >
        <.icon
          name={if @watchlisted?, do: "hero-bookmark-solid", else: "hero-bookmark"}
          class="size-4"
        />
      </button>
    </div>
    """
  end

  # The row's one verb, honest per release status: a released title can
  # be downloaded (or tracked without an indexer); an unreleased one can
  # only be tracked — the host's `omnibox_pick` performs exactly this
  # split. The verb names the goal, not the planning step it opens with.
  # An already-tracked upcoming row affords nothing further, so the verb
  # slot stays empty (the identity line carries the Tracked marker).
  defp verb(%TitleResult{tracked?: true}, :upcoming, _release_mode_available), do: nil
  defp verb(%TitleResult{}, :upcoming, _release_mode_available), do: "Track release"
  defp verb(%TitleResult{}, :released, true), do: "Download"
  defp verb(%TitleResult{}, :released, false), do: "Track"

  @doc """
  Whether the typed query is active — two or more characters after
  trimming. The section (and the search's ownership of the page)
  exists exactly while this holds.
  """
  @spec active_query?(String.t()) :: boolean()
  def active_query?(query), do: String.length(String.trim(query)) >= 2

  @doc """
  A title's release status as of `today`. A passed date (including
  today) is `:released`; a future date is `:upcoming` — and so is a
  missing one, because TMDB leaves unreleased titles undated. Accepts
  anything carrying `:release_date` (`TitleResult`, `WatchlistItem`).
  """
  @spec release_status(%{release_date: Date.t() | nil}, Date.t()) :: :released | :upcoming
  def release_status(%{release_date: nil}, _today), do: :upcoming

  def release_status(%{release_date: release_date}, today) do
    if Date.after?(release_date, today), do: :upcoming, else: :released
  end

  @doc """
  Applies the upcoming/released scope to the result list, preserving
  TMDB relevance order. `:all` passes everything through untouched.
  """
  @spec scope([TitleResult.t()], :all | :upcoming | :released, Date.t()) :: [TitleResult.t()]
  def scope(results, :all, _today), do: results

  def scope(results, scope, today) when scope in [:upcoming, :released] do
    Enum.filter(results, &(release_status(&1, today) == scope))
  end
end
