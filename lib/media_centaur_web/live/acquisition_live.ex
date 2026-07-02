defmodule MediaCentaurWeb.AcquisitionLive do
  @moduledoc """
  Unified Downloads page at `/download`. A single column of stacked
  zones, top to bottom:

  1. **Omnibox** (`data-nav-zone="omnibox"`) — one search surface, two
     modes: TMDB media search feeding the plan flow, and Prowlarr
     release search (results render in the search zone below it).
  2. **Draft plans** (`data-nav-zone="drafts"`) — unapproved plan
     boards, resumable into the plan modal.
  3. **Active pursuits** (`data-nav-zone="pursuits"`) — every live
     pursuit, paired at render time with its torrent(s) from the
     download-client queue. Refreshes live via PubSub + queue polls.
  4. **History** (`data-nav-zone="history"`) — terminal pursuits
     (failed / cancelled / succeeded) behind a collapsed-by-default
     disclosure. Filter chips + title search.
  5. **Other downloads** (`data-nav-zone="other_downloads"`) — client
     torrents that match no tracked pursuit.

  Mounted at `/download`. Only available when Prowlarr is configured —
  unauthenticated requests redirect to the library.

  See `MediaCentaur.Search.QueryExpander` for the supported brace
  syntax, `MediaCentaurWeb.AcquisitionLive.Logic` for search/group
  helpers, and `MediaCentaurWeb.AcquisitionLive.HistoryLogic` for the
  History zone filter helpers.

  ## External-state reconciliation

  This LiveView mirrors three external sources of truth — qBittorrent's
  queue (via `QueueMonitor` polls), the in-memory `SearchSession`, and
  the `acquisition_grabs` table. Each lives behind its own PubSub
  subscription, declared in `mount/3`:

      Acquisition.subscribe()        # acquisition:updates  → grab lifecycle
      Acquisition.subscribe_queue()  # acquisition:queue    → queue snapshots
      SearchSession.subscribe() # acquisition:search   → search session

  See the matching `subscribe_*/0` functions on `MediaCentaur.Acquisition`
  for the message types each topic carries.

  ### Optimistic UI + snapshot reconciliation pattern

  Snapshots from `QueueMonitor` are **authoritative** — every poll
  overwrites `active_queue`. User actions that mutate external state
  (cancel, future pause/resume) cannot just `assign(socket, ...)` and
  walk away: the next snapshot will undo the local change while the
  external system is still propagating.

  The convention is:

  1. Apply the change optimistically to the local socket assign.
  2. Record the in-flight intent in a `pending_*` map keyed by item id
     with a monotonic timestamp.
  3. In the snapshot handler, run the snapshot through a pure helper
     (`Logic.apply_pending_cancels/3` is the canonical example) that
     filters out items whose intent is still pending and ages out
     expired entries. The grace window is short enough that a *failed*
     mutation surfaces visibly rather than ghosting forever.
  4. Trigger `Acquisition.poll_queue_now/0` so reconciliation is fast,
     not "wait for the next 5s tick".

  Adding a new mutating action against an external mirror? Repeat this
  shape — the bug class is "the snapshot blew away the optimistic
  change", and the antidote is a pending-state map + a pure filter.
  """

  use MediaCentaurWeb, :live_view

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{CancelReasons, QueueMatcher}
  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.Pursuit

  alias MediaCentaur.Acquisition.Pursuits.Commands.{
    Cancel,
    ChangeTarget,
    RequestDecision
  }

  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Acquisition.TargetEvents
  alias MediaCentaur.Acquisition.ViewModels
  alias MediaCentaur.Acquisition.ViewModels.{Alternative, DescentNarrative, PursuitWithDownload}
  alias MediaCentaur.Capabilities

  alias MediaCentaurWeb.AcquisitionLive.{
    History,
    HistoryLogic,
    Logic,
    OrphanQueue,
    Search,
    SearchSession
  }

  alias MediaCentaur.ReleaseTracking

  alias MediaCentaur.Acquisition.{PlanEvents, Plans, Targeting}
  alias MediaCentaurWeb.AcquisitionLive.PlanLogic
  alias MediaCentaurWeb.HomeLive.Logic, as: HomeLogic

  alias MediaCentaur.Settings
  alias MediaCentaur.Storage

  alias MediaCentaurWeb.Components.Acquisition.{
    ConnectivityBadge,
    DownloadStorage,
    MediaOmnibox,
    PlanModal,
    PursuitGroup,
    PursuitModal,
    PursuitRow
  }

  @decision_prompt "Pick an alternative release."

  # Storage headroom is ambient context, not a live ticker — `df` is cheap
  # but not free, and free space only moves as downloads land. Refresh on a
  # slow cadence (same interval as the Status page's storage section).
  @storage_refresh_ms 5 * 60 * 1_000

  @impl true
  def mount(_params, _session, socket) do
    # The Prowlarr-readiness gate is the only DB read on the static HTTP
    # mount path — without it we can't decide whether to render or
    # redirect. All other state (search session, download-client gate,
    # active queue) is loaded after the WebSocket connects via
    # `ensure_loaded/1`.
    if Capabilities.prowlarr_ready?() do
      if connected?(socket) do
        Acquisition.subscribe()
        Acquisition.subscribe_queue()
        SearchSession.subscribe()
      end

      {:ok,
       maybe_start_storage(
         assign(socket,
           loaded?: false,
           storage_drives: [],
           page_backdrop: page_backdrop(),
           search_session: %SearchSession{},
           active_queue: [],
           queue_connectivity: :initializing,
           queue_last_success_at: nil,
           queue_loaded?: false,
           board_expanded_seasons: nil,
           cancel_confirm: nil,
           pending_cancels: %{},
           download_client_ready: false,
           history_filter: :failed,
           history_search: "",
           history_open?: false,
           history_rows: [],
           pursuit_rows: [],
           expanded_pursuit_groups: MapSet.new(),
           pursuits_reload_timer: nil,
           reload_timer: nil,
           selected_pursuit_id: nil,
           pursuit_detail: nil,
           omnibox_mode: :media,
           omnibox_query: "",
           omnibox_results: [],
           omnibox_searching?: false,
           omnibox_searched: nil,
           plan_param: nil,
           plan_stage: :loading,
           plan_selection: nil,
           plan_chosen: MapSet.new(),
           plan_expanded_seasons: MapSet.new(),
           plan_movie: nil,
           plan_board: nil,
           plan_grab_future: false,
           plan_error: nil,
           plan_last_activity: nil,
           plan_descent: nil,
           plan_alternatives: nil,
           plan_approving?: false,
           plan_discard_confirm?: false,
           plan_drafts: []
         )
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # First-render data load — gated by `connected?` so the static HTTP
  # render ships empty defaults and the WebSocket render fills them in
  # once. See AGENTS.md → LiveView callbacks (Iron Law).
  #
  # Per the "no blocking LV page loads" rule, the four initial reads
  # (search session, capability flag, active pursuit rows, history
  # rows) run on a supervised task in parallel and message back via
  # `{:acquisition_loaded, _}`. The `Acquisition.queue_state/0` read
  # is `:persistent_term` — microsecond — and stays synchronous so the
  # page can render the queue's freshness state immediately.
  # First-render data load — runs on BOTH the disconnected (static) and
  # connected renders so the first paint already carries the search session,
  # pursuit rows, and history, never an empty-state flash. Desktop
  # first-paint correctness (see AGENTS.md → LiveView callbacks): the four
  # reads are all local, so there is no traffic-scaling reason to defer
  # them. Do not re-add a `connected?` gate.
  defp ensure_loaded(socket) do
    if socket.assigns.loaded? do
      socket
    else
      socket
      |> assign_queue_from_state(Acquisition.queue_state())
      |> load_acquisition()
      |> assign(:loaded?, true)
    end
  end

  # Synchronous first-render load of the four initial reads (search
  # session, download-client capability, active pursuit rows, history
  # rows). All local; running them inline keeps the first paint correct.
  # Ambient page backdrop — same ETS-backed hero-candidate pool the
  # home/library pages draw from, in the downloads page's own slot so
  # no backdrop repeats across pages when the pool allows.
  defp page_backdrop do
    case HomeLogic.select_page_hero(MediaCentaur.Library.Views.hero_candidates(), 2) do
      %{backdrop_url: url} when is_binary(url) -> url
      _ -> nil
    end
  end

  # Storage headroom loads off the mount path (measure_all shells out to
  # `df`, which can stall on sleeping media dirs) via owned async (ADR-049,
  # MC0019) — cancelled with the LiveView, awaitable in tests. The static
  # HTTP render ships `storage_drives: []` (StorageBar renders nothing) and
  # the connected render fills it in. The periodic refresh keeps the figure
  # honest as downloads land.
  defp maybe_start_storage(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
      start_async_storage(socket)
    else
      socket
    end
  end

  defp start_async_storage(socket) do
    start_async(socket, :acquisition_storage, fn ->
      # Only drives a download can land on — a DB/image-cache-only drive can't
      # answer "do I have room for this grab?" (see DownloadStorage.media_dir_drives/1).
      DownloadStorage.media_dir_drives(Storage.measure_all())
    end)
  end

  defp load_acquisition(socket) do
    session = SearchSession.current()

    assign(socket,
      search_session: session,
      # An active release-search session resumes in release mode — the
      # one-search-surface flip must not hide work in progress (UIDR-014).
      omnibox_mode: if(session.query != "" or session.groups != [], do: :release, else: :media),
      download_client_ready: Capabilities.download_client_ready?(),
      plan_drafts: Plans.list_drafts(),
      pursuit_rows: MediaCentaur.Acquisition.Pursuits.list_active_rows(),
      history_rows: compute_history_rows(socket.assigns.history_filter, socket.assigns.history_search)
    )
  end

  defp load_pursuit_rows(socket) do
    assign(socket, pursuit_rows: MediaCentaur.Acquisition.Pursuits.list_active_rows())
  end

  defp compute_history_rows(history_filter, history_search) do
    history_filter
    |> HistoryLogic.list_rows_filter()
    |> Pursuits.list_rows()
    |> HistoryLogic.filter_pursuit_rows_by_search(history_search)
  end

  # QueueMonitor pre-filters completed items, but defend in depth: an
  # unconfigured client returns [], a future driver may differ.
  # Pending-cancel suppression is applied here so EVERY snapshot pass
  # (initial load + every QueueMonitor broadcast) honours the user's
  # in-flight cancellations — see Logic.apply_pending_cancels/3.
  #
  # Connectivity arrives pre-graded on the snapshot (the QueueMonitor
  # owns it — see MediaCentaur.Downloads.Connectivity); this LiveView
  # never re-derives client health from snapshot age.
  defp assign_queue_from_state(socket, %MediaCentaur.Downloads.QueueState{} = state) do
    active = Enum.reject(state.items, &(&1.state == :completed))

    {visible, pending_cancels} =
      Logic.apply_pending_cancels(
        active,
        socket.assigns.pending_cancels,
        System.monotonic_time(:second)
      )

    assign(socket,
      active_queue: visible,
      queue_connectivity: state.connectivity,
      queue_last_success_at: state.last_successful_poll_at,
      pending_cancels: pending_cancels,
      queue_loaded?: true
    )
  end

  # `?search=…` and `?filter=…` deep-link from the upcoming-zone badges
  # straight to a pre-filtered activity view. `?prowlarr_search=…` from
  # the same zone pre-fills the manual-search box and auto-fires the
  # search so a user clicking a "no acquisition yet" row immediately
  # sees Prowlarr results.
  @impl true
  def handle_params(params, _uri, socket) do
    was_loaded? = socket.assigns.loaded?

    socket =
      socket
      # Filter assigns first so the async task in `ensure_loaded/1`
      # snapshots the URL-driven filter state when it computes the
      # first `history_rows`. On subsequent handle_params (loaded?=true)
      # the sync `load_history/1` path picks up the new filters.
      |> assign(
        history_search: Map.get(params, "search", ""),
        history_filter: HistoryLogic.parse_filter(Map.get(params, "filter"))
      )
      |> maybe_open_history(params, was_loaded?)
      |> ensure_loaded()
      |> maybe_load_history(was_loaded?)
      |> apply_pursuit_modal_params(params)
      |> apply_plan_modal_params(params)
      |> maybe_trigger_prowlarr_search(Map.get(params, "prowlarr_search"))

    {:noreply, socket}
  end

  # History is collapsed by default — a deep-link that carries history
  # params (`?filter=…` from the upcoming-zone badges, `?search=…`) came
  # FOR that zone, so it auto-expands. Only the FIRST handle_params may
  # do this: `build_pursuit_modal_path/2` re-emits `filter=` on every
  # modal patch, and without the `was_loaded?` gate clicking any pursuit
  # row would pop History open underneath the modal.
  # Durable History disclosure preference. Persisted in Settings (not the URL
  # or socket state) so it survives navigating away and coming back — a plain
  # assign resets on every remount. Defaults collapsed so the page leads with
  # active pursuits.
  @history_open_key "ui:downloads:history_open"

  defp history_open_pref do
    case Settings.get_by_key(@history_open_key) do
      {:ok, %{value: %{"open" => open}}} when is_boolean(open) -> open
      _ -> false
    end
  end

  defp put_history_open_pref(open?) do
    # find_or_create_entry upserts (insert when absent, update when present) —
    # same helper DiagnosticsBadge uses for its persisted timestamp.
    Settings.find_or_create_entry(%{key: @history_open_key, value: %{"open" => open?}})
    :ok
  end

  defp maybe_open_history(socket, _params, true), do: socket

  defp maybe_open_history(socket, params, false) do
    if Map.has_key?(params, "filter") or Map.get(params, "search", "") != "" do
      # Deep-link came FOR history — auto-expand, but don't persist (transient).
      assign(socket, history_open?: true)
    else
      # First normal load: restore the durable disclosure preference so an
      # expand survives navigating away and back. Defaults collapsed.
      assign(socket, history_open?: history_open_pref())
    end
  end

  # Skip the sync history reload on first load — the async task spawned
  # by `ensure_loaded/1` already issues it with the URL-snapshot filter
  # values and messages back via `{:acquisition_loaded, _}`. Mid-session
  # URL changes (filter clicks, deep-links) fall through to the sync
  # path so the user sees an immediate result.
  defp maybe_load_history(socket, false), do: socket
  defp maybe_load_history(socket, true), do: load_history(socket)

  # Drives the pursuit detail modal off the `?selected=<pursuit_id>` URL
  # param so the modal participates in browser history — back/forward
  # closes/opens, refresh preserves state, and the URL is shareable.
  defp apply_pursuit_modal_params(socket, %{"selected" => id}) when is_binary(id) and id != "" do
    if id == socket.assigns.selected_pursuit_id do
      socket
    else
      socket
      |> assign(:selected_pursuit_id, id)
      # Nil = "use each season group's exception-driven default" until
      # the user toggles; reset per pursuit so one show's toggles don't
      # leak into the next.
      |> assign(:board_expanded_seasons, nil)
      |> load_pursuit_detail()
    end
  end

  defp apply_pursuit_modal_params(socket, _params) do
    if socket.assigns.selected_pursuit_id == nil do
      socket
    else
      assign(socket, selected_pursuit_id: nil, pursuit_detail: nil, board_expanded_seasons: nil)
    end
  end

  # Builds a path back to `/download` preserving the History zone
  # filter/search so the modal open/close doesn't reset the user's
  # surrounding view. Overrides are merged last and `nil`-valued keys
  # remove the param.
  defp build_pursuit_modal_path(socket, overrides) do
    base = %{
      "search" => socket.assigns.history_search,
      "filter" => to_string(socket.assigns.history_filter)
    }

    merged =
      base
      |> Map.merge(stringify_overrides(overrides))
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    case merged do
      [] -> "/download"
      params -> "/download?" <> URI.encode_query(params)
    end
  end

  defp stringify_overrides(overrides) do
    Map.new(overrides, fn
      {k, nil} when is_atom(k) -> {to_string(k), nil}
      {k, v} when is_atom(k) -> {to_string(k), to_string(v)}
      {k, v} -> {k, v}
    end)
  end

  # Pre-fill + auto-fire — same code path as the user submitting the
  # search form by hand. No-op when the param is absent or only whitespace.
  defp maybe_trigger_prowlarr_search(socket, query) when is_binary(query) do
    case String.trim(query) do
      "" ->
        socket

      trimmed ->
        case SearchSession.start_search(trimmed) do
          {:ok, %{queries: queries}} ->
            Enum.each(queries, fn q -> send(self(), {:run_search_one, q}) end)
            socket

          {:error, _} ->
            socket
        end
    end
  end

  defp maybe_trigger_prowlarr_search(socket, _), do: socket

  @impl true
  def render(assigns) do
    # Derive once per render — these values are read in multiple places
    # (the search-button spinner, the bulk-retry footer, etc.) and were
    # being recomputed two-to-three times per render.
    #
    # `paired_rows` and `orphan_queue` pair pursuits with their live
    # torrents at render time so the DB-backed `@pursuit_rows` doesn't
    # rebuild on every queue snapshot. The pairing is a pure helper —
    # see `QueueMatcher.match/2`.
    {paired_rows, orphan_queue} = QueueMatcher.match(assigns.pursuit_rows, assigns.active_queue)

    # Partition the unified `[PursuitWithDownload]` list at render time:
    # - `download_cards` keeps the full 2-row card with progress footer
    #   for every pursuit that has a paired torrent.
    # - `active_compact` are the unpaired pursuits — fed through
    #   `Logic.group_pursuit_rows/2` so 7 episodes of the same show in
    #   the same state collapse into one group row.
    # History rows always go through the grouping path (no downloads
    # paired in that zone).
    {download_cards, undownloaded_pwd} =
      Enum.split_with(paired_rows, fn %PursuitWithDownload{downloads: downloads} ->
        downloads != []
      end)

    active_compact =
      Logic.group_pursuit_rows(
        Enum.map(undownloaded_pwd, & &1.row),
        assigns.expanded_pursuit_groups
      )

    history_compact = Logic.group_pursuit_rows(assigns.history_rows, assigns.expanded_pursuit_groups)

    assigns =
      assigns
      |> Phoenix.Component.assign(:any_loading?, Logic.any_loading?(assigns.search_session.groups))
      |> Phoenix.Component.assign(:timeout_terms, Logic.timeout_terms(assigns.search_session.groups))
      |> Phoenix.Component.assign(:paired_rows, paired_rows)
      |> Phoenix.Component.assign(:download_cards, download_cards)
      |> Phoenix.Component.assign(:active_compact, active_compact)
      |> Phoenix.Component.assign(:history_compact, history_compact)
      |> Phoenix.Component.assign(:orphan_queue, orphan_queue)
      |> Phoenix.Component.assign(:storage_mode, DownloadStorage.display_mode(assigns.storage_drives))
      |> Phoenix.Component.assign(
        :telemetry_age,
        Logic.telemetry_age_label(assigns.queue_connectivity, assigns.queue_last_success_at)
      )

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/download"
      full_width
      acquisition_ready={@acquisition_ready}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
    >
      <:overlays>
        <.cancel_confirmation cancel_confirm={@cancel_confirm} />
        <.plan_discard_confirmation open={@plan_discard_confirm?} board={@plan_board} />
        <PlanModal.plan_modal
          open={@plan_param != nil}
          stage={@plan_stage}
          selection={@plan_selection}
          chosen={@plan_chosen}
          expanded_seasons={@plan_expanded_seasons}
          movie={@plan_movie}
          board={@plan_board}
          grab_future={@plan_grab_future}
          error={@plan_error}
          last_activity={@plan_last_activity}
          descent={@plan_descent}
          alternatives={@plan_alternatives}
          approving={@plan_approving?}
        />
        <PursuitModal.pursuit_modal
          open={@selected_pursuit_id != nil}
          pursuit_id={@selected_pursuit_id}
          header={@pursuit_detail && @pursuit_detail.header}
          status={@pursuit_detail && @pursuit_detail.status}
          timeline={@pursuit_detail && @pursuit_detail.timeline}
          unit_board={@pursuit_detail && @pursuit_detail.unit_board}
          board_expanded_seasons={@board_expanded_seasons}
          decision_card={@pursuit_detail && @pursuit_detail.decision_card}
          not_found?={(@pursuit_detail && @pursuit_detail.not_found?) || false}
        />
      </:overlays>
      <%!-- data-nav-default-zone names the LAYOUT KEY in input config.js
            (like `library`/`home`), not a context within it — the nav graph
            is built from this value. --%>
      <div class="relative" data-page-behavior="download" data-nav-default-zone="download">
        <%!-- Same ambient treatment as the home/library pages: a calm
              backdrop band behind the header (masked + dimmed by
              `.page-atmosphere`) plus the fixed side scrim, both behind
              the content (z-0) so they enrich the surface, never the
              cards. --%>
        <div :if={@page_backdrop} class="page-atmosphere" aria-hidden="true">
          <img src={@page_backdrop} alt="" loading="eager" decoding="sync" />
        </div>
        <div :if={@page_backdrop} class="page-side-dim" aria-hidden="true"></div>

        <%!-- Same header recipe + column placement as the library page
              (left-aligned, text-3xl, muted count subtitle) so moving
              between the two pages doesn't shift the title around.

              Width model: the page is full-bleed (like home/library) so
              the atmosphere band spans the viewport, but the content is a
              single readable column capped at max-w-4xl — search and
              drafts on top, active pursuits in the middle, the
              bookkeeping zones (History disclosure, other downloads) at
              the bottom. --%>
        <div class="relative z-[1] max-w-4xl space-y-6">
          <header>
            <h1 class="text-3xl font-bold tracking-tight">Downloads</h1>
            <%!-- One adaptive subtitle line, never a stack. When storage is calm
                  (a single healthy drive) it *is* the subtitle — free space is the
                  most useful ambient fact here. When storage opens up (low / multiple
                  drives) it renders as its own card below, and the subtitle falls back
                  to the activity summary. --%>
            <p
              :if={@storage_mode == :calm}
              class="mt-1 flex items-center gap-2 text-sm text-base-content/60"
            >
              <.icon name="hero-circle-stack-mini" class="size-4 shrink-0 text-base-content/40" />
              {DownloadStorage.calm_summary(@storage_drives)}
            </p>
            <p :if={@storage_mode != :calm} class="mt-1 text-sm text-base-content/60">
              {Logic.pursuit_summary(length(@paired_rows), length(@download_cards))}
            </p>
          </header>

          <DownloadStorage.download_storage drives={@storage_drives} />

          <MediaOmnibox.media_omnibox
            mode={@omnibox_mode}
            query={@omnibox_query}
            results={@omnibox_results}
            searching?={@omnibox_searching?}
            session={@search_session}
            any_loading?={@any_loading?}
          />

          <Search.search_zone
            :if={@omnibox_mode == :release}
            session={@search_session}
            any_loading?={@any_loading?}
            timeout_terms={@timeout_terms}
          />

          <section :if={@plan_drafts != []} data-nav-zone="drafts" class="space-y-3">
            <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Draft plans
            </h2>
            <div class="grid grid-cols-1 gap-2">
              <div
                :for={draft <- @plan_drafts}
                id={"plan-draft-#{draft.id}"}
                class="identity-banner flex items-center gap-3 px-4 py-3"
                style={"--banner-hue: #{banner_hue(draft.title)}"}
              >
                <span class="absolute top-2 left-3 text-[10px] uppercase tracking-wider text-base-content/40">
                  Draft
                </span>
                <div class="min-w-0 flex-1 pt-3">
                  <p class="identity-logotype truncate text-base leading-tight">{draft.title}</p>
                  <p class="text-xs text-info/90 mt-1 [text-shadow:0_1px_3px_oklch(0%_0_0/0.5)]">
                    {if draft.status == "planning",
                      do: "Planning…",
                      else: "Plan ready — review and approve"}
                  </p>
                </div>
                <.button
                  variant="secondary"
                  size="sm"
                  phx-click="resume_plan"
                  phx-value-id={draft.id}
                  data-nav-item
                  tabindex="0"
                >
                  Review plan
                </.button>
              </div>
            </div>
          </section>

          <p
            :if={!@download_client_ready}
            class="scrim-surface rounded-xl px-4 py-3 text-center text-sm text-base-content/50"
          >
            Connect a download client in
            <.link navigate="/settings?section=acquisition" class="link link-primary">
              Settings
            </.link>
            to see live torrent activity under each pursuit.
          </p>

          <section :if={@paired_rows != []} data-nav-zone="pursuits" class="space-y-3">
            <div class="flex items-center justify-between gap-3">
              <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
                Active pursuits
              </h2>
              <div :if={@download_client_ready} class="flex items-center gap-2">
                <ConnectivityBadge.connectivity_badge connectivity={@queue_connectivity} />
                <span
                  :if={!@queue_loaded?}
                  class="loading loading-spinner loading-xs text-base-content/30"
                >
                </span>
              </div>
            </div>
            <div class="grid grid-cols-1 gap-2">
              <PursuitRow.pursuit_row
                :for={
                  %PursuitWithDownload{
                    row: row,
                    download: download,
                    queue_item_id: qid,
                    downloads: downloads
                  } <-
                    @download_cards
                }
                vm={row}
                download={download}
                downloads={downloads}
                queue_item_id={qid}
                telemetry_age={@telemetry_age}
              />
              <.grouped_compact_rows entries={@active_compact} />
            </div>
          </section>

          <History.history_zone
            empty?={@history_rows == []}
            filter={@history_filter}
            search={@history_search}
            open?={@history_open?}
          >
            <.grouped_compact_rows entries={@history_compact} />
          </History.history_zone>

          <OrphanQueue.orphan_zone items={@orphan_queue} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("query_change", %{"query" => query}, socket) do
    session = SearchSession.set_query_preview(query)
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_event("submit_search", %{"query" => query}, socket) do
    if socket.assigns.search_session.grabbing? do
      {:noreply, socket}
    else
      session = SearchSession.set_query_preview(query)

      session =
        case SearchSession.start_search(query) do
          {:ok, %{session: started, queries: queries}} ->
            Enum.each(queries, fn q -> send(self(), {:run_search_one, q}) end)
            started

          {:error, _} ->
            session
        end

      {:noreply, assign(socket, search_session: session)}
    end
  end

  def handle_event("retry_search", %{"term" => term}, socket) do
    {:noreply, assign(socket, search_session: retry_terms(socket, [term]))}
  end

  def handle_event("retry_all_timeouts", _params, socket) do
    terms = Logic.timeout_terms(socket.assigns.search_session.groups)
    {:noreply, assign(socket, search_session: retry_terms(socket, terms))}
  end

  # Dismiss the release-search session entirely — the subtle "Clear search"
  # affordance, so a stale or interrupted search doesn't linger as a dead-end.
  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_session: SearchSession.clear())}
  end

  def handle_event("toggle_group", %{"term" => term}, socket) do
    session = SearchSession.toggle_group(term)
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_event("select_result", %{"term" => term, "guid" => guid}, socket) do
    session =
      case Map.get(socket.assigns.search_session.selections, term) do
        ^guid -> SearchSession.clear_selection(term)
        _ -> SearchSession.set_selection(term, guid)
      end

    {:noreply, assign(socket, search_session: session)}
  end

  def handle_event("cancel_download_prompt", %{"id" => id, "title" => title}, socket) do
    {:noreply, assign(socket, cancel_confirm: %{id: id, title: title})}
  end

  def handle_event("cancel_download_confirm", _params, %{assigns: %{cancel_confirm: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_download_confirm", _params, socket) do
    %{id: id, title: title} = socket.assigns.cancel_confirm

    socket =
      case Acquisition.cancel_download(id) do
        :ok ->
          Log.info(:acquisition, "cancelled download — #{title}")
          # Optimistically drop the row so the user sees feedback now,
          # AND remember the id so the next snapshot — which may still
          # contain the row if qBittorrent's DELETE hasn't propagated —
          # can't ghost it back. Logic.apply_pending_cancels/3 expires
          # the entry after a short grace window so a failed cancel
          # eventually surfaces.
          remaining = Enum.reject(socket.assigns.active_queue, &(&1.id == id))

          pending_cancels =
            Map.put(
              socket.assigns.pending_cancels,
              id,
              System.monotonic_time(:second)
            )

          # Hurry the next reconciliation along instead of waiting for
          # QueueMonitor's idle cadence.
          Acquisition.poll_queue_now()

          socket
          |> assign(active_queue: remaining, pending_cancels: pending_cancels)
          |> put_flash(:info, "Cancelled “#{title}”.")

        {:error, reason} ->
          Log.warning(:acquisition, "cancel failed — #{title} — #{inspect(reason)}")
          put_flash(socket, :error, "Could not cancel “#{title}”.")
      end

    {:noreply, assign(socket, cancel_confirm: nil)}
  end

  def handle_event("cancel_download_cancel", _params, socket) do
    {:noreply, assign(socket, cancel_confirm: nil)}
  end

  # ---------------------------------------------------------------------------
  # Plan flow (UIDR-014) — URL-driven, refresh-safe by construction:
  # `?plan=new&tmdb_id=…&tmdb_type=…` opens targeting; `?plan=<id>`
  # opens the durable draft's board.
  # ---------------------------------------------------------------------------

  def handle_event("plan_preset", %{"preset" => preset}, socket)
      when preset in ~w(everything_aired continue latest_season) do
    selection = socket.assigns.plan_selection

    {:noreply,
     assign(socket, plan_chosen: PlanLogic.apply_preset(selection, String.to_existing_atom(preset)))}
  end

  def handle_event("plan_toggle_season", %{"season" => season}, socket) do
    chosen =
      PlanLogic.toggle_season(
        socket.assigns.plan_chosen,
        socket.assigns.plan_selection,
        String.to_integer(season)
      )

    {:noreply, assign(socket, plan_chosen: chosen)}
  end

  def handle_event("plan_toggle_season_expand", %{"season" => season}, socket) do
    expanded =
      PlanLogic.toggle_expanded(socket.assigns.plan_expanded_seasons, String.to_integer(season))

    {:noreply, assign(socket, plan_expanded_seasons: expanded)}
  end

  def handle_event("plan_toggle_unit", %{"season" => season, "episode" => episode}, socket) do
    chosen =
      PlanLogic.toggle_unit(
        socket.assigns.plan_chosen,
        socket.assigns.plan_selection,
        {String.to_integer(season), String.to_integer(episode)}
      )

    {:noreply, assign(socket, plan_chosen: chosen)}
  end

  def handle_event("plan_toggle_grab_future", _params, socket) do
    {:noreply, assign(socket, plan_grab_future: !socket.assigns.plan_grab_future)}
  end

  def handle_event("plan_create", _params, socket) do
    grab_future = socket.assigns.plan_grab_future

    result =
      case socket.assigns.plan_stage do
        :targeting ->
          selection = socket.assigns.plan_selection
          units = PlanLogic.chosen_in_order(socket.assigns.plan_chosen, selection)

          if units == [],
            do: :noop,
            else: Plans.create_series_plan(selection, units, grab_future: grab_future)

        :movie_confirm ->
          movie = socket.assigns.plan_movie
          if movie.in_library?, do: :noop, else: Plans.create_movie_plan(movie, grab_future: grab_future)
      end

    case result do
      :noop ->
        {:noreply, socket}

      {:ok, plan} ->
        # The intent just materialized into a draft — the omnibox hunt is
        # over, so it resets to its resting question. (Canceling the flow
        # before this point keeps the query alive for another pick.)
        {:noreply,
         socket
         |> assign(
           plan_drafts: Plans.list_drafts(),
           omnibox_query: "",
           omnibox_results: [],
           omnibox_searching?: false,
           omnibox_searched: nil
         )
         |> push_patch(to: "/download?plan=#{plan.id}")}

      {:error, reason} ->
        Log.warning(:acquisition, "plan create failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not create the plan.")}
    end
  end

  def handle_event("plan_show_alternatives", %{"unit-id" => unit_id}, socket) do
    case Plans.alternatives_for(unit_id) do
      {:ok, items} ->
        {:noreply,
         assign(socket, plan_alternatives: %{unit_id: unit_id, items: items, searching?: false})}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("plan_find_more_alternatives", %{"unit-id" => unit_id}, socket) do
    case socket.assigns.plan_alternatives do
      %{unit_id: ^unit_id, searching?: false} = open ->
        {:noreply,
         socket
         |> assign(plan_alternatives: Map.put(open, :searching?, true))
         |> start_async(:plan_find_more, fn -> {unit_id, Plans.search_alternatives(unit_id)} end)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("plan_hide_alternatives", _params, socket) do
    {:noreply, assign(socket, plan_alternatives: nil)}
  end

  def handle_event("plan_choose_release", %{"unit-id" => unit_id, "guid" => guid}, socket) do
    case Plans.choose_release(unit_id, guid) do
      {:ok, _plan} ->
        {:noreply, assign(socket, plan_alternatives: nil)}

      {:error, reason} ->
        Log.warning(:acquisition, "plan choose failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not pick that release.")}
    end
  end

  def handle_event("plan_swap_release", %{"unit-id" => unit_id, "guid" => guid}, socket) do
    case Plans.exclude_release(unit_id, guid) do
      {:ok, _plan} ->
        {:noreply, assign(socket, plan_alternatives: nil)}

      {:error, reason} ->
        Log.warning(:acquisition, "plan swap failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not swap that release.")}
    end
  end

  def handle_event("plan_search_again", _params, socket) do
    with %{plan_id: plan_id} <- socket.assigns.plan_board,
         {:ok, plan} <- Plans.get(plan_id),
         {:ok, _plan} <- Plans.replan(plan, force_search: true) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not re-run the search.")}
    end
  end

  # The gap handoff (ADR-056): unfound units become gap wants on the
  # title's tracking entry. Context-layer async — creating the track
  # fetches TMDB, which doesn't belong inline in an event handler.
  def handle_event("plan_track_gaps", _params, socket) do
    case socket.assigns.plan_board do
      %{plan_id: plan_id, gaps: gaps} when gaps != [] ->
        Acquisition.track_plan_gaps_async(plan_id)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Watching for #{length(gaps)} missing #{if length(gaps) == 1, do: "episode", else: "episodes"} — release tracking will keep looking"
         )}

      _ ->
        {:noreply, socket}
    end
  end

  # Approval submits real grabs (Prowlarr → indexer → download client) —
  # seconds of network per release. Running it inline froze the LV, so it
  # rides an owned async (ADR-049) behind an "Approving…" button state.
  def handle_event("plan_approve", _params, socket) do
    with false <- socket.assigns.plan_approving?,
         %{plan_id: plan_id} <- socket.assigns.plan_board do
      {:noreply,
       socket
       |> assign(plan_approving?: true)
       |> start_async(:plan_approve, fn ->
         with {:ok, plan} <- Plans.get(plan_id), do: Plans.approve(plan)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("plan_discard_prompt", _params, socket) do
    {:noreply, assign(socket, plan_discard_confirm?: true)}
  end

  def handle_event("plan_discard_cancel", _params, socket) do
    {:noreply, assign(socket, plan_discard_confirm?: false)}
  end

  def handle_event("plan_discard_confirm", _params, %{assigns: %{plan_discard_confirm?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("plan_discard_confirm", _params, socket) do
    socket = assign(socket, plan_discard_confirm?: false)

    with %{plan_id: plan_id} <- socket.assigns.plan_board,
         {:ok, plan} <- Plans.get(plan_id),
         {:ok, _discarded} <- Plans.discard(plan) do
      {:noreply,
       socket
       |> assign(plan_drafts: Plans.list_drafts())
       |> put_flash(:info, "Plan discarded.")
       |> push_patch(to: "/download")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not discard the plan.")}
    end
  end

  def handle_event("close_plan", _params, socket) do
    {:noreply, push_patch(socket, to: "/download")}
  end

  def handle_event("resume_plan", %{"id" => plan_id}, socket) do
    {:noreply, push_patch(socket, to: "/download?plan=#{plan_id}")}
  end

  # ---------------------------------------------------------------------------
  # Omnibox (UIDR-014) — one search surface, two modes.
  # ---------------------------------------------------------------------------

  def handle_event("omnibox_change", %{"query" => query}, socket) do
    trimmed = String.trim(query)
    socket = assign(socket, omnibox_query: query)

    cond do
      String.length(trimmed) < 2 ->
        {:noreply, assign(socket, omnibox_results: [], omnibox_searching?: false, omnibox_searched: nil)}

      # TMDB citizenship: a re-fire of the same effective query (trailing
      # space, blur/focus echo) never searches again — each debounce fire
      # costs two API calls (movie + tv).
      trimmed == socket.assigns.omnibox_searched ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> assign(omnibox_searching?: true, omnibox_searched: trimmed)
         |> cancel_async(:omnibox_search, :superseded)
         |> start_async(:omnibox_search, fn -> {query, ReleaseTracking.search_tmdb(trimmed)} end)}
    end
  end

  def handle_event("omnibox_mode", %{"mode" => mode}, socket) when mode in ~w(media release) do
    {:noreply,
     assign(socket,
       omnibox_mode: String.to_existing_atom(mode),
       omnibox_results: [],
       omnibox_query: "",
       omnibox_searching?: false,
       omnibox_searched: nil
     )}
  end

  def handle_event("omnibox_pick", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    plan_type = if media_type == "movie", do: "movie", else: "tv"

    {:noreply, push_patch(socket, to: "/download?plan=new&tmdb_id=#{tmdb_id}&tmdb_type=#{plan_type}")}
  end

  def handle_event("grab_selected", _params, socket) do
    selections = socket.assigns.search_session.selections

    if map_size(selections) == 0 do
      {:noreply, socket}
    else
      # Keep the expanded term with its picked result — the batch
      # collapses into one composite pursuit whose units each carry
      # their term as the concrete search query (ADR-055).
      picks =
        selections
        |> Enum.map(fn {term, guid} ->
          case Logic.find_result(socket.assigns.search_session.groups, guid) do
            nil -> nil
            result -> %{term: term, result: result}
          end
        end)
        |> Enum.reject(&is_nil/1)

      session = SearchSession.set_grabbing(true)
      send(self(), {:run_grabs, picks})
      {:noreply, assign(socket, search_session: session)}
    end
  end

  # History-zone events (filter, search). Row-level cancel / re-arm
  # actions are gone — rows are passive and clicking one opens the
  # pursuit modal where Cancel / Change target live.

  def handle_event("toggle_history", _params, socket) do
    open? = !socket.assigns.history_open?
    put_history_open_pref(open?)
    {:noreply, assign(socket, history_open?: open?)}
  end

  def handle_event("set_history_filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(history_filter: HistoryLogic.parse_filter(filter))
     |> load_history()}
  end

  def handle_event("set_history_search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(history_search: search) |> load_history()}
  end

  # Group expand/collapse. Toggles membership of
  # `{title, state, awaiting?}` in the socket-local
  # `expanded_pursuit_groups` MapSet. The 3-tuple matches the bucket key
  # `Logic.group_pursuit_rows/2` uses to separate awaiting-decision
  # pursuits from regular active ones — same `{title, state}` pair can
  # appear in two distinct buckets, so the expanded set must
  # discriminate.
  #
  # `String.to_existing_atom/1` is safe here because the only emitter is
  # the `PursuitGroup` component, which renders `Atom.to_string(state)`
  # from a closed enum (`Pursuits.State`). An adversarial value just
  # falls through to ArgumentError, which we let crash the event —
  # there's no graceful render for "user fabricated a state we don't
  # know about".
  def handle_event(
        "toggle_pursuit_group",
        %{"title" => title, "state" => state, "awaiting" => awaiting},
        socket
      ) do
    key = {title, String.to_existing_atom(state), awaiting == "true"}
    expanded = socket.assigns.expanded_pursuit_groups

    next =
      if MapSet.member?(expanded, key) do
        MapSet.delete(expanded, key)
      else
        MapSet.put(expanded, key)
      end

    {:noreply, assign(socket, expanded_pursuit_groups: next)}
  end

  # Pursuit detail modal — open / close via URL.

  def handle_event("select_pursuit", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: build_pursuit_modal_path(socket, %{selected: id}))}
  end

  def handle_event("close_pursuit", _params, socket) do
    {:noreply, push_patch(socket, to: build_pursuit_modal_path(socket, %{selected: nil}))}
  end

  # Pursuit detail modal — manual actions. All four operate on
  # `selected_pursuit_id`; the open modal is the implicit target.

  def handle_event("cancel_pursuit", _params, socket) do
    case Cancel.execute(%{
           pursuit_id: socket.assigns.selected_pursuit_id,
           cancelled_by: :user,
           reason: CancelReasons.user_request()
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Pursuit cancelled.") |> load_pursuit_detail()}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit cancel failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not cancel pursuit.")}
    end
  end

  def handle_event("toggle_board_season", %{"season" => season_key}, socket) do
    # First toggle materializes the nil "use defaults" sentinel into the
    # default set, then flips — so the user's click composes with the
    # exception-driven defaults instead of discarding them.
    groups =
      case socket.assigns.pursuit_detail do
        %{unit_board: %ViewModels.UnitBoard{groups: groups}} -> groups
        _detail -> nil
      end

    expanded =
      socket.assigns.board_expanded_seasons || ViewModels.UnitBoard.default_expanded(groups)

    expanded =
      if MapSet.member?(expanded, season_key),
        do: MapSet.delete(expanded, season_key),
        else: MapSet.put(expanded, season_key)

    {:noreply, assign(socket, :board_expanded_seasons, expanded)}
  end

  def handle_event("change_target", params, socket) do
    # An optional `unit-id` (from the unit-board drill-down) scopes the
    # pivot to one unit of a composite; without it the lead unit pivots.
    args =
      case params do
        %{"unit-id" => unit_id} when is_binary(unit_id) ->
          %{pursuit_id: socket.assigns.selected_pursuit_id, unit_id: unit_id}

        _ ->
          %{pursuit_id: socket.assigns.selected_pursuit_id}
      end

    case ChangeTarget.execute(args) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Looking for a new target…") |> load_pursuit_detail()}

      {:error, :not_eligible} ->
        {:noreply, put_flash(socket, :error, "This pursuit can't change target right now.")}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit change-target failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not change target for this pursuit.")}
    end
  end

  def handle_event("request_decision", params, socket) do
    # An optional `unit-id` (unit-board swap) scopes the decision to one
    # unit of a composite — the alternatives list follows it because the
    # awaiting unit becomes the lead (Units.lead_of/1).
    args =
      case params do
        %{"unit-id" => unit_id} when is_binary(unit_id) ->
          %{pursuit_id: socket.assigns.selected_pursuit_id, unit_id: unit_id, prompt: @decision_prompt}

        _other ->
          %{pursuit_id: socket.assigns.selected_pursuit_id, prompt: @decision_prompt}
      end

    case RequestDecision.execute(args) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Pick a release below.") |> load_pursuit_detail()}

      {:error, reason} ->
        Log.warning(:acquisition, "request decision failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not switch to decision mode.")}
    end
  end

  # Submitting a pick involves `Prowlarr.grab/1` (POST + indexer wait) and
  # the `PickTarget` write. Running that inline blocks the LiveView past
  # the heartbeat window — same pattern that previously disconnected
  # `refresh_alternatives`. So we spawn a Task.Supervisor child and
  # message the outcome back via `{:alternative_picked, pursuit_id, outcome}`.
  #
  # Fast path: when the SearchResult for this guid is still in the
  # `decision_results_by_guid` cache from the last render, pass it
  # straight to `Acquisition.pick_alternative/3` — no second Prowlarr
  # search to translate guid → result. Cache miss (rare — modal lost
  # its assigns) falls back to the guid string, which re-runs the
  # pursuit's search internally.
  def handle_event(
        "pick_alternative",
        %{"pursuit-id" => pursuit_id, "guid" => guid, "label" => label},
        socket
      ) do
    arg =
      case get_in(socket.assigns, [:pursuit_detail, :decision_results_by_guid, guid]) do
        nil -> guid
        result -> result
      end

    Acquisition.pick_alternative_async(pursuit_id, arg, label, self())
    {:noreply, put_flash(socket, :info, "Trying alternative…")}
  end

  # Re-fetch decision-card alternatives. The Prowlarr round-trip can take
  # several seconds (especially with brace-expanded fan-out across
  # multiple indexers); doing it inline blocks the LiveView process
  # past the heartbeat window and the client disconnects.
  # We therefore:
  #
  #   1. event fires → flip the open card to `loading?: true` and render
  #      the spinner. Spawn a Task.Supervisor child to do the fetch.
  #   2. background task → resolve the new decision card, then
  #      `send(parent, {:alternatives_refreshed, pursuit_id, card})`.
  #   3. info handler matches that message → if the modal is still on
  #      the same pursuit, swap the card in and flash if Prowlarr
  #      returned nothing.
  def handle_event("refresh_alternatives", _params, socket) do
    case socket.assigns.pursuit_detail do
      %{decision_card: card} = detail when not is_nil(card) ->
        loading_card = %{card | loading?: true, alternatives: []}

        socket =
          assign(socket,
            pursuit_detail: %{detail | decision_card: loading_card, decision_results_by_guid: %{}}
          )

        pursuit_id = socket.assigns.selected_pursuit_id

        socket =
          start_async(socket, {:alternatives_refresh, pursuit_id}, fn ->
            case Pursuits.get(pursuit_id) do
              {:ok, pursuit} ->
                header = Pursuits.header_from(pursuit)

                # "Search Prowlarr again" is the user-initiated refresh —
                # it bypasses the corpus freshness gate (ADR-055).
                build_decision(
                  pursuit,
                  header.awaiting_decision?,
                  header.recipe.search_queries,
                  nil,
                  force: true
                )

              _ ->
                %{card: nil, results_by_guid: %{}}
            end
          end)

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Async work + queue polling
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:capabilities_changed, socket) do
    if Capabilities.prowlarr_ready?() do
      # Ping QueueMonitor in case the user just configured the download
      # client — without this nudge we would wait up to 30 s (idle cadence)
      # for the queue to populate.
      Acquisition.poll_queue_now()
      {:noreply, assign(socket, download_client_ready: Capabilities.download_client_ready?())}
    else
      {:noreply, push_navigate(socket, to: "/")}
    end
  end

  def handle_info({:run_search_one, query}, socket) do
    Acquisition.run_search_one_async(query, &SearchSession.record_search_result/2)
    {:noreply, socket}
  end

  def handle_info({:search_session, session}, socket) do
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_info({:run_grabs, picks}, socket) do
    query = socket.assigns.search_session.query

    # One composite pursuit for the whole batch (ADR-055) — pairs still
    # report per-pick outcomes for the grab message.
    pairs =
      case Acquisition.pick_targets(picks, query) do
        {:ok, pairs} -> pairs
        {:error, reason} -> Enum.map(picks, fn pick -> {pick, {:error, reason}} end)
      end

    Enum.each(pairs, fn
      {pick, {:error, reason}} ->
        Log.warning(:acquisition, "manual pick failed — #{pick.result.title} — #{inspect(reason)}")

      _ ->
        :ok
    end)

    ok_count = Enum.count(pairs, fn {_, outcome} -> match?({:ok, _}, outcome) end)
    err_count = length(pairs) - ok_count
    Log.info(:acquisition, "manual pick batch complete — #{ok_count} ok, #{err_count} failed")

    SearchSession.set_grab_message(Logic.build_grab_message(pairs))
    SearchSession.clear_results()
    SearchSession.set_grabbing(false)

    {:noreply, socket}
  end

  def handle_info({:queue_state, %MediaCentaur.Downloads.QueueState{} = state}, socket) do
    # Pass the items list through to the modal refresh so the modal's
    # download progress updates from the same snapshot the queue zone
    # is rendering — and without firing the three DB reads that the
    # previous `Pursuits.status_for/1` path required.
    socket =
      socket
      |> assign_queue_from_state(state)
      |> refresh_pursuit_status_if_open(state.items)

    {:noreply, socket}
  end

  def handle_info(:reload_history, socket) do
    {:noreply, load_history(socket)}
  end

  def handle_info(:refresh_storage, socket) do
    Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
    {:noreply, start_async_storage(socket)}
  end

  # All `acquisition:updates` broadcasts are typed structs — either
  # `Pursuits.Events.*` (persisted timeline events) or `TargetEvents.*`
  # (transient lifecycle signals). TargetEvents trigger a History
  # reload (terminal state transitions show up there);
  # Pursuits.Events trigger a pursuit-row reload + modal sync.
  def handle_info(%struct{} = event, socket) do
    cond do
      struct == PlanEvents.Changed ->
        socket =
          socket
          |> assign(plan_drafts: Plans.list_drafts())
          |> maybe_reload_plan_board(event)

        {:noreply, socket}

      struct == PlanEvents.SearchActivity ->
        {:noreply, maybe_note_plan_activity(socket, event)}

      struct == PlanEvents.DescentStatus ->
        {:noreply, maybe_note_plan_descent(socket, event)}

      TargetEvents.event?(struct) ->
        {:noreply, debounce(socket, :reload_timer, :reload_history, 500)}

      PursuitEvents.event?(struct) ->
        socket =
          socket
          |> debounce(:pursuits_reload_timer, :reload_pursuits, 500)
          |> maybe_reload_modal_for_event(event)

        {:noreply, socket}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info(:reload_pursuits, socket) do
    {:noreply, load_pursuit_rows(socket)}
  end

  # Result of the background pick task. Like the alternatives fetches,
  # only applies the outcome when the modal is still on the same pursuit
  # — a closed or pivoted modal drops the stale result. Success is
  # silent on the LV side (the PubSub `:target_picked` reload re-renders
  # the modal); failures surface as flashes.
  def handle_info({:alternative_picked, pursuit_id, outcome}, socket) do
    if socket.assigns.selected_pursuit_id == pursuit_id do
      case outcome do
        {:ok, _pursuit} ->
          {:noreply, load_pursuit_detail(socket)}

        {:error, :alternative_unavailable} ->
          {:noreply, put_flash(socket, :error, "That release is no longer available.")}

        {:error, reason} ->
          Log.warning(:acquisition, "pick alternative failed — #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Could not pick that alternative.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Initial modal-open alternatives fetch. Drops the result if the user has
  # closed the modal or pivoted to another pursuit. No flash on empty — the
  # empty card's "Search Prowlarr again" CTA is self-explanatory.
  @impl true
  def handle_async(:plan_targeting, {:ok, outcome}, socket) do
    case outcome do
      {:tv, selection} ->
        {:noreply,
         assign(socket,
           plan_stage: :targeting,
           plan_selection: selection,
           plan_chosen: PlanLogic.apply_preset(selection, :everything_aired)
         )}

      {:movie, movie} ->
        {:noreply, assign(socket, plan_stage: :movie_confirm, plan_movie: movie)}

      {:error, reason} ->
        Log.warning(:acquisition, "plan targeting failed — #{inspect(reason)}")
        {:noreply, assign(socket, plan_stage: :error, plan_error: "Couldn't load this title from TMDB.")}
    end
  end

  def handle_async(:plan_targeting, {:exit, reason}, socket) do
    Log.warning(:acquisition, "plan targeting crashed — #{inspect(reason)}")
    {:noreply, assign(socket, plan_stage: :error, plan_error: "Couldn't load this title from TMDB.")}
  end

  def handle_async({:pursuit_artwork, pursuit_id}, {:ok, urls}, socket) do
    case socket.assigns do
      %{selected_pursuit_id: ^pursuit_id, pursuit_detail: %{header: header} = detail}
      when not is_nil(header) ->
        updated = %{header | backdrop_url: urls.backdrop_url, logo_url: urls.logo_url}
        {:noreply, assign(socket, pursuit_detail: %{detail | header: updated})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_async({:pursuit_artwork, _pursuit_id}, {:exit, reason}, socket) do
    Log.warning(:acquisition, "artwork fetch crashed — #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async(:plan_approve, {:ok, outcome}, socket) do
    socket = assign(socket, plan_approving?: false)

    case outcome do
      {:ok, committed} ->
        {:noreply,
         socket
         |> assign(plan_drafts: Plans.list_drafts())
         |> put_flash(:info, "Pursuit started.")
         |> push_patch(to: "/download?selected=#{committed.pursuit_id}")}

      {:error, {:overlap, units}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Already being pursued: #{Logic.overlap_labels(units)}. Remove the overlap first."
         )}

      {:error, :nothing_to_grab} ->
        {:noreply, put_flash(socket, :error, "Nothing in this plan is grabbable yet.")}

      {:error, reason} ->
        Log.warning(:acquisition, "plan approve failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not commit the plan.")}
    end
  end

  def handle_async(:plan_approve, {:exit, reason}, socket) do
    Log.warning(:acquisition, "plan approve crashed — #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(plan_approving?: false)
     |> put_flash(:error, "Could not commit the plan.")}
  end

  def handle_async(:omnibox_search, {:ok, {query, results}}, socket) do
    # Stale guard: only the newest query's results land.
    if query == socket.assigns.omnibox_query do
      rows =
        results
        # One TMDB page, relevance-ranked — the dropdown scrolls; depth
        # past 20 is a query-refinement problem, not a pagination one.
        |> Enum.take(20)
        |> Enum.map(fn result ->
          %MediaOmnibox.Result{
            tmdb_id: result.tmdb_id,
            media_type: result.media_type,
            name: result.name,
            year: result.year,
            poster_path: result.poster_path,
            tracked?: result.already_tracked
          }
        end)

      {:noreply, assign(socket, omnibox_results: rows, omnibox_searching?: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:omnibox_search, {:exit, _reason}, socket) do
    {:noreply, assign(socket, omnibox_searching?: false)}
  end

  def handle_async({:alternatives_fetch, pursuit_id}, {:ok, decision}, socket) do
    case socket.assigns do
      %{selected_pursuit_id: ^pursuit_id, pursuit_detail: %{} = detail} ->
        {:noreply,
         assign(socket,
           pursuit_detail: %{
             detail
             | decision_card: decision.card,
               decision_results_by_guid: decision.results_by_guid
           }
         )}

      _ ->
        {:noreply, socket}
    end
  end

  # "Search Prowlarr again" refresh. Same stale-guard; flashes on empty.
  def handle_async({:alternatives_refresh, pursuit_id}, {:ok, decision}, socket) do
    case socket.assigns do
      %{selected_pursuit_id: ^pursuit_id, pursuit_detail: %{} = detail} ->
        socket =
          assign(socket,
            pursuit_detail: %{
              detail
              | decision_card: decision.card,
                decision_results_by_guid: decision.results_by_guid
            }
          )

        socket =
          case decision.card do
            %{alternatives: []} ->
              put_flash(socket, :info, "Prowlarr returned no new alternatives.")

            _ ->
              socket
          end

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:plan_find_more, {:ok, {unit_id, result}}, socket) do
    case {result, socket.assigns.plan_alternatives} do
      {{:ok, items}, %{unit_id: ^unit_id}} ->
        {:noreply,
         assign(socket, plan_alternatives: %{unit_id: unit_id, items: items, searching?: false})}

      {_result, %{unit_id: ^unit_id} = open} ->
        {:noreply, assign(socket, plan_alternatives: Map.put(open, :searching?, false))}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_async(:plan_find_more, {:exit, reason}, socket) do
    Log.warning(:acquisition, "find-more alternatives crashed — #{inspect(reason)}")

    case socket.assigns.plan_alternatives do
      %{} = open -> {:noreply, assign(socket, plan_alternatives: Map.put(open, :searching?, false))}
      _other -> {:noreply, socket}
    end
  end

  def handle_async(:acquisition_storage, {:ok, drives}, socket) do
    {:noreply, assign(socket, storage_drives: drives)}
  end

  def handle_async(name, {:exit, reason}, socket) do
    Log.warning(:acquisition, "acquisition async #{inspect(name)} failed — #{inspect(reason)}")
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Pursuit detail modal — loading + refresh helpers (moved from the
  # legacy PursuitLive when the detail page collapsed into a modal).
  # ---------------------------------------------------------------------------

  # Full load — includes the (possibly Prowlarr-hitting) decision card
  # build. Used on initial open and on pursuit-lifecycle events.
  # A TMDB pursuit whose local artwork lookup came back empty fetches
  # and caches it off-process (one TMDB detail call + the standard
  # ImageStore downloads); the result re-lands on the open header only.
  defp maybe_fetch_artwork(socket, header) do
    recipe = header.recipe

    if recipe.recipe_type == :tmdb and recipe.tmdb_id != nil and is_nil(header.backdrop_url) and
         Capabilities.tmdb_ready?() do
      pursuit_id = header.id

      start_async(socket, {:pursuit_artwork, pursuit_id}, fn ->
        Acquisition.Artwork.ensure(recipe.tmdb_id, recipe.tmdb_type)
      end)
    else
      socket
    end
  end

  defp load_pursuit_detail(%{assigns: %{selected_pursuit_id: nil}} = socket) do
    assign(socket, pursuit_detail: nil)
  end

  defp load_pursuit_detail(%{assigns: %{selected_pursuit_id: id}} = socket) do
    case Pursuits.get(id) do
      {:ok, %Pursuit{} = pursuit} ->
        # One DB read for the pursuit; reuse the struct for the header
        # and status assemblers (was previously three separate Repo.gets
        # of the same row — see audit M2). DB-only work below; the
        # Prowlarr decision-card fetch is dispatched off-process so the
        # modal opens in <5 ms regardless of indexer latency
        # (ADR-044).
        header = Pursuits.header_from(pursuit)
        status = Pursuits.status_from(pursuit)
        socket = maybe_fetch_artwork(socket, header)
        timeline = Pursuits.timeline_for(pursuit.id)
        unit_board = Pursuits.unit_board_for(pursuit)

        {card, results_by_guid, needs_fetch?} =
          decision_card_or_placeholder(
            pursuit,
            header.awaiting_decision?,
            header.recipe.search_queries,
            socket.assigns.pursuit_detail
          )

        socket =
          assign(socket,
            pursuit_detail: %{
              header: header,
              status: status,
              timeline: timeline,
              unit_board: unit_board,
              decision_card: card,
              decision_results_by_guid: results_by_guid,
              not_found?: false
            }
          )

        if needs_fetch?, do: start_async_alternatives_fetch(socket, pursuit.id), else: socket

      {:error, :not_found} ->
        assign(socket,
          pursuit_detail: %{
            header: nil,
            status: nil,
            timeline: nil,
            unit_board: nil,
            decision_card: nil,
            decision_results_by_guid: %{},
            not_found?: true
          }
        )
    end
  end

  # Three-tuple decision for the modal-open path:
  #
  #   * `{cached_card, cached_results, false}` — pursuit is awaiting
  #     decision and we already have alternatives for it in socket
  #     state (a PubSub-driven `maybe_reload_modal_for_event/2` reload
  #     while the modal is open). Reuse them to avoid a redundant
  #     Prowlarr round-trip on every event burst.
  #   * `{loading_card, %{}, true}` — pursuit is awaiting decision and
  #     this is a first open (or the user pivoted to a different
  #     pursuit). Render the card immediately in its `loading?: true`
  #     state and dispatch the Prowlarr fetch as a Task; the result
  #     lands on the `{:alternatives_loaded, _, _}` handle_info clause
  #     below.
  #   * `{nil, %{}, false}` — pursuit is not awaiting decision; no card.
  defp decision_card_or_placeholder(%Pursuit{} = pursuit, true = _awaiting?, queries, cached) do
    case cached do
      %{
        decision_card: %ViewModels.DecisionCard{pursuit_id: id, loading?: false} = vm,
        decision_results_by_guid: results
      }
      when id == pursuit.id ->
        {vm, results, false}

      _ ->
        loading = %ViewModels.DecisionCard{
          pursuit_id: pursuit.id,
          prompt: @decision_prompt,
          alternatives: [],
          loading?: true,
          search_queries: queries
        }

        {loading, %{}, true}
    end
  end

  defp decision_card_or_placeholder(_pursuit, _awaiting?, _queries, _cached), do: {nil, %{}, false}

  # Owned async (ADR-049): runs off the LV process via start_async/3 so the
  # WebSocket handler returns immediately, the task is cancelled with the
  # LiveView, and tests can await it. Result lands in
  # `handle_async({:alternatives_fetch, pursuit_id}, …)`, which ignores it
  # if the user has closed the modal or selected a different pursuit.
  defp start_async_alternatives_fetch(socket, pursuit_id) do
    start_async(socket, {:alternatives_fetch, pursuit_id}, fn ->
      case Pursuits.get(pursuit_id) do
        {:ok, pursuit} ->
          header = Pursuits.header_from(pursuit)
          build_decision(pursuit, header.awaiting_decision?, header.recipe.search_queries, nil)

        _ ->
          %{card: nil, results_by_guid: %{}}
      end
    end)
  end

  # Cheap refresh — re-derives only the queue-dependent fields against
  # the queue snapshot we just received, with no DB round-trip. Lifecycle
  # events still trigger a full `load_pursuit_detail/1` via the
  # `pursuit-event` debounce handler. See audit C1.
  defp refresh_pursuit_status_if_open(socket, queue_items) when is_list(queue_items) do
    case socket.assigns do
      %{selected_pursuit_id: nil} ->
        socket

      %{pursuit_detail: %{status: %_{} = status} = detail} ->
        refreshed = Pursuits.refresh_status_download(status, queue_items)
        assign(socket, pursuit_detail: %{detail | status: refreshed})

      _ ->
        socket
    end
  end

  defp maybe_reload_modal_for_event(socket, %{pursuit_id: pursuit_id}) do
    if socket.assigns.selected_pursuit_id == pursuit_id do
      load_pursuit_detail(socket)
    else
      socket
    end
  end

  defp maybe_reload_modal_for_event(socket, _event), do: socket

  defp apply_plan_modal_params(socket, params) do
    case Map.get(params, "plan") do
      nil ->
        assign(socket,
          plan_param: nil,
          plan_selection: nil,
          plan_movie: nil,
          plan_board: nil,
          plan_descent: nil,
          plan_alternatives: nil,
          plan_error: nil,
          plan_discard_confirm?: false
        )

      "new" ->
        open_plan_targeting(socket, params)

      plan_id ->
        open_plan_board(socket, plan_id)
    end
  end

  defp open_plan_targeting(socket, %{"tmdb_id" => tmdb_id, "tmdb_type" => tmdb_type} = _params)
       when tmdb_type in ~w(movie tv) do
    param = {tmdb_id, tmdb_type}

    if socket.assigns.plan_param == param do
      socket
    else
      socket
      |> assign(
        plan_param: param,
        plan_stage: :loading,
        plan_selection: nil,
        plan_movie: nil,
        plan_board: nil,
        plan_chosen: MapSet.new(),
        plan_expanded_seasons: MapSet.new(),
        plan_grab_future: false,
        plan_error: nil
      )
      |> start_async(:plan_targeting, fn -> load_targeting(tmdb_id, tmdb_type) end)
    end
  end

  defp open_plan_targeting(socket, _params) do
    assign(socket, plan_param: nil, plan_stage: :error, plan_error: "Malformed plan link.")
  end

  # Runs in the :plan_targeting async task — TMDB + library reads only.
  defp load_targeting(tmdb_id, "tv") do
    case Targeting.series_selection(tmdb_id) do
      {:ok, selection} -> {:tv, selection}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_targeting(tmdb_id, "movie") do
    case MediaCentaur.TMDB.Client.get_movie(tmdb_id) do
      {:ok, movie} ->
        in_library? =
          case MediaCentaur.Library.find_present_movie(to_string(tmdb_id)) do
            {:ok, _path} -> true
            :not_found -> false
          end

        {:movie, PlanLogic.movie_facts(movie, in_library?)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp open_plan_board(socket, plan_id) do
    case Plans.get(plan_id) do
      {:ok, plan} ->
        board = Plans.board_for(plan)

        assign(socket,
          plan_param: plan_id,
          plan_stage: :board,
          plan_board: board,
          plan_descent: plan_descent_for(socket, plan_id, board),
          plan_error: nil
        )

      {:error, :not_found} ->
        assign(socket,
          plan_param: plan_id,
          plan_stage: :error,
          plan_error: "Plan not found — it may have been discarded."
        )
    end
  end

  # Keep a live-updated panel across board reloads; seed the itinerary
  # for a freshly-opened planning board; movies don't narrate.
  defp plan_descent_for(socket, plan_id, board) do
    cond do
      socket.assigns.plan_param == plan_id && socket.assigns.plan_descent ->
        socket.assigns.plan_descent

      board.status == :planning and not board.movie? ->
        DescentNarrative.initial(board.wanted)

      true ->
        nil
    end
  end

  # The durable plan rows are the state of record — a Changed event for
  # the open plan just re-reads the board.
  defp maybe_reload_plan_board(socket, %PlanEvents.Changed{plan_id: plan_id}) do
    if socket.assigns.plan_param == plan_id do
      open_plan_board(socket, plan_id)
    else
      socket
    end
  end

  defp maybe_note_plan_activity(socket, %PlanEvents.SearchActivity{} = activity) do
    if socket.assigns.plan_param == activity.plan_id do
      line =
        case activity.outcome do
          :error -> "Search failed: #{activity.term}"
          :corpus -> "#{activity.term} — #{activity.result_count} known (corpus)"
          :live -> "Searched: #{activity.term} — #{activity.result_count} found"
        end

      assign(socket, plan_last_activity: line)
    else
      socket
    end
  end

  defp maybe_note_plan_descent(socket, %PlanEvents.DescentStatus{} = status) do
    if socket.assigns.plan_param == status.plan_id do
      assign(socket, plan_descent: DescentNarrative.build(status))
    else
      socket
    end
  end

  # Reuse the cached decision card while the pursuit is awaiting a
  # decision — the alternatives don't refresh until the user acts or
  # the pursuit's `awaiting_decision_at` clears. This caps Prowlarr
  # load at one search per "awaiting decision" period rather than one
  # per queue snapshot.
  #
  # Returns both the display VM (`card`) and the raw `[SearchResult.t()]`
  # keyed by guid (`results_by_guid`). The LV stores both so
  # `handle_event("pick_alternative", ...)` can pass the cached struct
  # straight to `Acquisition.pick_alternative/3`, skipping the otherwise
  # mandatory Prowlarr round-trip to look the result up by guid.
  defp build_decision(pursuit, awaiting?, search_queries, cached, search_opts \\ [])

  defp build_decision(%Pursuit{} = pursuit, true = _awaiting?, search_queries, cached, search_opts) do
    case cached do
      %{decision_card: %ViewModels.DecisionCard{pursuit_id: id} = vm, decision_results_by_guid: results}
      when id == pursuit.id ->
        %{card: vm, results_by_guid: results}

      _ ->
        results = Acquisition.list_alternatives_for(pursuit, search_opts)

        card = %ViewModels.DecisionCard{
          pursuit_id: pursuit.id,
          prompt: @decision_prompt,
          alternatives: Enum.map(results, &search_result_to_alternative/1),
          loading?: false,
          search_queries: search_queries
        }

        %{card: card, results_by_guid: Map.new(results, &{&1.guid, &1})}
    end
  end

  defp build_decision(_pursuit, _awaiting?, _search_queries, _cached, _search_opts),
    do: %{card: nil, results_by_guid: %{}}

  defp search_result_to_alternative(result) do
    %Alternative{
      guid: result.guid,
      title: result.title,
      indexer: indexer_name(result),
      quality: quality_label(result),
      size_bytes: Map.get(result, :size_bytes),
      seeders: Map.get(result, :seeders),
      indexer_id: Map.get(result, :indexer_id)
    }
  end

  defp indexer_name(%{indexer: indexer}) when is_binary(indexer), do: indexer
  defp indexer_name(_), do: "Unknown"

  defp quality_label(%{quality: q}) when is_atom(q), do: MediaCentaur.Search.Quality.label(q)
  defp quality_label(_), do: nil

  defp load_history(socket) do
    rows = compute_history_rows(socket.assigns.history_filter, socket.assigns.history_search)
    assign(socket, history_rows: rows)
  end

  defp retry_terms(socket, []), do: socket.assigns.search_session

  defp retry_terms(_socket, terms) do
    session = SearchSession.retry_search_terms(terms)
    Enum.each(terms, fn term -> send(self(), {:run_search_one, term}) end)
    session
  end

  # ---------------------------------------------------------------------------
  # Grouped-compact-rows renderer — pattern-matches on the
  # `Logic.group_pursuit_rows/2` output. Lives on the parent so both
  # zones (Active Pursuits and History) share one render helper. Each
  # zone produces its own grouped list; the renderer doesn't know which
  # zone called it.
  # ---------------------------------------------------------------------------

  attr :entries, :list,
    required: true,
    doc:
      "Output of `Logic.group_pursuit_rows/2` — a mixed list of `{:single, PursuitRow.t()}` and `{:group, %{title, state, count, verb, severity, expanded?, vms}}` tagged tuples. Heterogeneous by design (the grouping helper interleaves singles and groups in input order); `:list` is the tightest type the component can declare."

  defp grouped_compact_rows(assigns) do
    ~H"""
    <%= for entry <- @entries do %>
      <%= case entry do %>
        <% {:single, vm} -> %>
          <PursuitRow.pursuit_row vm={vm} density={:compact} />
        <% {:group, data} -> %>
          <PursuitGroup.pursuit_group
            title={data.title}
            state={data.state}
            awaiting?={data.awaiting?}
            count={data.count}
            verb={data.verb}
            severity={data.severity}
            vms={data.vms}
            expanded?={data.expanded?}
          />
      <% end %>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Cancel-confirmation modal — kept on the parent because the
  # confirm/cancel events flip parent socket assigns (`pending_cancels`).
  # ---------------------------------------------------------------------------

  attr :cancel_confirm, :any,
    required: true,
    doc:
      "transient cancel-confirmation state — `nil` or a `%{id, title}` map. Heterogeneous nil-or-map shape; `:any` is intentional."

  defp cancel_confirmation(assigns) do
    ~H"""
    <.modal
      id="cancel-download-modal"
      open={!is_nil(@cancel_confirm)}
      dismiss={:ephemeral}
      on_close="cancel_download_cancel"
      size={:sm}
      panel_class="p-6"
      data-detail-mode={!is_nil(@cancel_confirm) && "modal"}
      data-dismiss-event="cancel_download_cancel"
      style="z-index: 60;"
    >
      <div :if={@cancel_confirm}>
        <h3 class="text-lg font-bold text-error">Cancel download?</h3>
        <p class="mt-2 text-sm text-base-content/70">
          The torrent and any downloaded files will be deleted from qBittorrent.
        </p>
        <div class="mt-3 rounded-lg bg-base-content/5 p-3 text-sm break-words">
          {@cancel_confirm.title}
        </div>
        <div class="mt-4 flex justify-end gap-2">
          <.button
            variant="dismiss"
            size="sm"
            phx-click="cancel_download_cancel"
            data-nav-item
            tabindex="0"
          >
            Keep
          </.button>
          <.button
            variant="danger"
            size="sm"
            phx-click="cancel_download_confirm"
            data-nav-item
            tabindex="0"
          >
            Cancel download
          </.button>
        </div>
      </div>
    </.modal>
    """
  end

  # Discard-confirmation modal — kept on the parent for the same reason
  # as cancel-confirmation: the confirm/cancel events flip parent socket
  # assigns, and discarding a solved-and-steered draft is destructive.

  attr :open, :boolean, required: true
  attr :board, MediaCentaur.Acquisition.ViewModels.PlanBoard, default: nil

  defp plan_discard_confirmation(assigns) do
    ~H"""
    <.modal
      id="plan-discard-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close="plan_discard_cancel"
      size={:sm}
      panel_class="p-6"
      data-detail-mode={@open && "modal"}
      data-dismiss-event="plan_discard_cancel"
      style="z-index: 60;"
    >
      <div :if={@open}>
        <h3 class="text-lg font-bold text-error">Discard plan?</h3>
        <p class="mt-2 text-sm text-base-content/70">
          The draft plan and any release choices you made will be lost. Nothing has been grabbed.
        </p>
        <div :if={@board} class="mt-3 rounded-lg bg-base-content/5 p-3 text-sm break-words">
          {@board.title}
        </div>
        <div class="mt-4 flex justify-end gap-2">
          <.button
            variant="dismiss"
            size="sm"
            phx-click="plan_discard_cancel"
            data-nav-item
            tabindex="0"
          >
            Keep
          </.button>
          <.button
            variant="danger"
            size="sm"
            phx-click="plan_discard_confirm"
            data-nav-item
            tabindex="0"
          >
            Discard plan
          </.button>
        </div>
      </div>
    </.modal>
    """
  end
end
