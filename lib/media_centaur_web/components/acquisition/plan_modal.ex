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

  Stages, driven by the host's `?plan=` param (`Live.PlanHost`, on every
  page that opens a title — the modal is a tenant of the page that opened
  it, never a trip to Downloads):

  * `:loading` — the targeting universe is being fetched.
  * `:targeting` — the series picker: quick-action presets, tri-state
    season rows, episode drill-in; in-library rows greyed (shown,
    never hidden), unaired rows inert.
  * `:movie_confirm` — the movie fast path: one card, two clicks.
  * `:board` — the manifest over the durable draft plan (UIDR-029 as
    amended 2026-11-06): the verdict in the pinned block, then one list
    of lines (`PlanLine`) — each release with the episode cells it
    covers, then the outcomes (searching, lower quality only, not
    found, a pack offer, dropped by you) each with its cells and its
    decision at the line's end — then the receipts (*How we searched*,
    always shown), and the acts in the frame's foot. Refresh-safe by
    construction. An *empty* board — ready, nothing found — carries
    the bookmark in the footer's primary slot instead of Approve (spec
    2026-09-14): *Add to watchlist*, or the *On your watchlist* marker
    once the subject is listed, because the remedy for a title that is
    not out yet is the watchlist (UIDR-039). The button pushes the
    host's `set_rung` with the subject's ref, as the title view's
    bookmark does; the calendar the verdict speaks comes from
    `TMDB.ReleaseWindow` through `gap_verdict`.
  * `:error` — targeting failed (TMDB unreachable etc.).

  The targeting and movie-confirm feet carry the Download split
  (`GlassMenu.split_button`, the title detail's control): the main
  segment performs `mode` — the mode the picker was opened with — and
  the menu names the other, sending it as the create event's `mode`
  (spec 2026-09-23 follow-up). The host owns the menu's open state
  (`menu_open`, events `plan_mode_toggle` / `plan_menu_close`).

  Keyboard/gamepad navigation: the modal is a `plan` overlay with four
  regions (`config.overlays.plan`). The board is a `plan_head` TREE
  (the verdict's Undo) over the `plan_lines` TREE (each line an item,
  its controls and then its cells sub-items; the open picker's rows
  beneath their line) over the `plan_foot` TOOLBAR — the frame's foot,
  carrying the acts (Stop searching, Discard, Approve, the watchlist
  slot). Targeting and movie confirm put their controls in `plan_body`
  and Cancel + the Download split in `plan_foot`; the split's open menu
  is a `plan_menu` TREE nested in the foot, the overlay's one `back`
  edge, so BACK closes the list before it dismisses the modal. The
  error stage's one Close is in `plan_body`. A cell's tip is its
  episode label through the app tooltip.

  Pure rendering; the host owns all state and events.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [format_size: 1]

  alias MediaCentaurWeb.Live.DisclosureState
  alias MediaCentaurWeb.Components.Acquisition.PlanLine
  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.Components.Detail.PreviewBody
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Checkbox
  alias MediaCentaurWeb.Components.GlassMenu
  alias MediaCentaurWeb.DownloadsLive.PlanLogic
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Logic, as: TitleLogic
  alias MediaCentaurWeb.Components.Title.WatchlistToggle
  alias MediaCentaurWeb.TitleRef

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
      "%TMDB.Title{} | nil — the picked search result, dressing the " <>
        ":loading stage the instant the modal opens."

  attr :selection, :any,
    default: nil,
    doc: "%Targeting.Selection{} | nil — the picker's universe (targeting stage)."

  attr :chosen, :any,
    default: nil,
    doc: "MapSet of {season, episode} — the picker's chosen units (targeting stage)."

  attr :movie, :any,
    default: nil,
    doc:
      "%MediaCentaurWeb.Components.Detail.TitlePreview{} | nil — the movie fast path's detail-shaped preview (built by PlanLogic.movie_preview/2)."

  attr :board, :any,
    default: nil,
    doc: "%PlanBoard{} | nil — the live coverage board (board stage)."

  attr :error, :string, default: nil, doc: "Targeting-stage failure copy (error stage)."

  attr :last_activity, :string,
    default: nil,
    doc: "Latest PlanEvents.SearchActivity line for the board's ticker, or nil."

  attr :search_progress, :any,
    default: nil,
    doc:
      "%SearchProgressPanel.View{} | nil — the board's expectation rows (TV plans); the headline is `gap_verdict`'s searching world."

  attr :disclosures, :any,
    default: MapSet.new(),
    doc: "the page's `DisclosureState` — the picker's season rows."

  attr :alternatives, :any,
    default: nil,
    doc:
      "%{unit_id, items: [PlanBoard.Alternative.t()], searching?: boolean} | nil — the open swap picker (board stage)."

  attr :search_health, :any,
    default: nil,
    doc:
      "`MediaCentaur.Search.IndexerHealth.t()` | nil — when `blind?/1`, the gap banner says availability couldn't be checked instead of claiming unavailability (UIDR-016)."

  attr :gap_verdict, :any,
    default: nil,
    doc:
      "`ViewModels.GapVerdict.t()` | nil — the board's one verdict: the searching world while planning, the gap banner's adaptive diagnosis (UIDR-022) once ready; nil for a ready board with no gaps."

  attr :rejected, :any,
    default: nil,
    doc:
      "%{unit_id, items: [PlanBoard.Alternative.t()]} | nil — the open rejected-results panel (UIDR-022, movie boards only)."

  attr :discard_armed, :boolean,
    default: false,
    doc: "host-owned: Discard's first click has landed (MC0027 tier 2 — no overlay)."

  attr :subject, Title,
    default: nil,
    doc:
      "the plan's title as the app-wide TMDB title value — what an empty board's bookmark " <>
        "lists (`Title.ref/1` is its `phx-value-ref`). Nil hides the control."

  attr :rung, :atom,
    values: [nil, :ignored, :list, :follow, :grab],
    default: nil,
    doc: "the subject's rung; nil is Off. At List and above the footer shows the marker."

  attr :mode, :atom,
    values: [nil | PlanningMode.modes()],
    default: nil,
    doc:
      "the planning mode the Download split's main segment performs (targeting and movie-confirm " <>
        "stages); its menu names the other. Nil on the other stages."

  attr :menu_open, :boolean, default: false, doc: "host-owned: the Download split's menu is open."

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
      data-nav-overlay={@open && "plan"}
      data-dismiss-event={@on_close}
    >
      <:orientation>
        <div :if={@lockup} class="px-6 pb-5 space-y-4">
          <TitleLayer.lockup
            title={@lockup.title}
            logo_url={@lockup.logo_url}
            tagline={@lockup.tagline}
          />
          <%!-- The board's one verdict, in the block that pins: the
                sentence over the lines stays in view however far the
                manifest scrolls (UIDR-029 as amended 2026-11-06). --%>
          <.board_verdict :if={@stage == :board && @board} board={@board} gap_verdict={@gap_verdict} />
        </div>
      </:orientation>
      <:body>
        <.loading_stage :if={@stage == :loading} />

        <div
          :if={@stage == :error}
          data-nav-zone="plan_body"
          class="p-8 text-center text-sm space-y-3"
        >
          <p class="text-error">{@error || "Couldn't load this title from TMDB."}</p>
          <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
            Close
          </.button>
        </div>

        <.targeting_stage
          :if={@stage == :targeting && @selection}
          selection={@selection}
          chosen={@chosen || MapSet.new()}
          disclosures={@disclosures}
        />

        <.movie_stage :if={@stage == :movie_confirm && @movie} movie={@movie} />

        <.board_stage
          :if={@stage == :board && @board}
          board={@board}
          alternatives={@alternatives}
          last_activity={@last_activity}
          search_progress={@search_progress}
          gap_verdict={@gap_verdict}
          rejected={@rejected}
        />
      </:body>
      <%!-- The acts live in the frame's foot (campaign plan-modal, M2): a
            band at the panel's bottom edge, outside the scroll, so Cancel,
            Download and Approve stay in reach however long the body is.
            The error stage keeps its one Close in the body; loading has
            no controls. --%>
      <:foot :if={@stage in [:targeting, :movie_confirm, :board]}>
        <.targeting_foot
          :if={@stage == :targeting && @selection}
          chosen_count={MapSet.size(@chosen || MapSet.new())}
          mode={@mode}
          menu_open={@menu_open}
          on_close={@on_close}
        />
        <.movie_foot
          :if={@stage == :movie_confirm && @movie}
          movie={@movie}
          mode={@mode}
          menu_open={@menu_open}
          on_close={@on_close}
        />
        <.board_foot
          :if={@stage == :board && @board}
          board={@board}
          discard_armed={@discard_armed}
          subject={@subject}
          rung={@rung}
        />
      </:foot>
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
    <div class="p-6 flex items-center gap-2 text-sm text-base-content/55">
      <span class="loading loading-spinner loading-xs"></span> Loading from TMDB…
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Targeting stage
  # ---------------------------------------------------------------------------

  attr :selection, Targeting.Selection, required: true
  attr :chosen, :any, required: true, doc: "MapSet — typed at the public attr."
  attr :disclosures, :any, required: true, doc: "the page's `DisclosureState`."

  defp targeting_stage(assigns) do
    assigns = assign(assigns, :chosen_count, MapSet.size(assigns.chosen))

    ~H"""
    <div data-nav-zone="plan_body" class="p-6 pb-6 space-y-5">
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
          phx-value-preset="clear"
          data-nav-item
          tabindex="0"
        >
          Clear selected
        </.button>
        <span class="ml-auto text-sm text-base-content/55 tabular-nums">
          {@chosen_count} selected
        </span>
      </div>

      <div class="space-y-2">
        <.season_row
          :for={season <- @selection.seasons}
          season={season}
          selection={@selection}
          chosen={@chosen}
          disclosures={@disclosures}
        />
      </div>
    </div>
    """
  end

  # The picker's foot: Cancel and the Download split, in the frame's foot
  # (`plan_foot`), so the act stays in reach however long the season list.
  attr :chosen_count, :integer, required: true
  attr :mode, :atom, required: true
  attr :menu_open, :boolean, required: true
  attr :on_close, :string, required: true

  defp targeting_foot(assigns) do
    ~H"""
    <div data-nav-zone="plan_foot" class="px-6 py-4 flex items-center justify-end gap-2">
      <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
        Cancel
      </.button>
      <.download_split mode={@mode} menu_open={@menu_open} inert={@chosen_count == 0}>
        Download {@chosen_count} {if @chosen_count == 1, do: "episode", else: "episodes"}
      </.download_split>
    </div>
    """
  end

  # The one Download control of both feet: the title detail's split,
  # opening upward from the foot's end, over the body, so the list stays
  # inside the panel. Inert (aria-disabled, dimmed) rather than disabled
  # while there is nothing to download, so the nav graph never shifts.
  attr :mode, :atom, required: true, doc: "what the main segment performs; the menu names the other"
  attr :menu_open, :boolean, required: true
  attr :inert, :boolean, required: true, doc: "nothing to download yet"
  slot :inner_block, required: true, doc: "the main segment's label"

  defp download_split(assigns) do
    assigns = assign(assigns, :other_mode, PlanningMode.other(assigns.mode))

    ~H"""
    <GlassMenu.split_button
      id="plan-download"
      open={@menu_open}
      on_toggle="plan_mode_toggle"
      on_close="plan_menu_close"
      menu_zone="plan_menu"
      menu_label="More download options"
      placement="above"
      align="end"
      class={@inert && "opacity-50"}
      phx-click="plan_create"
      aria-disabled={to_string(@inert)}
    >
      {render_slot(@inner_block)}
      <:item
        id="plan-download-other"
        event="plan_create"
        values={%{"mode" => Atom.to_string(@other_mode)}}
      >
        {TitleLogic.planning_mode_label(@other_mode)}
      </:item>
    </GlassMenu.split_button>
    """
  end

  attr :season, Targeting.Season, required: true
  attr :selection, Targeting.Selection, required: true
  attr :chosen, :any, required: true, doc: "MapSet — typed at the public attr."
  attr :disclosures, :any, required: true, doc: "the page's `DisclosureState`."

  defp season_row(assigns) do
    id = "plan-season-#{assigns.selection.tmdb_id}-#{assigns.season.season_number}"
    state = PlanLogic.season_state(assigns.chosen, assigns.selection, assigns.season)

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(:id, id)
      |> assign(:open, DisclosureState.open?(assigns.disclosures, id))

    ~H"""
    <%!-- A season with nothing left to choose (every aired episode owned)
          never opens: it renders as a plain row — no caret, no pointer,
          not a nav item — the same inert line for mouse and cursor. --%>
    <div
      :if={@state == :disabled}
      id={@id}
      class="glass-inset rounded-lg opacity-50 flex items-center gap-3 px-4 py-2.5"
    >
      <Checkbox.checkbox state={:disabled} />
      <span class="text-sm font-medium">Season {@season.season_number}</span>
      <span class="text-sm text-base-content/55">{season_meta(@season)}</span>
    </div>
    <.disclosure
      :if={@state != :disabled}
      id={@id}
      open={@open}
      variant={:bare}
      class="glass-inset rounded-lg"
      row_class="flex items-center gap-3 px-4 py-2.5"
      head_class="flex flex-1 min-w-0 items-center gap-3 text-left"
      body_class="border-t border-base-content/5"
    >
      <:leading>
        <Checkbox.checkbox
          state={@state}
          phx-click="plan_toggle_season"
          phx-value-season={@season.season_number}
        />
      </:leading>
      <:head>
        <span class="text-sm font-medium">Season {@season.season_number}</span>
        <span class="text-sm text-base-content/55">{season_meta(@season)}</span>
      </:head>
      <ul>
        <li
          :for={episode <- @season.episodes}
          id={"plan-episode-#{episode.season_number}-#{episode.episode_number}"}
          class={[
            "flex items-baseline gap-3 pl-10 pr-4 py-2 pointer-coarse:py-3.5",
            (!episode.aired? || episode.in_library?) && "opacity-40"
          ]}
        >
          <Checkbox.checkbox
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
          <span :if={episode.in_library?} class="flex-shrink-0 text-xs text-base-content/55">
            In library
          </span>
          <span
            :if={episode.tracked? && !episode.in_library?}
            class="flex-shrink-0 text-xs text-info/70"
            data-tip="Release tracking is already watching for this — check it to grab it in this plan instead"
          >
            Tracked
          </span>
          <span :if={!episode.aired?} class="flex-shrink-0 text-xs text-base-content/55">
            Unaired
          </span>
          <span
            :if={episode.aired? && !episode.in_library? && episode.air_date}
            class="flex-shrink-0 text-xs text-base-content/55 tabular-nums"
          >
            {episode.air_date}
          </span>
        </li>
      </ul>
    </.disclosure>
    """
  end

  # ---------------------------------------------------------------------------
  # Movie stage
  # ---------------------------------------------------------------------------

  attr :movie, TitlePreview,
    required: true,
    doc: "detail-shaped preview built by `TitlePreview.movie/3` in the host's targeting task."

  defp movie_stage(assigns) do
    # The identity (logo/title/tagline) lives in the frame's pinned
    # lockup; the hero imagery is the frame's backdrop (the host feeds
    # it backdrop-or-poster via PlanLogic.shell_backdrop_url). This
    # stage is the facts below.
    ~H"""
    <div data-nav-zone="plan_body" class="px-6 pt-6 pb-6">
      <PreviewBody.preview_body preview={@movie} library_state />
    </div>
    """
  end

  attr :movie, TitlePreview, required: true
  attr :mode, :atom, required: true
  attr :menu_open, :boolean, required: true
  attr :on_close, :string, required: true

  defp movie_foot(assigns) do
    ~H"""
    <div data-nav-zone="plan_foot" class="px-6 py-4 flex items-center justify-end gap-2">
      <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
        Cancel
      </.button>
      <.download_split mode={@mode} menu_open={@menu_open} inert={@movie.in_library?}>
        Download
      </.download_split>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Board stage
  # ---------------------------------------------------------------------------

  attr :board, PlanBoard, required: true
  attr :gap_verdict, :any, required: true, doc: "GapVerdict.t() | nil — typed at the public attr."

  # The verdict slot, seated in the pinned orientation block: one
  # sentence for every state the board can be in (`PlanLogic.verdict/2`),
  # its evidence line, and the accepted-lower-quality line with Undo. The
  # `plan_head` region's only control is Undo.
  defp board_verdict(assigns) do
    assigns = assign(assigns, :verdict, PlanLogic.verdict(assigns.board, assigns.gap_verdict))

    ~H"""
    <div data-nav-zone="plan_head" class="space-y-1">
      <p
        id="plan-verdict"
        class={[
          "text-lg leading-snug text-on-image",
          @verdict.tone == :warning && "text-warning/90",
          @verdict.tone == :success && "text-success",
          is_nil(@verdict.tone) && "text-base-content/90"
        ]}
      >
        <span :if={@verdict.planning?} class="loading loading-spinner loading-sm align-middle mr-2"></span>
        {@verdict.headline}
      </p>
      <p :if={@verdict.evidence_line} class="text-xs text-base-content/55 text-on-image">
        {@verdict.evidence_line}
      </p>
      <p
        :if={@board.lower_quality_accepted?}
        id="plan-lower-quality-accepted"
        class="text-xs text-base-content/55 text-on-image"
      >
        Lower quality accepted for this show — it keeps using the best release there is.
        <.button
          variant="dismiss"
          size="xs"
          phx-click="plan_undo_lower_quality"
          data-nav-item
          tabindex="0"
        >
          Undo
        </.button>
      </p>
    </div>
    """
  end

  attr :board, PlanBoard, required: true

  attr :alternatives, :any,
    required: true,
    doc:
      "%{unit_id, items: [PlanBoard.Alternative.t()], searching?: boolean} | nil — the open swap picker (board stage)."

  attr :last_activity, :string, required: true

  attr :search_progress, :any,
    required: true,
    doc: "%SearchProgressPanel.View{} | nil — typed at the public attr."

  attr :gap_verdict, :any,
    required: true,
    doc: "GapVerdict.t() | nil — typed at the public attr."

  attr :rejected, :any,
    required: true,
    doc: "%{unit_id, items} | nil — typed at the public attr."

  # The manifest (UIDR-029 as amended 2026-11-06): the lines, each with
  # the picker that opens under it when it is that line's; then the
  # receipts — while planning the latest search over the live step rows,
  # once ready the step rows alone, always shown. The verdict is in the
  # pinned block above; the acts are in the frame's foot below.
  defp board_stage(assigns) do
    assigns =
      assign(assigns,
        rejectable?: match?(%{show_rejected?: true}, assigns.gap_verdict),
        movie_gap_unit_id: PlanBoard.movie_gap_unit_id(assigns.board)
      )

    ~H"""
    <div data-nav-zone="plan_lines" class="px-6 pt-2 pb-6 space-y-6">
      <div class="space-y-2">
        <%= for line <- @board.lines do %>
          <PlanLine.plan_line
            line={line}
            ready?={@board.status == :ready}
            movie?={@board.movie?}
            picker_open={picker_open?(line, @alternatives, @rejected)}
            rejectable?={line.kind == :not_found && @rejectable?}
          />
          <.alternatives_panel
            :if={
              line.kind == :release && @alternatives &&
                @alternatives.unit_id == line.release.swap_unit_id
            }
            alternatives={@alternatives}
            release={line.release}
          />
          <.alternatives_panel
            :if={
              line.kind == :below_preference && @alternatives && line.below.unit_id &&
                @alternatives.unit_id == line.below.unit_id
            }
            alternatives={@alternatives}
          />
          <.alternatives_panel
            :if={line.kind == :not_found && @rejected}
            alternatives={%{unit_id: @rejected.unit_id, items: @rejected.items}}
            variant={:rejected}
          />
        <% end %>
      </div>

      <p :if={@board.error} class="text-xs text-error/80">{@board.error}</p>

      <div
        :if={@search_progress || (@board.status == :planning && @last_activity)}
        class="space-y-2"
      >
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          How we searched
        </h3>
        <p :if={@board.status == :planning && @last_activity} class="text-sm text-base-content/55">
          {@last_activity}
        </p>
        <.search_progress_rows :if={@search_progress} search_progress={@search_progress} />
      </div>
    </div>
    """
  end

  # Whether the picker under this line is open: the swap picker for a
  # release or the one below-preference unit, the rejected list for a
  # movie's not-found line.
  defp picker_open?(%PlanBoard.Line{kind: :release, release: release}, alternatives, _rejected),
    do: alternatives != nil and alternatives.unit_id == release.swap_unit_id

  defp picker_open?(%PlanBoard.Line{kind: :below_preference, below: below}, alternatives, _rejected),
    do: alternatives != nil and below.unit_id != nil and alternatives.unit_id == below.unit_id

  defp picker_open?(%PlanBoard.Line{kind: :not_found}, _alternatives, rejected), do: rejected != nil
  defp picker_open?(%PlanBoard.Line{}, _alternatives, _rejected), do: false

  # The board's foot: the summary and the acts — Stop searching while
  # planning; Discard (armed) and Approve, or the watchlist slot on an
  # empty board, once ready — in the frame's foot (`plan_foot`).
  attr :board, PlanBoard, required: true
  attr :discard_armed, :boolean, required: true
  attr :subject, :any, required: true, doc: "Title.t() | nil — typed at the public attr."
  attr :rung, :atom, required: true

  defp board_foot(assigns) do
    assigns =
      assign(assigns,
        releases: PlanBoard.releases(assigns.board),
        total_size_bytes: PlanBoard.total_size_bytes(assigns.board)
      )

    ~H"""
    <div data-nav-zone="plan_foot" class="px-6 py-4 flex items-center justify-between gap-4">
      <span class="text-sm text-base-content/55 tabular-nums">
        {@board.covered} of {@board.wanted} covered · {length(@releases)}
        {if length(@releases) == 1, do: "release", else: "releases"}
        <span :if={@total_size_bytes}>· ≈ {format_size(@total_size_bytes)}</span>
      </span>
      <div class="flex items-center gap-2">
        <.button
          :if={@board.status == :planning}
          variant="dismiss"
          size="sm"
          phx-click="plan_stop_searching"
          data-tip="Stop now and keep what's been found so far — nothing is grabbed"
          data-nav-item
          tabindex="0"
        >
          Stop searching
        </.button>
        <%!-- Discarding loses the draft and the release choices, and
               nothing has been grabbed — costly but recoverable, so the
               house arm gesture rather than an overlay (MC0027 tier 2).
               A confirmation modal here also had to out-stack the modal
               it belonged to, which is a problem it need not have. --%>
        <.armed_button
          :if={@board.status == :ready}
          armed={@discard_armed}
          event="plan_discard"
          armed_label="Press again to discard"
          variant="dismiss"
          size="sm"
        >
          Discard
        </.armed_button>
        <.button
          :if={@board.status == :ready && @releases != []}
          variant="primary"
          size="sm"
          phx-click="plan_approve"
          data-nav-item
          tabindex="0"
        >
          <%!-- The release count and total size sit in the footer summary
                to the left; the button names the act, not the tally. --%>
          Approve plan
        </.button>
        <.watchlist_slot
          :if={@subject && PlanBoard.empty?(@board)}
          subject={@subject}
          rung={@rung}
        />
      </div>
    </div>
    """
  end

  # The empty board's remedy, in the footer's primary slot: the bookmark
  # in its labelled form (UIDR-039 — the same glyph the title view and
  # the Feed wear), or the marker once the subject is listed. One event,
  # the host's `set_rung`, the same write the title view's bookmark makes.
  attr :subject, Title, required: true
  attr :rung, :atom, required: true, doc: "nil | TitleIntent.rung() — typed at the public attr."

  defp watchlist_slot(assigns) do
    assigns =
      assign(assigns,
        listed?: WatchlistToggle.listed?(assigns.rung),
        ref: TitleRef.param(Title.ref(assigns.subject))
      )

    ~H"""
    <span
      :if={@listed?}
      id="plan-on-watchlist"
      class="inline-flex items-center gap-1.5 px-3 text-sm text-primary/80"
    >
      <.icon name="hero-bookmark-solid" class="size-4" /> On your watchlist
    </span>
    <.button
      :if={!@listed?}
      id="plan-add-to-watchlist"
      variant="secondary"
      size="sm"
      phx-click="set_rung"
      phx-value-choice="list"
      phx-value-ref={@ref}
      data-nav-item
      tabindex="0"
    >
      <.icon name="hero-bookmark" class="size-4" /> Add to watchlist
    </.button>
    """
  end

  attr :alternatives, :map,
    required: true,
    doc: "%{unit_id, items, searching?} — typed at the public attr."

  attr :release, PlanBoard.Release,
    default: nil,
    doc:
      "the currently assigned release when the picker opens from a release row — rendered as the " <>
        "pre-selected anchor row; nil when it opens from a below-floor offer or the rejected list, " <>
        "which have no current assignment."

  attr :variant, :atom,
    default: :alternatives,
    values: [:alternatives, :rejected],
    doc:
      ":alternatives is the swap picker (identity-verified candidates); :rejected is the gap banner's " <>
        "escape hatch (UIDR-022) — same panel, but choosing routes through the identity override and " <>
        "the corpus-refresh verb doesn't apply."

  # A single-select picker: the current assignment (when there is one)
  # leads the list with its radio filled; picking another radio swaps
  # immediately — the re-solve is the confirmation, so there is no
  # staged apply step. Per-unit verbs only: exclude lives on the release
  # row's ✕, Search again at board level.
  defp alternatives_panel(assigns) do
    ~H"""
    <div
      id={"plan-alternatives-panel-#{@alternatives.unit_id}"}
      class="glass-inset rounded-lg px-4 py-3 ml-4 space-y-1 border border-base-content/10"
    >
      <div class="flex items-center justify-between gap-3 pb-1">
        <h4 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          Choose a release
        </h4>
        <.button
          id={if @variant == :rejected, do: "plan-rejected-close", else: "plan-alternatives-close"}
          variant="dismiss"
          size="xs"
          shape="square"
          phx-click={
            if @variant == :rejected, do: "plan_hide_rejected", else: "plan_hide_alternatives"
          }
          data-tip="Close"
          aria-label="Close"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </.button>
      </div>

      <div :if={@release} id="plan-alternatives-current" class="flex items-center gap-3 py-1.5">
        <input
          type="radio"
          name={"plan-alternatives-#{@alternatives.unit_id}"}
          class="radio radio-xs radio-primary flex-shrink-0"
          checked
          aria-disabled="true"
        />
        <ReleaseFacts.release_facts entry={release_entry(@release)} />
        <span class="flex-shrink-0 text-xs text-base-content/55">Current</span>
      </div>

      <p :if={@alternatives.items == []} class="text-xs text-base-content/55 py-1">
        Nothing else known yet — Find more runs this span's searches.
      </p>

      <div
        :for={alternative <- @alternatives.items}
        id={"plan-alternative-#{@alternatives.unit_id}-#{:erlang.phash2(alternative.guid)}"}
        class="flex items-center gap-3 py-1.5"
      >
        <input
          type="radio"
          name={"plan-alternatives-#{@alternatives.unit_id}"}
          class="radio radio-xs radio-primary flex-shrink-0 cursor-pointer"
          phx-click={
            if @variant == :rejected, do: "plan_choose_rejected", else: "plan_choose_release"
          }
          phx-value-unit-id={@alternatives.unit_id}
          phx-value-guid={alternative.guid}
          data-tip="Choose this release"
          data-nav-item
          tabindex="0"
        />
        <ReleaseFacts.release_facts entry={alternative_entry(alternative)} />
        <span :if={alternative.reason} class="flex-shrink-0 text-xs text-base-content/55">
          {alternative.reason}
        </span>
      </div>

      <div
        :if={@variant == :alternatives}
        class="flex items-center justify-end gap-2 pt-2 border-t border-base-content/5"
      >
        <.button
          variant="neutral"
          size="xs"
          phx-click="plan_find_more_alternatives"
          phx-value-unit-id={@alternatives.unit_id}
          disabled={@alternatives[:searching?] == true}
          data-tip="Search the indexers for more options for this span"
          data-nav-item
          tabindex="0"
        >
          <span :if={@alternatives[:searching?]} class="loading loading-spinner loading-xs"></span>
          {if @alternatives[:searching?], do: "Searching…", else: "Find more"}
        </.button>
      </div>
    </div>
    """
  end

  attr :search_progress, :any,
    required: true,
    doc: "%SearchProgressPanel.View{} — typed at the public attr."

  defp search_progress_rows(assigns) do
    ~H"""
    <div :for={row <- @search_progress.rows} class="flex items-center gap-2 text-xs">
      <span class={["size-1.5 rounded-full flex-shrink-0", progress_dot(row.state)]}></span>
      <span class={[
        "w-32 flex-shrink-0 text-base-content/60",
        row.state == :skipped && "line-through text-base-content/55"
      ]}>
        {row.label}
      </span>
      <span class="min-w-0 truncate text-base-content/55">{row.detail}</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------

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

  defp progress_dot(:active), do: "bg-info animate-pulse"
  defp progress_dot(:done), do: "bg-success/70"
  defp progress_dot(_pending_or_skipped), do: "bg-base-content/20"
end
