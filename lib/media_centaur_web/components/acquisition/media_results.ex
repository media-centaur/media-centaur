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
  Clear) is its own `toolbar` nav zone.

  This module owns the list, not the row. Each result is a
  `Components.Title.Row` — identity, quiet markers, the whole card
  opening the title detail modal, where every verb lives (spec
  2026-09-05 §14). Media search was the last surface still carrying its
  own verb; it no longer does, so a search result and a Discovery row
  are the same row.

  Pure rendering; events bubble to the parent LiveView (`open_title`
  from the row, `omnibox_clear` and `omnibox_scope` from the header).
  """

  use Phoenix.Component

  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Components.Title.Row, as: TitleRow

  attr :query, :string,
    required: true,
    doc: "The live query — the section renders only while `active_query?/1` holds."

  attr :results, :list, required: true, doc: "`Title.t()` rows, TMDB relevance order."
  attr :searching?, :boolean, required: true

  attr :metadata_available, :boolean,
    default: true,
    doc:
      "Whether TMDB is configured. Every row on this surface comes from TMDB, so with no key the search cannot return anything — the empty answer then names the missing capability instead of reporting a miss the query never had a chance to hit."

  attr :scope, :atom,
    default: :all,
    values: [:all, :upcoming, :released],
    doc: "Release-status filter — the chips between the box and the rows; `:all` shows everything."

  attr :today, :any,
    default: nil,
    doc: "`Date.t()` the upcoming/released split compares against — nil means today (fixed in stories)."

  attr :title_rungs, :any,
    default: %{},
    doc: "`%{{tmdb_id, media_type} => rung}` — where each title sits on the ladder."

  attr :in_library_refs, :any,
    default: MapSet.new(),
    doc: "`{tmdb_id, media_type}` refs the library has a presentable container for."

  attr :default_grab_mode, :string,
    required: true,
    doc:
      "the resolved Default rung, for the row's tracking marker — `AutoGrabSettings.load().default_mode`."

  attr :friend_activity_by_ref, :map,
    default: %{},
    doc:
      "`%{ref => rows}` from `Activities.friend_activity_for/1` for the landed results — the pennants on the mast."

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

      <%!-- Two different empty answers. "Nothing found" is a claim about the
            query; it is only true when the search actually ran. --%>
      <div
        :if={!@searching? && @results == [] && @metadata_available}
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
      >
        Nothing found on TMDB.
      </div>

      <div
        :if={!@searching? && @results == [] && !@metadata_available}
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
      >
        <p class="text-base-content/70">Searching titles needs a TMDB key.</p>
        <p class="mt-1">
          Media Centaur looks titles up on The Movie Database. Add a key and this search works,
          along with artwork and release tracking.
        </p>
        <.link
          navigate="/settings?section=tmdb"
          class="mt-3 inline-block link link-primary"
          data-nav-item
          tabindex="0"
        >
          Add a TMDB key
        </.link>
      </div>

      <div
        :if={!@searching? && @results != [] && @visible == []}
        class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
      >
        No {if @scope == :upcoming, do: "upcoming", else: "released"} titles in these results.
      </div>

      <div data-nav-zone="grid" class="space-y-2">
        <TitleRow.title_row
          :for={result <- @visible}
          id={"omnibox-result-#{result.media_type}-#{result.tmdb_id}"}
          title={result}
          poster_url={title_poster_url(result)}
          markers={markers(result, assigns)}
          friend_activity={Map.get(@friend_activity_by_ref, Title.ref(result), [])}
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

  # The row's markers, from the one builder every title row uses.
  # `acquisition_state: nil` because this page does not read
  # `Acquisition.title_state/2` per result — a scheduled convergence, and
  # a one-word change here when it does.
  defp markers(%Title{} = result, assigns) do
    ref = Title.ref(result)

    Logic.row_markers(%{
      in_library?: MapSet.member?(assigns.in_library_refs, ref),
      acquisition_state: nil,
      rung: Map.get(assigns.title_rungs, ref),
      default_grab_mode: assigns.default_grab_mode
    })
  end

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
