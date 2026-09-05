defmodule MediaCentaurWeb.Components.Acquisition.MediaResults do
  @moduledoc """
  Flat media-search results — the TMDB answer sheet rendered as page
  content below the omnibox hero (UIDR-014). No floating overlay: the
  section exists exactly while the typed query is active
  (`active_query?/1`), and clearing the query is the one dismissal —
  no click-away, nothing to lose track of.

  While it renders, the search owns the page: the host hides the
  forecast, the same convention as the release-search zone — whose
  `grid` nav zone the result rows reuse (the two modes are exclusive,
  so only one grid exists at a time). The header strip (scope chips +
  Clear) is its own `toolbar` nav zone: the rows form a two-column
  grid (pick + bookmark, declared via the row-level `data-nav-grid`),
  and grid navigation is index arithmetic — header items sharing the
  zone would shift the pairing.

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

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.TMDB.Title

  attr :query, :string,
    required: true,
    doc: "The live query — the section renders only while `active_query?/1` holds."

  attr :results, :list, required: true, doc: "`Title.t()` rows, TMDB relevance order."
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

  attr :tracked_refs, :any,
    default: MapSet.new(),
    doc: "`{tmdb_id, media_type}` refs release tracking holds an open item for — the Tracked marker."

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
      class="mx-auto w-full max-w-3xl space-y-2"
    >
      <div class="flex items-center justify-between gap-3 px-1" data-nav-zone="toolbar">
        <span class="flex items-center gap-2 text-xs text-base-content/55">
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
          class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
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
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
      >
        Nothing found on TMDB.
      </div>

      <div
        :if={!@searching? && @results != [] && @visible == []}
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
      >
        No {if @scope == :upcoming, do: "upcoming", else: "released"} titles in these results.
      </div>

      <div data-nav-zone="grid" class="space-y-2">
        <.result_row
          :for={result <- @visible}
          result={result}
          status={release_status(result, @today)}
          release_mode_available={@release_mode_available}
          watchlisted?={MapSet.member?(@watchlisted_refs, {result.tmdb_id, result.media_type})}
          in_library?={MapSet.member?(@in_library_refs, {result.tmdb_id, result.media_type})}
          tracked?={MapSet.member?(@tracked_refs, {result.tmdb_id, result.media_type})}
        />
      </div>
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
          "border-base-content/15 text-base-content/55 hover:border-base-content/30 hover:text-base-content/70"
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

  attr :result, Title, required: true

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

  attr :tracked?, :boolean,
    required: true,
    doc:
      "Whether release tracking already holds this title — the Tracked marker, and no verb when upcoming."

  # A wrapper div owns the row surface: the main pick button and the
  # bookmark toggle are siblings — nested interactive elements are
  # invalid HTML. The wrapper is a real 2-track grid carrying
  # `data-nav-grid`: the input system reads its computed column count,
  # so DOWN/UP move row-to-row (pick → pick) and LEFT/RIGHT move
  # within a row (pick ↔ bookmark). Every row renders exactly these
  # two nav items.
  defp result_row(assigns) do
    assigns =
      assign(assigns, :verb, verb(assigns.tracked?, assigns.status, assigns.release_mode_available))

    ~H"""
    <div
      class="glass-surface grid w-full grid-cols-[1fr_auto] items-start gap-1 rounded-xl pr-2 transition-colors hover:bg-base-content/[0.05]"
      data-nav-grid
    >
      <button
        id={"omnibox-result-#{@result.media_type}-#{@result.tmdb_id}"}
        type="button"
        class="flex min-w-0 cursor-pointer items-start gap-4 py-3 pl-4 text-left"
        phx-click="omnibox_pick"
        phx-value-tmdb-id={@result.tmdb_id}
        phx-value-media-type={@result.media_type}
        data-nav-item
        tabindex="0"
      >
        <.title_summary title={@result} poster_url={title_poster_url(@result)}>
          <:markers>
            <span :if={@tracked?} class="shrink-0 text-xs text-success/70">Tracked</span>
            <%!-- Quiet neutral, deliberately unlike Tracked's success tint —
                in-library is metadata here, not a state this page owns. --%>
            <span :if={@in_library?} class="shrink-0 text-xs text-base-content/55">In library</span>
          </:markers>
        </.title_summary>

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
          "flex cursor-pointer items-center self-stretch px-2 transition-colors",
          @watchlisted? && "text-primary",
          !@watchlisted? && "text-base-content/55 hover:text-base-content/60"
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
  defp verb(true, :upcoming, _release_mode_available), do: nil
  defp verb(false, :upcoming, _release_mode_available), do: "Track release"
  defp verb(_tracked?, :released, true), do: "Download"
  defp verb(_tracked?, :released, false), do: "Track"

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
  missing one, because TMDB leaves unreleased titles undated. Takes a
  `TMDB.Title` — every caller now holds one (search rows, watchlist
  rows), so `:release_date` is read from a single shape.
  """
  @spec release_status(Title.t(), Date.t()) :: :released | :upcoming
  def release_status(%{release_date: nil}, _today), do: :upcoming

  def release_status(%{release_date: release_date}, today) do
    if Date.after?(release_date, today), do: :upcoming, else: :released
  end

  @doc """
  Applies the upcoming/released scope to the result list, preserving
  TMDB relevance order. `:all` passes everything through untouched.
  """
  @spec scope([Title.t()], :all | :upcoming | :released, Date.t()) :: [Title.t()]
  def scope(results, :all, _today), do: results

  def scope(results, scope, today) when scope in [:upcoming, :released] do
    Enum.filter(results, &(release_status(&1, today) == scope))
  end
end
