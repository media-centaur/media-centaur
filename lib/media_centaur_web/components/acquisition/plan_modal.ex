defmodule MediaCentaurWeb.Components.Acquisition.PlanModal do
  @moduledoc """
  The plan-flow modal (UIDR-014): one continuous, URL-driven surface
  carrying a media-search request from targeting through approval —
  no wizard step-dots.

  The whole surface is a tenant of the cinematic modal frame
  (`CinematicShell`), wearing the title's backdrop from the moment the
  modal opens (the picked search result dresses the loading stage)
  through targeting, confirm, and the board. The host picks the
  per-stage source via `PlanLogic.shell_backdrop_url/2`.

  Stages, driven by the host LiveView's `?plan=` param:

  * `:loading` — the targeting universe is being fetched.
  * `:targeting` — the series picker: quick-action presets, tri-state
    season rows, episode drill-in; in-library rows greyed (shown,
    never hidden), unaired rows inert.
  * `:movie_confirm` — the movie fast path: one card, two clicks.
  * `:board` — the live coverage board over the durable draft plan:
    unit cells in season rows (consecutive same-release cells fuse
    into a capsule — consolidation made visible), the chosen releases
    beneath with swap/exclude, below-floor offers ("lower quality
    available" with the picker as the explicit override), gaps as an
    explicit warning row, and the approval footer. Refresh-safe by
    construction.
  * `:error` — targeting failed (TMDB unreachable etc.).

  Pure rendering; the host owns all state and events.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [format_size: 1, tmdb_cdn_url: 2]

  alias MediaCentaurWeb.Components.Acquisition.CellVocabulary
  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
  alias MediaCentaurWeb.IncomingLive.MoviePreview
  alias MediaCentaurWeb.IncomingLive.PlanLogic
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.FacetStrip
  alias MediaCentaurWeb.Components.Detail.MetadataRow
  alias MediaCentaurWeb.Components.Detail.TitleLayer

  attr :open, :boolean, required: true

  attr :stage, :atom,
    default: :loading,
    values: [:loading, :targeting, :movie_confirm, :board, :error]

  attr :backdrop_url, :string,
    default: nil,
    doc:
      "the shell's cinematic backdrop — one identity following the request through every " <>
        "stage (PlanLogic.shell_backdrop_url/2 picks the source per stage). Nil renders the " <>
        "atmosphere scrim alone."

  attr :identity, :any,
    default: nil,
    doc:
      "%ReleaseTracking.TitleResult{} | nil — the picked search result, dressing the " <>
        ":loading stage the instant the modal opens."

  attr :selection, :any,
    default: nil,
    doc: "%Targeting.Selection{} | nil — the picker's universe (targeting stage)."

  attr :chosen, :any,
    default: nil,
    doc: "MapSet of {season, episode} — the picker's chosen units (targeting stage)."

  attr :expanded_seasons, :any,
    default: nil,
    doc:
      "MapSet of season numbers the picker shows expanded (targeting stage) — nil/empty means every season collapsed."

  attr :movie, :any,
    default: nil,
    doc:
      "%MediaCentaurWeb.IncomingLive.MoviePreview{} | nil — the movie fast path's detail-shaped preview (built by PlanLogic.movie_preview/2)."

  attr :board, :any,
    default: nil,
    doc: "%PlanBoard{} | nil — the live coverage board (board stage)."

  attr :grab_future, :boolean, default: false
  attr :error, :string, default: nil, doc: "Targeting-stage failure copy (error stage)."

  attr :last_activity, :string,
    default: nil,
    doc: "Latest PlanEvents.SearchActivity line for the board's ticker, or nil."

  attr :descent, :any,
    default: nil,
    doc: "%DescentNarrative.View{} | nil — the board's expectation panel (TV plans)."

  attr :alternatives, :any,
    default: nil,
    doc:
      "%{unit_id, items: [PlanBoard.Alternative.t()], searching?: boolean} | nil — the open swap picker (board stage)."

  attr :approving, :boolean,
    default: false,
    doc: "Approval grabs in flight — the footer button shows progress and ignores clicks."

  attr :search_health, :any,
    default: nil,
    doc:
      "`MediaCentaur.Search.IndexerHealth.t()` | nil — when `blind?/1`, the gap banner says availability couldn't be checked instead of claiming unavailability (UIDR-016)."

  attr :gap_verdict, :any,
    default: nil,
    doc:
      "`ViewModels.GapVerdict.t()` | nil — the gap banner's adaptive diagnosis (UIDR-022); nil while the board has no gaps."

  attr :rejected, :any,
    default: nil,
    doc:
      "%{unit_id, items: [PlanBoard.Alternative.t()]} | nil — the open rejected-results panel (UIDR-022, movie boards only)."

  attr :on_close, :string, default: "close_plan"

  def plan_modal(assigns) do
    lockup =
      PlanLogic.lockup(assigns.stage, %{
        identity: assigns.identity,
        selection: assigns.selection,
        movie: assigns.movie,
        board: assigns.board
      })

    assigns = assign(assigns, :lockup, lockup)

    ~H"""
    <%!-- The plan modal wears the same cinematic frame as the library
          detail modal (pinned identity lockup over a fixed backdrop) —
          a just-picked title reads as the same surface as one already
          owned; only the imagery source differs (hotlinked TMDB for
          this browsing-tier surface). One backdrop persists across
          stage patches, so targeting → board keeps the identity painted
          without a re-decode; per-stage scroll offsets are remembered
          through view_key. --%>
    <CinematicShell.cinematic_shell
      id="plan-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close={@on_close}
      present={@open}
      backdrop_url={@backdrop_url}
      scroll_key={@lockup && @lockup.title}
      view_key={@stage}
      data-plan-modal
      data-detail-mode={@open && "modal"}
      data-dismiss-event={@on_close}
    >
      <:orientation>
        <div :if={@lockup} class="px-6 pb-5">
          <TitleLayer.lockup
            title={@lockup.title}
            logo_url={@lockup.logo_url}
            tagline={@lockup.tagline}
          />
        </div>
      </:orientation>
      <:body>
        <.loading_stage :if={@stage == :loading} />

        <div :if={@stage == :error} class="p-8 text-center text-sm space-y-3">
          <p class="text-error">{@error || "Couldn't load this title from TMDB."}</p>
          <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
            Close
          </.button>
        </div>

        <.targeting_stage
          :if={@stage == :targeting && @selection}
          selection={@selection}
          chosen={@chosen || MapSet.new()}
          expanded_seasons={@expanded_seasons || MapSet.new()}
          grab_future={@grab_future}
          on_close={@on_close}
        />

        <.movie_stage :if={@stage == :movie_confirm && @movie} movie={@movie} on_close={@on_close} />

        <.board_stage
          :if={@stage == :board && @board}
          board={@board}
          alternatives={@alternatives}
          approving={@approving}
          last_activity={@last_activity}
          descent={@descent}
          search_health={@search_health}
          gap_verdict={@gap_verdict}
          rejected={@rejected}
          on_close={@on_close}
        />
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Loading stage
  # ---------------------------------------------------------------------------

  # The identity lives in the pinned lockup (a picked result dresses the
  # modal the instant it opens); this stage is just the honest status
  # line beneath it.
  defp loading_stage(assigns) do
    ~H"""
    <div class="p-6 flex items-center gap-2 text-sm text-base-content/50">
      <span class="loading loading-spinner loading-xs"></span> Loading from TMDB…
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Targeting stage
  # ---------------------------------------------------------------------------

  attr :selection, Targeting.Selection, required: true
  attr :chosen, :any, required: true, doc: "MapSet — typed at the public attr."
  attr :expanded_seasons, :any, required: true, doc: "MapSet — typed at the public attr."
  attr :grab_future, :boolean, required: true
  attr :on_close, :string, required: true

  defp targeting_stage(assigns) do
    assigns = assign(assigns, :chosen_count, MapSet.size(assigns.chosen))

    ~H"""
    <div class="flex flex-col max-h-full">
      <div class="p-6 pb-6 space-y-5">
        <%!-- Identity (logo/title) lives in the pinned lockup above; this
              line carries the stage's facts — season/episode meta and the
              tracked marker. --%>
        <p class="text-sm text-base-content/60 text-on-image">
          {selection_meta(@selection)}
          <.badge :if={@selection.tracked?} variant="warning" size="xs" class="ml-2 align-middle">
            Tracked
          </.badge>
        </p>

        <div class="flex flex-wrap items-center gap-2">
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="everything_aired"
            data-nav-item
            tabindex="0"
          >
            Everything aired
          </.button>
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="continue"
            data-nav-item
            tabindex="0"
          >
            Continue from my library
          </.button>
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="latest_season"
            data-nav-item
            tabindex="0"
          >
            Latest season
          </.button>
          <.button
            variant="neutral"
            size="sm"
            phx-click="plan_preset"
            phx-value-preset="none"
            data-nav-item
            tabindex="0"
          >
            None
          </.button>
          <span class="ml-auto text-sm text-base-content/50 tabular-nums">
            {@chosen_count} selected
          </span>
        </div>

        <div class="space-y-2">
          <.season_row
            :for={season <- @selection.seasons}
            season={season}
            selection={@selection}
            chosen={@chosen}
            expanded={MapSet.member?(@expanded_seasons, season.season_number)}
          />
        </div>
      </div>

      <div class="border-t border-base-content/10 px-6 py-4 flex items-center justify-between gap-4">
        <label class="flex items-center gap-2 text-sm text-base-content/70 cursor-pointer">
          <input
            type="checkbox"
            checked={@grab_future}
            class="checkbox checkbox-sm checkbox-primary"
            phx-click="plan_toggle_grab_future"
            data-nav-item
            tabindex="0"
          />
          <span>
            Also grab future episodes
            <span class="block text-[11px] text-base-content/40">hands off to release tracking</span>
          </span>
        </label>
        <div class="flex items-center gap-2">
          <.button
            :if={!@selection.tracked?}
            variant="neutral"
            size="sm"
            phx-click="plan_track_only"
            title="Follow future releases — download nothing now"
            data-nav-item
            tabindex="0"
          >
            Track only
          </.button>
          <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
            Cancel
          </.button>
          <.button
            variant="primary"
            size="sm"
            phx-click="plan_create"
            aria-disabled={to_string(@chosen_count == 0)}
            class={@chosen_count == 0 && "opacity-50"}
            data-nav-item
            tabindex="0"
          >
            Download {@chosen_count} {if @chosen_count == 1, do: "episode", else: "episodes"}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :season, Targeting.Season, required: true
  attr :selection, Targeting.Selection, required: true
  attr :chosen, :any, required: true, doc: "MapSet — typed at the public attr."
  attr :expanded, :boolean, required: true

  defp season_row(assigns) do
    assigns =
      assign(assigns, :state, PlanLogic.season_state(assigns.chosen, assigns.selection, assigns.season))

    ~H"""
    <div class={["glass-inset rounded-lg", @state == :disabled && "opacity-50"]}>
      <div class="flex items-center gap-3 px-4 py-2.5">
        <.tri_checkbox
          state={@state}
          phx-click="plan_toggle_season"
          phx-value-season={@season.season_number}
        />
        <button
          type="button"
          class="flex flex-1 min-w-0 items-center gap-3 text-left"
          phx-click="plan_toggle_season_expand"
          phx-value-season={@season.season_number}
          disabled={@state == :disabled}
          data-nav-item={@state != :disabled}
          tabindex={if @state == :disabled, do: "-1", else: "0"}
        >
          <span class="text-sm font-medium">Season {@season.season_number}</span>
          <span class="text-sm text-base-content/40">{season_meta(@season)}</span>
          <.icon
            :if={@state != :disabled}
            name={if @expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
            class="size-4 ml-auto text-base-content/40"
          />
        </button>
      </div>
      <ul :if={@state != :disabled && @expanded} class="border-t border-base-content/5">
        <li
          :for={episode <- @season.episodes}
          id={"plan-episode-#{episode.season_number}-#{episode.episode_number}"}
          class={[
            "flex items-baseline gap-3 pl-10 pr-4 py-2",
            (!episode.aired? || episode.in_library?) && "opacity-40"
          ]}
        >
          <.tri_checkbox
            :if={episode.aired? && !episode.in_library?}
            state={
              if MapSet.member?(@chosen, {episode.season_number, episode.episode_number}),
                do: :checked,
                else: :unchecked
            }
            small
            phx-click="plan_toggle_unit"
            phx-value-season={episode.season_number}
            phx-value-episode={episode.episode_number}
          />
          <span :if={!episode.aired? || episode.in_library?} class="w-4 flex-shrink-0"></span>
          <span class="min-w-0 flex-1 truncate text-sm">
            E{String.pad_leading(to_string(episode.episode_number), 2, "0")} · {episode.label}
          </span>
          <span :if={episode.in_library?} class="flex-shrink-0 text-xs text-base-content/40">
            In library
          </span>
          <span
            :if={episode.tracked? && !episode.in_library?}
            class="flex-shrink-0 text-xs text-info/70"
            title="Release tracking is already watching for this — check it to grab it in this plan instead"
          >
            Tracked
          </span>
          <span :if={!episode.aired?} class="flex-shrink-0 text-xs text-base-content/40">
            Unaired
          </span>
          <span
            :if={episode.aired? && !episode.in_library? && episode.air_date}
            class="flex-shrink-0 text-xs text-base-content/30 tabular-nums"
          >
            {episode.air_date}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr :state, :atom,
    required: true,
    doc:
      ":checked | :indeterminate | :unchecked | :disabled — the closed set PlanLogic.season_state/3 returns; private component, exercised through the targeting variation."

  attr :small, :boolean, default: false

  attr :rest, :global,
    doc: "phx-click/phx-value-* passthrough — the checkbox is a dumb button; callers own the event."

  defp tri_checkbox(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex-shrink-0 rounded border flex items-center justify-center transition-colors",
        @small && "w-4 h-4",
        !@small && "w-[18px] h-[18px]",
        @state in [:checked, :indeterminate] && "bg-primary/80 border-primary",
        @state == :unchecked && "border-base-content/30 hover:border-base-content/60",
        @state == :disabled && "border-base-content/15"
      ]}
      disabled={@state == :disabled}
      data-nav-item
      tabindex="0"
      {@rest}
    >
      <.icon :if={@state == :checked} name="hero-check-mini" class="size-3 text-base-100" />
      <.icon :if={@state == :indeterminate} name="hero-minus-mini" class="size-3 text-base-100" />
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Movie stage
  # ---------------------------------------------------------------------------

  attr :movie, MoviePreview,
    required: true,
    doc: "detail-shaped preview built by PlanLogic.movie_preview/2 in the host's targeting task."

  attr :on_close, :string, required: true

  defp movie_stage(assigns) do
    # The identity (logo/title/tagline) lives in the frame's pinned
    # lockup; the hero imagery is the frame's backdrop (the host feeds
    # it backdrop-or-poster via PlanLogic.shell_backdrop_url). This
    # stage is the facts below.
    ~H"""
    <div>
      <div class="px-6 pt-6 pb-6 space-y-5">
        <div class="flex items-center justify-between gap-3">
          <MetadataRow.metadata_row badge_text="Movie" items={@movie.metadata_items} />
          <span class={[
            "flex-shrink-0 text-xs",
            if(@movie.in_library?, do: "text-warning/80", else: "text-base-content/40")
          ]}>
            {if @movie.in_library?, do: "Already in your library", else: "Not in your library"}
          </span>
        </div>

        <p :if={@movie.overview} class="text-sm text-base-content/70 line-clamp-6">
          {@movie.overview}
        </p>

        <FacetStrip.facet_strip :if={@movie.facets != []} facets={@movie.facets} />

        <.cast_strip :if={@movie.cast != []} cast={@movie.cast} />
      </div>

      <div class="border-t border-base-content/10 px-6 py-4 flex items-center justify-end gap-2">
        <%!-- Only a movie that isn't out yet has a release to watch for;
              for one already out, tracking would promise nothing. --%>
        <.button
          :if={!@movie.in_library? && @movie.upcoming?}
          variant="neutral"
          size="sm"
          phx-click="plan_track_only"
          title="Watch for this movie's release — download nothing now"
          data-nav-item
          tabindex="0"
        >
          Track release
        </.button>
        <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
          Cancel
        </.button>
        <.button
          variant="primary"
          size="sm"
          phx-click="plan_create"
          aria-disabled={to_string(@movie.in_library?)}
          class={@movie.in_library? && "opacity-50"}
          data-nav-item
          tabindex="0"
        >
          Download
        </.button>
      </div>
    </div>
    """
  end

  attr :cast, :list,
    required: true,
    doc:
      "top-billed `MediaCentaur.Library.Person` structs (capped by PlanLogic.movie_preview/2) — a compact confirmation strip, not the owned detail panel's full cast grid."

  defp cast_strip(assigns) do
    ~H"""
    <div>
      <h3 class="text-[0.65rem] uppercase tracking-wider text-base-content/40 font-semibold mb-2">
        Top cast
      </h3>
      <div class="flex gap-3 overflow-x-auto thin-scrollbar pb-1">
        <div :for={person <- @cast} class="flex-shrink-0 w-16 text-center">
          <img
            :if={person.profile_path}
            src={tmdb_cdn_url(person.profile_path, :w185)}
            alt={person.name}
            loading="eager"
            decoding="sync"
            class="w-16 h-16 rounded-full object-cover bg-base-300"
          />
          <div
            :if={!person.profile_path}
            class="w-16 h-16 rounded-full bg-base-300/60 flex items-center justify-center"
          >
            <.icon name="hero-user" class="size-6 text-base-content/30" />
          </div>
          <p class="mt-1 text-[11px] leading-tight text-base-content/80 line-clamp-2">
            {person.name}
          </p>
          <p
            :if={person.character}
            class="text-[10px] leading-tight text-base-content/40 line-clamp-1"
          >
            {person.character}
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Board stage
  # ---------------------------------------------------------------------------

  attr :board, PlanBoard, required: true

  attr :alternatives, :any,
    required: true,
    doc:
      "%{unit_id, items: [PlanBoard.Alternative.t()], searching?: boolean} | nil — the open swap picker (board stage)."

  attr :approving, :boolean, required: true
  attr :last_activity, :string, required: true

  attr :descent, :any,
    required: true,
    doc: "%DescentNarrative.View{} | nil — typed at the public attr."

  attr :search_health, :any,
    required: true,
    doc: "IndexerHealth.t() | nil — typed at the public attr."

  attr :gap_verdict, :any,
    required: true,
    doc: "GapVerdict.t() | nil — typed at the public attr."

  attr :rejected, :any,
    required: true,
    doc: "%{unit_id, items} | nil — typed at the public attr."

  attr :on_close, :string, required: true

  defp board_stage(assigns) do
    ~H"""
    <div class="flex flex-col max-h-full">
      <div class="p-6 pb-6 space-y-6">
        <div>
          <%!-- The title lives in the pinned lockup; this is the plan's
                live status line. --%>
          <p class="text-sm text-on-image">
            <span :if={@board.status == :planning} class="text-base-content/50">
              <span class="loading loading-spinner loading-xs align-middle mr-1"></span>
              Planning · {@board.wanted} {if @board.movie?, do: "unit", else: "episodes"} wanted
            </span>
            <span :if={@board.status == :ready} class="text-info">
              Plan ready · {@board.covered} of {@board.wanted} covered
            </span>
            <span :if={@board.status == :committed} class="text-success">
              Committed — the pursuit has taken over.
            </span>
          </p>
        </div>

        <div :if={@descent} class="glass-inset rounded-lg px-4 py-3 space-y-2">
          <p class="text-sm text-base-content/70">{@descent.headline}</p>
          <div :for={row <- @descent.rows} class="flex items-center gap-2 text-xs">
            <span class={["size-1.5 rounded-full flex-shrink-0", descent_dot(row.state)]}></span>
            <span class={[
              "w-32 flex-shrink-0 text-base-content/60",
              row.state == :skipped && "line-through text-base-content/30"
            ]}>
              {row.label}
            </span>
            <span class="min-w-0 truncate text-base-content/40">{row.detail}</span>
          </div>
        </div>

        <div :if={!@board.movie?} class="space-y-2">
          <div :for={season <- @board.seasons} class="flex items-start gap-3">
            <span class="flex-shrink-0 w-10 pt-2 text-sm text-base-content/40 tabular-nums">
              S{season.season_number}
            </span>
            <div class="flex min-w-0 flex-1 flex-wrap items-center gap-1">
              <%= for run <- PlanLogic.cell_runs(season.cells) do %>
                <div
                  :if={match?({:capsule, _, _}, run)}
                  class="flex flex-wrap gap-px rounded-lg border border-primary/60 bg-primary/10 p-0.5"
                  title={run |> elem(2) |> hd() |> Map.get(:release_title)}
                >
                  <.board_cell :for={cell <- elem(run, 2)} cell={cell} in_capsule />
                </div>
                <.board_cell :if={match?({:cell, _}, run)} cell={elem(run, 1)} />
              <% end %>
            </div>
          </div>
        </div>

        <div :if={@board.releases != []} class="space-y-2">
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
            Releases — {length(@board.releases)}
          </h3>
          <div :for={release <- @board.releases} class="space-y-2">
            <div
              id={"plan-release-#{release.swap_unit_id}"}
              class="glass-inset rounded-lg px-4 py-2.5 flex items-center gap-3"
            >
              <ReleaseFacts.release_facts entry={release_entry(release)} />
              <.button
                :if={@board.status == :ready}
                variant="neutral"
                size="xs"
                class="flex-shrink-0"
                phx-click={
                  if @alternatives && @alternatives.unit_id == release.swap_unit_id,
                    do: "plan_hide_alternatives",
                    else: "plan_show_alternatives"
                }
                phx-value-unit-id={release.swap_unit_id}
                title="See the other options for this"
                data-nav-item
                tabindex="0"
              >
                Options
              </.button>
              <.button
                :if={@board.status == :ready}
                variant="destructive_inline"
                size="xs"
                shape="square"
                class="flex-shrink-0"
                phx-click="plan_swap_release"
                phx-value-unit-id={release.swap_unit_id}
                phx-value-guid={release.guid}
                title="Remove this release — exclude it everywhere and re-solve"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-x-mark-mini" class="size-3.5" />
              </.button>
            </div>

            <.alternatives_panel
              :if={@alternatives && @alternatives.unit_id == release.swap_unit_id}
              alternatives={@alternatives}
              release={release}
            />
          </div>
        </div>

        <div
          :for={overlap <- @board.overlaps}
          :if={@board.status == :ready}
          id={"plan-overlap-#{:erlang.phash2(overlap.exclude_guid)}"}
          class="glass-inset rounded-lg px-4 py-3 border border-warning/30 flex items-center gap-3"
        >
          <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning flex-shrink-0" />
          <span class="min-w-0 flex-1 text-sm text-warning/90">{overlap.description}</span>
          <.button
            variant="risky"
            size="xs"
            class="flex-shrink-0"
            phx-click="plan_swap_release"
            phx-value-unit-id={overlap.exclude_unit_id}
            phx-value-guid={overlap.exclude_guid}
            title="Exclude this release everywhere and let the planner re-solve without it"
            data-nav-item
            tabindex="0"
          >
            {overlap.action_label}
          </.button>
        </div>

        <div
          :for={offer <- @board.offers}
          :if={@board.status == :ready}
          id={"plan-offer-#{offer.unit_id}"}
          class="glass-inset rounded-lg px-4 py-3 border border-warning/30 flex items-center gap-3"
        >
          <.icon name="hero-archive-box-mini" class="size-4 text-warning flex-shrink-0" />
          <span class="min-w-0 flex-1 text-sm text-warning/90">
            No right-sized release for {offer.unit_label} — only a {offer.scope_label}<span :if={
              offer.size_bytes
            }>, {format_size(offer.size_bytes)}</span>, which brings episodes you didn't ask for.
          </span>
          <.button
            variant="risky"
            size="xs"
            class="flex-shrink-0"
            phx-click="plan_choose_release"
            phx-value-unit-id={offer.unit_id}
            phx-value-guid={offer.guid}
            title={offer.title}
            data-nav-item
            tabindex="0"
          >
            Grab the pack
          </.button>
        </div>

        <div
          :for={below <- @board.below_floor}
          :if={@board.status == :ready}
          id={"plan-below-floor-#{below.unit_id}"}
          class="space-y-2"
        >
          <div class="glass-inset rounded-lg px-4 py-3 border border-info/30 flex items-center gap-3">
            <.icon name="hero-arrow-trending-down-mini" class="size-4 text-info flex-shrink-0" />
            <span class="min-w-0 flex-1 text-sm">
              <span class="text-base-content/90">
                Nothing matching your quality preference<span :if={!@board.movie?}> for {below.unit_label}</span>
              </span>
              <span class="block text-xs text-base-content/50 mt-1">
                {below.count} lower-quality {if below.count == 1, do: "release", else: "releases"} available.
                Grabbing one takes it for this title without changing your preference.
              </span>
            </span>
            <.button
              variant="neutral"
              size="xs"
              class="flex-shrink-0"
              phx-click={
                if @alternatives && @alternatives.unit_id == below.unit_id,
                  do: "plan_hide_alternatives",
                  else: "plan_show_alternatives"
              }
              phx-value-unit-id={below.unit_id}
              data-nav-item
              tabindex="0"
            >
              {if @alternatives && @alternatives.unit_id == below.unit_id,
                do: "Hide",
                else: "Show them"}
            </.button>
          </div>

          <.alternatives_panel
            :if={@alternatives && @alternatives.unit_id == below.unit_id}
            alternatives={@alternatives}
          />
        </div>

        <div :if={@board.status == :ready && @board.gaps != [] && @gap_verdict} class="space-y-2">
          <%!-- The adaptive diagnosis verdict (UIDR-022): the headline
                states the world the counts prove; the muted line beneath
                carries the receipts (queries, freshness). --%>
          <div class="glass-inset rounded-lg px-4 py-3 border border-warning/30 flex items-center gap-3">
            <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning flex-shrink-0" />
            <span class="min-w-0 flex-1 text-sm">
              <span class="block text-warning/90">{@gap_verdict.headline}</span>
              <span :if={@gap_verdict.evidence_line} class="block text-xs text-base-content/50 mt-1">
                {@gap_verdict.evidence_line}
              </span>
            </span>
            <.button
              :if={@gap_verdict.show_rejected?}
              variant="neutral"
              size="xs"
              class="flex-shrink-0"
              phx-click={if @rejected, do: "plan_hide_rejected", else: "plan_show_rejected"}
              data-nav-item
              tabindex="0"
            >
              {if @rejected, do: "Hide", else: "Show them anyway"}
            </.button>
            <.button
              variant="neutral"
              size="xs"
              class="flex-shrink-0"
              phx-click="plan_track_gaps"
              title="Keep watching for these — opens gap wants on the title's tracking entry"
              data-nav-item
              tabindex="0"
            >
              Track these later
            </.button>
            <.button
              variant="neutral"
              size="xs"
              class="flex-shrink-0"
              phx-click="plan_search_again"
              data-nav-item
              tabindex="0"
            >
              Search again
            </.button>
          </div>

          <.alternatives_panel
            :if={@rejected}
            alternatives={%{unit_id: @rejected.unit_id, items: @rejected.items}}
            variant={:rejected}
          />
        </div>

        <p :if={@board.error} class="text-xs text-error/80">{@board.error}</p>
        <p :if={@last_activity} class="text-sm text-base-content/40">{@last_activity}</p>
      </div>

      <div class="border-t border-base-content/10 px-6 py-4 flex items-center justify-between gap-4">
        <span class="text-sm text-base-content/50 tabular-nums">
          {@board.covered} of {@board.wanted} covered · {length(@board.releases)}
          {if length(@board.releases) == 1, do: "release", else: "releases"}
          <span :if={@board.total_size_bytes}>· ≈ {format_size(@board.total_size_bytes)}</span>
        </span>
        <div class="flex items-center gap-2">
          <.button
            :if={@board.status in [:planning, :ready]}
            variant="dismiss"
            size="sm"
            phx-click="plan_discard_prompt"
            data-nav-item
            tabindex="0"
          >
            Discard
          </.button>
          <.button
            :if={@board.status == :ready && @board.releases != []}
            variant="primary"
            size="sm"
            phx-click="plan_approve"
            aria-disabled={to_string(@approving)}
            class={@approving && "opacity-70"}
            data-nav-item
            tabindex="0"
          >
            <%!-- The release count and total size sit in the footer summary
                  to the left; the button names the act, not the tally. --%>
            <span :if={@approving} class="loading loading-spinner loading-xs"></span>
            {if @approving, do: "Approving…", else: "Approve plan"}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :alternatives, :map,
    required: true,
    doc: "%{unit_id, items, searching?} — typed at the public attr."

  attr :release, PlanBoard.Release,
    default: nil,
    doc:
      "the currently assigned release when the picker opens from a release row (enables the exclude-and-re-solve verb); nil when it opens from a below-floor offer, which has no current assignment."

  attr :variant, :atom,
    default: :alternatives,
    values: [:alternatives, :rejected],
    doc:
      ":alternatives is the swap picker (identity-verified candidates); :rejected is the gap banner's " <>
        "escape hatch (UIDR-022) — same panel, but choosing routes through the identity override and " <>
        "the corpus-refresh verb doesn't apply."

  defp alternatives_panel(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg px-4 py-3 ml-4 space-y-1 border border-base-content/10">
      <p :if={@alternatives.items == []} class="text-xs text-base-content/40 py-1">
        Nothing else in the corpus yet — Find more runs this span's searches.
      </p>

      <div
        :for={alternative <- @alternatives.items}
        id={"plan-alternative-#{@alternatives.unit_id}-#{:erlang.phash2(alternative.guid)}"}
        class="flex items-center gap-3 py-1.5"
      >
        <ReleaseFacts.release_facts entry={alternative_entry(alternative)} />
        <span :if={alternative.reason} class="flex-shrink-0 text-xs text-base-content/40">
          {alternative.reason}
        </span>
        <.button
          variant="neutral"
          size="xs"
          class="flex-shrink-0"
          phx-click={
            if @variant == :rejected, do: "plan_choose_rejected", else: "plan_choose_release"
          }
          phx-value-unit-id={@alternatives.unit_id}
          phx-value-guid={alternative.guid}
          data-nav-item
          tabindex="0"
        >
          Choose
        </.button>
      </div>

      <div class="flex items-center justify-end gap-2 pt-2 border-t border-base-content/5">
        <.button
          :if={@variant == :alternatives}
          variant="neutral"
          size="xs"
          phx-click="plan_find_more_alternatives"
          phx-value-unit-id={@alternatives.unit_id}
          disabled={@alternatives[:searching?] == true}
          title="Search the indexers for more options for this span"
          data-nav-item
          tabindex="0"
        >
          <span :if={@alternatives[:searching?]} class="loading loading-spinner loading-xs"></span>
          {if @alternatives[:searching?], do: "Searching…", else: "Find more"}
        </.button>
        <.button
          :if={@release}
          variant="dismiss"
          size="xs"
          phx-click="plan_swap_release"
          phx-value-unit-id={@alternatives.unit_id}
          phx-value-guid={@release.guid}
          title="Exclude this release everywhere and let the planner re-solve"
          data-nav-item
          tabindex="0"
        >
          Exclude this release — re-solve
        </.button>
        <.button variant="dismiss" size="xs" phx-click="plan_search_again" data-nav-item tabindex="0">
          Search again
        </.button>
      </div>
    </div>
    """
  end

  attr :cell, PlanBoard.Cell, required: true
  attr :in_capsule, :boolean, default: false

  defp board_cell(assigns) do
    ~H"""
    <span
      id={"plan-cell-#{@cell.plan_unit_id}"}
      title={cell_title(@cell)}
      class={[
        "w-9 h-9 rounded-md flex items-center justify-center text-[13px] tabular-nums select-none",
        @cell.state |> CellVocabulary.from_plan_state(@in_capsule) |> CellVocabulary.cell_treatment()
      ]}
    >
      {@cell.episode_number}
    </span>
    """
  end

  # ---------------------------------------------------------------------------

  defp cell_title(%PlanBoard.Cell{release_title: title} = cell) when is_binary(title),
    do: "#{cell.label} — #{title}"

  defp cell_title(%PlanBoard.Cell{state: :searching} = cell), do: "#{cell.label} — searching"
  defp cell_title(%PlanBoard.Cell{state: :unfound} = cell), do: "#{cell.label} — not available"
  defp cell_title(%PlanBoard.Cell{} = cell), do: cell.label

  defp selection_meta(%Targeting.Selection{} = selection) do
    aired = selection.seasons |> Enum.flat_map(& &1.episodes) |> Enum.count(& &1.aired?)
    owned = selection.seasons |> Enum.flat_map(& &1.episodes) |> Enum.count(& &1.in_library?)

    base = "#{aired} aired"
    if owned > 0, do: "#{base} · #{owned} already in your library", else: base
  end

  defp season_meta(%Targeting.Season{episodes: episodes}) do
    aired = Enum.count(episodes, & &1.aired?)

    if aired == 0 do
      "not yet aired"
    else
      "#{aired} aired"
    end
  end

  defp release_entry(%PlanBoard.Release{} = release) do
    %ReleaseFacts.Entry{
      title: release.title,
      scope_label: release.scope_label,
      quality: release.quality,
      size_bytes: release.size_bytes,
      seeders: release.seeders
    }
  end

  defp alternative_entry(%PlanBoard.Alternative{} = alternative) do
    %ReleaseFacts.Entry{
      title: alternative.title,
      scope_label: alternative.scope_label,
      quality: alternative.quality,
      size_bytes: alternative.size_bytes,
      seeders: alternative.seeders,
      suspicious?: alternative.suspicious?
    }
  end

  defp descent_dot(:active), do: "bg-info animate-pulse"
  defp descent_dot(:done), do: "bg-success/70"
  defp descent_dot(_pending_or_skipped), do: "bg-base-content/20"
end
