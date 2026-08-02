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

  attr :scope, :atom,
    default: :all,
    values: [:all, :upcoming, :released],
    doc: "Release-status filter — the chips between the box and the rows; `:all` shows everything."

  attr :today, :any,
    default: nil,
    doc: "`Date.t()` the upcoming/released split compares against — nil means today (fixed in stories)."

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
        release_mode_available={@release_mode_available}
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

  @doc """
  A result's release status as of `today`. A passed date (including
  today) is `:released`; a future date is `:upcoming` — and so is a
  missing one, because TMDB leaves unreleased titles undated.
  """
  @spec release_status(TitleResult.t(), Date.t()) :: :released | :upcoming
  def release_status(%TitleResult{release_date: nil}, _today), do: :upcoming

  def release_status(%TitleResult{release_date: release_date}, today) do
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
