defmodule MediaCentaurWeb.IncomingLive do
  @moduledoc """
  The Incoming page at `/incoming` (DDR-015) — Upcoming and Downloads
  merged into one collection-growth destination. A single column with a
  density gradient, top to bottom:

  1. **Hero omnibox** (`data-nav-zone="omnibox"`) — the front door: TMDB
     media search feeding the plan/track flows, or Prowlarr release
     search (results render in the search zone below; the shelf recedes
     while release search owns the page).
  2. **Coming up agenda** (`data-nav-zone="coming_up_list"`) — one
     compact date-led row per tracked title, nearness-ordered, statuses
     via the shared `StatusPill` vocabulary; overflow grows in place
     ("Show all N").
  3. **Draft plans** (`data-nav-zone="drafts"`) — unapproved plan
     boards, resumable into the plan modal.
  4. **In flight** (`data-nav-zone="pursuits"`) — every live pursuit,
     paired at render time with its torrent(s) from the download-client
     queue. Refreshes live via PubSub + queue polls.
  5. **Recently landed** (`data-nav-zone="ledger"`) — THE history
     surface: a newest-first glimpse that expands in place ("View all")
     into the filtered archive (chips + search). One section, no
     sibling duplicate.
  6. **Other downloads** (`data-nav-zone="other_downloads"`) — client
     torrents that match no tracked pursuit — then the Storage section.

  No capability gate on mount: without Prowlarr the page renders
  forecast-only. Section honesty is enforced once, in
  `MediaCentaurWeb.IncomingLive.View` (the page's single composition
  point) — templates never re-check capabilities.

  See `MediaCentaur.Search.QueryExpander` for the supported brace
  syntax, `MediaCentaurWeb.IncomingLive.Logic` for search/group
  helpers, and `MediaCentaurWeb.IncomingLive.HistoryLogic` for the
  ledger/archive filter helpers.

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

  alias MediaCentaurWeb.IncomingLive.{
    HistoryLogic,
    Logic,
    OrphanQueue,
    Search,
    SearchSession
  }

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Item, UpcomingFeed}

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Acquisition.{PlanEvents, Plans, Targeting}
  alias MediaCentaurWeb.Components.Incoming.{Ledger, Shelf}
  alias MediaCentaurWeb.Components.ReleaseTracking.{Detail, Present, TitleDetail}
  alias MediaCentaurWeb.IncomingLive.MoviePreview
  alias MediaCentaurWeb.IncomingLive.View
  alias MediaCentaurWeb.IncomingLive.PlanLogic
  alias MediaCentaurWeb.HomeLive.Logic, as: HomeLogic

  alias MediaCentaur.Settings
  alias MediaCentaur.Storage

  alias MediaCentaur.Search.IndexerHealth

  alias MediaCentaurWeb.Components.Acquisition.{
    ConnectivityBadge,
    DownloadStorage,
    MediaOmnibox,
    MediaResults,
    NeedsAttention,
    PlanModal,
    PursuitGroup,
    PursuitModal,
    PursuitRow
  }

  @decision_prompt "Pick an alternative release."

  # Fast enough that the free-space number stays honest while grabs are
  # actively landing on disk. The probe is a handful of statvfs calls on an
  # owned async task, and the timer only exists while someone has this page
  # open — the faster cadence costs nothing when nobody is watching.
  # The ledger glimpse shows at most HistoryLogic's expanded cap (12); one
  # extra row lets `ledger_rows/2` know whether anything stays hidden without
  # reading the whole terminal-pursuit table on every mount and reload.
  @ledger_read_cap 13

  @storage_refresh_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    # No capability redirect: this page is the first acquisition surface
    # that renders without Prowlarr (forecast-only). Capability gating is
    # render-level, enforced once inside `View.build/1`. Forecast topics are
    # always live; acquisition topics only when there's an indexer to hear
    # from (re-checked in `:capabilities_changed` for mid-session setup).
    prowlarr? = Capabilities.prowlarr_ready?()

    if connected?(socket) do
      MediaCentaur.Library.subscribe()
      ReleaseTracking.subscribe()
      if prowlarr?, do: subscribe_acquisition()
    end

    today = Date.utc_today()

    {:ok,
     maybe_start_storage(
       assign(socket,
         loaded?: false,
         subscribed_acquisition?: prowlarr? and connected?(socket),
         today: today,
         detail: nil,
         shelf_expanded?: false,
         view: %View{shelf: %View.ShelfSection{}, ledger: %View.LedgerSection{}},
         grab_status_by_key: %{},
         auto_grab_default_mode: AutoGrabSettings.load().default_mode,
         ledger_expanded?: false,
         ledger_rows: [],
         loaded_history_params: nil,
         forecast_reload_timer: nil,
         storage_drives: [],
         search_health: IndexerHealth.cached(),
         page_backdrop: page_backdrop(),
         search_session: %SearchSession{},
         active_queue: [],
         queue_connectivity: :initializing,
         queue_last_success_at: nil,
         queue_loaded?: false,
         board_expanded_seasons: nil,
         cancel_confirm: nil,
         pending_cancels: %{},
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
         omnibox_scope: :all,
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
         plan_identity: nil,
         plan_artwork: nil,
         plan_drafts: []
       )
     )}
  end

  defp subscribe_acquisition do
    Acquisition.subscribe()
    Acquisition.subscribe_queue()
    SearchSession.subscribe()
  end

  defp subscribe_acquisition_once(socket) do
    if socket.assigns.subscribed_acquisition? or not connected?(socket) do
      socket
    else
      subscribe_acquisition()
      assign(socket, subscribed_acquisition?: true)
    end
  end

  # First-render data load — runs on BOTH the disconnected (static) and
  # connected renders so the first paint already carries the forecast, search
  # session, pursuit rows, and ledger, never an empty-state flash. Desktop
  # first-paint correctness (see AGENTS.md → LiveView callbacks): the reads
  # are all local, so there is no traffic-scaling reason to defer them. Do
  # not re-add a `connected?` gate. The `Acquisition.queue_state/0` read is
  # `:persistent_term` — microsecond — and safe without a client.
  defp ensure_loaded(socket) do
    if socket.assigns.loaded? do
      socket
    else
      socket
      |> assign_queue_from_state(Acquisition.queue_state())
      |> load_acquisition()
      |> build_view()
      |> assign(:loaded?, true)
    end
  end

  # Synchronous first-render load of the four initial reads (search
  # session, download-client capability, active pursuit rows, history
  # rows). All local; running them inline keeps the first paint correct.
  # Ambient page backdrop — same ETS-backed hero-candidate pool the
  # home/library pages draw from, in the downloads page's own slot so
  # no backdrop repeats across pages when the pool allows.
  # The activity card's "Open SABnzbd/qBittorrent" link on error states
  # — resolved here rather than in the pure status VM because it reads
  # live client config.
  defp pursuit_client_url(%{status: %{download: %{protocol: protocol}}})
       when protocol in [:torrent, :usenet], do: MediaCentaur.Downloads.client_web_url(protocol)

  defp pursuit_client_url(_detail), do: nil

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
    # Storage headroom answers "do I have room for this grab?" — without an
    # indexer nothing grabs, so the forecast-only page skips the df loop.
    if connected?(socket) and Capabilities.prowlarr_ready?() do
      Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
      start_async_storage(socket)
    else
      socket
    end
  end

  defp start_async_storage(socket) do
    socket
    |> start_async(:acquisition_storage, fn ->
      # Only drives a download can land on — a DB/image-cache-only drive can't
      # answer "do I have room for this grab?" (see DownloadStorage.media_dir_drives/1).
      DownloadStorage.media_dir_drives(Storage.measure_all())
    end)
    |> start_async(:indexer_health, fn ->
      # Two cheap Prowlarr reads (roster + back-offs) — the Needs attention
      # section's search card and the plan banner's honesty (UIDR-016).
      IndexerHealth.check()
    end)
  end

  # Acquisition reads only exist when an indexer is configured — without one
  # the empty mount defaults are already the honest state, and `View.build/1`
  # keeps the operational sections empty regardless.
  defp load_acquisition(socket) do
    if Capabilities.prowlarr_ready?() do
      session = SearchSession.current()

      assign(socket,
        search_session: session,
        # An active release-search session resumes in release mode — the
        # one-search-surface flip must not hide work in progress (UIDR-014).
        omnibox_mode: if(session.query != "" or session.groups != [], do: :release, else: :media),
        download_client_ready: Capabilities.download_client_ready?(),
        plan_drafts: load_drafts(),
        pursuit_rows: MediaCentaur.Acquisition.Pursuits.list_active_rows(),
        ledger_rows: Pursuits.list_rows(:all_terminal, limit: @ledger_read_cap),
        history_rows: compute_history_rows(socket.assigns.history_filter, socket.assigns.history_search),
        loaded_history_params: {socket.assigns.history_filter, socket.assigns.history_search}
      )
    else
      socket
    end
  end

  # The ledger reloads with the active rows — a pursuit leaving the active
  # list is exactly the moment it enters the ledger.
  defp load_pursuit_rows(socket) do
    assign(socket,
      pursuit_rows: MediaCentaur.Acquisition.Pursuits.list_active_rows(),
      ledger_rows: Pursuits.list_rows(:all_terminal, limit: @ledger_read_cap)
    )
  end

  # Rebuild the composed page view from current assigns + fresh forecast
  # reads. Every mutation of a View input (pursuit rows, drafts, ledger
  # state, releases) funnels through here — one composition point, one
  # rebuild path.
  defp build_view(socket) do
    releases = forecast_releases()
    acquisition? = Capabilities.acquisition_ready?()
    default_mode = AutoGrabSettings.load().default_mode
    grab = grab_status_by_key(releases, acquisition?)

    view =
      View.build(%{
        releases: releases,
        watching_items: ReleaseTracking.list_watching_items(),
        pursuit_rows: socket.assigns.pursuit_rows,
        ledger_rows: socket.assigns.ledger_rows,
        drafts: socket.assigns.plan_drafts,
        today: socket.assigns.today,
        prowlarr_ready?: Capabilities.prowlarr_ready?(),
        acquisition_ready?: acquisition?,
        auto_grab_default_mode: default_mode,
        grab_status_by_key: grab,
        ledger_expanded?: socket.assigns.ledger_expanded?,
        shelf_expanded?: socket.assigns.shelf_expanded?
      })

    assign(socket,
      view: view,
      grab_status_by_key: grab,
      auto_grab_default_mode: default_mode
    )
  end

  defp forecast_releases do
    %{upcoming: upcoming, released: released} = ReleaseTracking.list_releases()
    upcoming ++ released
  end

  # `%{release_key => %{pursuit_id}}` for releases under an ACTIVE pursuit —
  # the input the feed needs to mark `:under_pursuit` and the shelf needs to
  # anchor a card to its torrent row.
  defp grab_status_by_key(_releases, false), do: %{}

  defp grab_status_by_key(releases, true) do
    releases
    |> Enum.map(&UpcomingFeed.release_key/1)
    |> Enum.uniq()
    |> Acquisition.statuses_for_releases()
    # `statuses_for_releases/1` also returns cancelled/complete pursuits; only
    # an ACTIVE pursuit means a release is genuinely being grabbed right now.
    |> Enum.filter(fn {_key, {pursuit, _target}} -> pursuit.state == "active" end)
    |> Map.new(fn {key, {pursuit, _target}} -> {key, %{pursuit_id: pursuit.id}} end)
  end

  # --- Per-title detail (the forecast slide-over) ---

  defp build_detail(socket, item_id) do
    case ReleaseTracking.get_item(item_id) do
      nil ->
        nil

      item ->
        acquisition? = Capabilities.acquisition_ready?()
        default_mode = socket.assigns.auto_grab_default_mode

        releases =
          item_id
          |> ReleaseTracking.list_releases_for_item()
          |> Enum.map(&%{&1 | item: item})

        context = %{
          today: socket.assigns.today,
          acquisition_ready?: acquisition?,
          auto_grab_default_mode: default_mode,
          grab_status_by_key: socket.assigns.grab_status_by_key
        }

        feed = UpcomingFeed.build(releases, context)

        %Detail{
          item_id: item.id,
          name: item.name,
          media_type: item.media_type,
          backdrop_path: item.backdrop_path,
          acquisition?: acquisition?,
          auto_grab: Present.auto_grab_summary(item.auto_grab_mode, default_mode, acquisition?),
          timeline: flatten_feed(feed),
          activity: build_activity(item_id)
        }
    end
  end

  defp flatten_feed(%UpcomingFeed{buckets: buckets, unscheduled: unscheduled}) do
    Enum.flat_map(UpcomingFeed.bucket_order(), &Map.get(buckets, &1, [])) ++ unscheduled
  end

  defp build_activity(item_id) do
    item_id
    |> ReleaseTracking.list_events_for_item(8)
    |> Enum.map(&%{text: &1.description, at: MediaCentaur.Format.relative_ago(&1.inserted_at)})
  end

  # A media pick on the forecast-only page: track the title (movies grab no
  # scope; shows start from the last library episode) and mark the dropdown
  # row so the pick reads as done.
  defp track_picked_result(socket, tmdb_id) do
    case Enum.find(socket.assigns.omnibox_results, &(to_string(&1.tmdb_id) == to_string(tmdb_id))) do
      nil ->
        socket

      result ->
        scope =
          case result.media_type do
            :movie ->
              %{}

            :tv_series ->
              {last_season, last_episode} = ReleaseTracking.find_last_library_episode(nil)
              %{start_season: last_season, start_episode: last_episode}
          end

        ReleaseTracking.track_from_search_async(
          %{
            tmdb_id: result.tmdb_id,
            media_type: result.media_type,
            name: result.name,
            poster_path: result.poster_path
          },
          scope
        )

        assign(socket,
          omnibox_results:
            Enum.map(socket.assigns.omnibox_results, fn row ->
              if to_string(row.tmdb_id) == to_string(tmdb_id), do: %{row | tracked?: true}, else: row
            end)
        )
    end
  end

  # The plan modal's current identity, whichever stage holds it —
  # `{tmdb_id :: integer, media_type, name}` or nil when nothing usable.
  defp tracked_plan_identity(%{plan_movie: %MoviePreview{} = movie}) when movie.title != nil do
    case Integer.parse(movie.tmdb_id) do
      {tmdb_id, ""} -> {tmdb_id, :movie, movie.title}
      _other -> nil
    end
  end

  defp tracked_plan_identity(%{plan_selection: %Targeting.Selection{} = selection}) do
    case Integer.parse(selection.tmdb_id) do
      {tmdb_id, ""} -> {tmdb_id, :tv_series, selection.title}
      _other -> nil
    end
  end

  defp tracked_plan_identity(_assigns), do: nil

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

  # `?search=…` / `?filter=…` restore the archive's filter state (the
  # pursuit-modal path helper always carries them). `?prowlarr_search=…`
  # pre-fills the release-search box and auto-fires the search.
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

  # On a modal patch (loaded?=true) leave the disclosure as the user left it.
  defp maybe_open_history(socket, _params, true), do: socket

  # On a fresh load, the persisted preference is the sole source of truth —
  # never the URL's filter/search state. `build_pursuit_modal_path/2` always
  # carries `filter=failed`, so keying off it (as this used to) popped History
  # open whenever you returned to a pursuit-modal URL. There are no genuine
  # `?filter=`/`?search=` deep-links, so nothing in the URL should
  # override the pref. Defaults collapsed.
  defp maybe_open_history(socket, _params, false) do
    assign(socket, history_open?: history_open_pref())
  end

  # First load: `ensure_loaded/1` already computed history_rows with the
  # URL-snapshot filter values. Mid-session param changes fall through to
  # the sync reload below.
  defp maybe_load_history(socket, false), do: socket

  defp maybe_load_history(socket, true) do
    # Pursuit-modal patches carry filter/search params too — only a real
    # change earns the full terminal-table re-read.
    if {socket.assigns.history_filter, socket.assigns.history_search} ==
         socket.assigns[:loaded_history_params] do
      socket
    else
      load_history(socket)
    end
  end

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

  # Builds a path back to `/incoming` preserving the archive filter/search
  # so the modal open/close doesn't reset the user's surrounding view.
  # Overrides are merged last and `nil`-valued keys remove the param.
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
      [] -> "/incoming"
      params -> "/incoming?" <> URI.encode_query(params)
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

  defp shelf_progress(download_cards) do
    for %PursuitWithDownload{row: row, download: download} <- download_cards,
        download && download.progress_pct,
        into: %{} do
      {row.id, round(download.progress_pct)}
    end
  end

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
    {paired_rows, orphan_queue} = QueueMatcher.match(assigns.view.in_flight, assigns.active_queue)

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
      # The shelf recedes only while a search actually owns the page (an
      # active media query, or a release query/results) — a bare mode
      # flip keeps the forecast in view.
      |> Phoenix.Component.assign(
        :shelf_visible?,
        Logic.shelf_visible?(assigns.omnibox_mode, assigns.omnibox_query, assigns.search_session)
      )
      # Live percentages ride the same render-time pairing: the paired
      # downloads stamp their progress onto in-pursuit shelf cards, so the
      # shelf hairline tracks the torrent without rebuilding the View.
      |> Phoenix.Component.assign(
        :shelf_cards,
        View.with_progress(assigns.view.shelf.cards, shelf_progress(download_cards))
      )
      # The plan modal's cinematic shell — one identity following the
      # request through every stage (UIDR-014).
      |> Phoenix.Component.assign(
        :plan_backdrop_url,
        PlanLogic.shell_backdrop_url(assigns.plan_stage, %{
          identity: assigns.plan_identity,
          selection: assigns.plan_selection,
          movie: assigns.plan_movie,
          artwork: assigns.plan_artwork
        })
      )

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/incoming"
      full_width
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <:overlays>
        <.cancel_confirmation cancel_confirm={@cancel_confirm} />
        <.plan_discard_confirmation open={@plan_discard_confirm?} board={@plan_board} />
        <PlanModal.plan_modal
          open={@plan_param != nil}
          stage={@plan_stage}
          backdrop_url={@plan_backdrop_url}
          identity={@plan_identity}
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
          search_health={@search_health}
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
          client_url={pursuit_client_url(@pursuit_detail)}
          not_found?={(@pursuit_detail && @pursuit_detail.not_found?) || false}
        />
        <TitleDetail.title_detail :if={@detail} detail={@detail} today={@today} />
      </:overlays>
      <%!-- data-nav-default-zone names the LAYOUT KEY in input config.js
            (like `library`/`home`), not a context within it — the nav graph
            is built from this value. --%>
      <div class="relative" data-page-behavior="incoming" data-nav-default-zone="incoming">
        <%!-- Backdrop trial: the ambient movie image (`.page-atmosphere`
              band fed by @page_backdrop) is removed while we evaluate the
              page without it. The dark side/bottom scrim stays — it's a
              pure gradient, so it needs no image and keeps the page's
              depth. --%>
        <div class="page-side-dim" aria-hidden="true"></div>

        <%!-- Same header recipe as the library page (left-aligned, text-3xl,
              one muted subtitle line) so moving between pages doesn't shift
              the title around.

              Width model: the page is full-bleed (like home/library); the
              content column runs max-w-6xl — one axis, density thinning
              downward: hero search, the Coming-up agenda list, operational
              in-flight band, then the bookkeeping (ledger, History
              disclosure, other downloads) at the bottom. --%>
        <%!-- Centered, not left-anchored: on media-center-wide screens a
              left-hugging column strands the right half of the display and
              shoves the (input-anchored) search overlay into the sidebar. --%>
        <div class="relative z-[1] max-w-6xl mx-auto space-y-8">
          <header>
            <h1 class="text-3xl font-bold tracking-tight">Incoming</h1>
            <p class="mt-1 text-sm text-base-content/60">
              Add to your library, and see what's on the way.
            </p>
          </header>

          <MediaOmnibox.media_omnibox
            hero
            release_mode_available={@prowlarr_ready}
            prompt={
              if @prowlarr_ready,
                do: "What would you like to add?",
                else: "What would you like to track?"
            }
            mode={@omnibox_mode}
            query={@omnibox_query}
            session={@search_session}
            any_loading?={@any_loading?}
          />

          <%!-- Both search modes answer flat, in the page (UIDR-014):
                media results here, release results in the search zone
                below. No floating overlays — clearing the query is the
                one dismissal. --%>
          <MediaResults.media_results
            :if={@omnibox_mode == :media}
            query={@omnibox_query}
            results={@omnibox_results}
            searching?={@omnibox_searching?}
            release_mode_available={@prowlarr_ready}
            scope={@omnibox_scope}
          />

          <Search.search_zone
            :if={@omnibox_mode == :release}
            session={@search_session}
            any_loading?={@any_loading?}
            timeout_terms={@timeout_terms}
          />

          <%!-- The shelf recedes while a search owns the page — clearing
                the query restores it. A bare mode flip (empty box) keeps
                the forecast visible. --%>
          <Shelf.shelf
            :if={@shelf_visible?}
            cards={@shelf_cards}
            overflow_count={@view.shelf.overflow_count}
            stragglers={@view.shelf.stragglers}
          />

          <section :if={@view.drafts != []} data-nav-zone="drafts" class="space-y-3">
            <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Draft plans
            </h2>
            <div class="grid grid-cols-1 gap-2">
              <%!-- The whole banner is the click target — resuming the
                    plan is the row's only verb, so it needs no inner
                    button to hunt for. --%>
              <button
                :for={draft <- @view.drafts}
                type="button"
                id={"plan-draft-#{draft.id}"}
                class="identity-banner flex items-center gap-3 px-4 py-3 w-full text-left cursor-pointer transition-[filter] hover:brightness-110"
                style={"--banner-hue: #{banner_hue(draft.title)}"}
                phx-click="resume_plan"
                phx-value-id={draft.id}
                data-nav-item
                tabindex="0"
              >
                <%!-- Cached tracking artwork wears the banner; the hue
                      gradient stays underneath as the no-artwork look.
                      Same left-weighted scrim recipe as the banner's own
                      background so the title stays legible. --%>
                <img
                  :if={draft.backdrop_url}
                  src={draft.backdrop_url}
                  alt=""
                  aria-hidden="true"
                  class="absolute inset-0 h-full w-full object-cover pointer-events-none"
                  loading="eager"
                  decoding="sync"
                />
                <div
                  :if={draft.backdrop_url}
                  aria-hidden="true"
                  class="absolute inset-0 pointer-events-none bg-gradient-to-r from-[oklch(13%_0.02_264/0.92)] via-[oklch(13%_0.02_264/0.72)] to-[oklch(13%_0.02_264/0.30)]"
                >
                </div>
                <span class="absolute top-2 left-3 text-[10px] uppercase tracking-wider text-base-content/40 z-[1]">
                  Draft
                </span>
                <div class="min-w-0 flex-1 pt-3 relative z-[1]">
                  <p class="identity-logotype truncate text-base leading-tight">{draft.title}</p>
                  <p class="text-xs text-info/90 mt-1 [text-shadow:0_1px_3px_oklch(0%_0_0/0.5)]">
                    {if draft.status == "planning",
                      do: "Planning…",
                      else: "Plan ready — review and approve"}
                  </p>
                </div>
                <.icon
                  name="hero-chevron-right-mini"
                  class="size-5 flex-shrink-0 text-base-content/40 relative z-[1]"
                />
              </button>
            </div>
          </section>

          <p
            :if={@prowlarr_ready and !@download_client_ready}
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
                In flight
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

          <Ledger.ledger
            rows={@view.ledger.rows}
            hidden_count={@view.ledger.hidden_count}
            expanded={@view.ledger.expanded?}
            archive_open?={@history_open? and @prowlarr_ready}
            filter={@history_filter}
            search={@history_search}
            archive_empty?={@history_rows == []}
            storage_drives={if(@storage_mode == :calm, do: @storage_drives, else: [])}
          >
            <:archive>
              <.grouped_compact_rows entries={@history_compact} />
            </:archive>
          </Ledger.ledger>

          <OrphanQueue.orphan_zone items={@orphan_queue} />

          <%!-- Needs attention is bookkeeping — it closes the page, never
                leads it (UIDR-016). Calm free space stays the ledger's foot
                line; cards only render when storage escalates (low space /
                multiple drives) or search health degrades. --%>
          <NeedsAttention.needs_attention
            :if={NeedsAttention.visible?(@storage_mode, @search_health)}
            drives={if(@storage_mode == :card, do: @storage_drives, else: [])}
            search_health={@search_health}
          />
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
           plan_drafts: load_drafts(),
           omnibox_query: "",
           omnibox_results: [],
           omnibox_searching?: false,
           omnibox_searched: nil,
           omnibox_scope: :all
         )
         |> build_view()
         |> push_patch(to: "/incoming?plan=#{plan.id}")}

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
       |> assign(plan_drafts: load_drafts())
       |> build_view()
       |> put_flash(:info, "Plan discarded.")
       |> push_patch(to: "/incoming")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not discard the plan.")}
    end
  end

  def handle_event("close_plan", _params, socket) do
    {:noreply, push_patch(socket, to: "/incoming")}
  end

  def handle_event("resume_plan", %{"id" => plan_id}, socket) do
    {:noreply, push_patch(socket, to: "/incoming?plan=#{plan_id}")}
  end

  # ---------------------------------------------------------------------------
  # Omnibox (UIDR-014) — one search surface, two modes.
  # ---------------------------------------------------------------------------

  def handle_event("omnibox_change", %{"query" => query}, socket) do
    trimmed = String.trim(query)
    socket = assign(socket, omnibox_query: query)

    cond do
      String.length(trimmed) < 2 ->
        {:noreply,
         assign(socket,
           omnibox_results: [],
           omnibox_searching?: false,
           omnibox_searched: nil
         )}

      # TMDB citizenship: a re-fire of the same effective query (trailing
      # space, blur/focus echo) never searches again — each debounce fire
      # costs one API call (multi), up to three when the query carries a
      # trailing year (movie + tv, plus the year-less fallback).
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

  # The flat results section's one reset — clearing the query is the
  # only dismissal (results are page content, not an overlay). The
  # refocus puts pointer users straight into the next search; the
  # client-side input wipe rides the button's JS.dispatch (see
  # MediaResults).
  def handle_event("omnibox_clear", _params, socket) do
    {:noreply,
     socket
     |> assign(
       omnibox_query: "",
       omnibox_results: [],
       omnibox_searching?: false,
       omnibox_searched: nil,
       omnibox_scope: :all
     )
     |> push_event("omnibox:refocus", %{})}
  end

  # The upcoming/released chips between the box and the rows. Clicking
  # the active chip toggles back to everything; the scope survives query
  # refinements (the chips stay visible, so the state stays legible) and
  # resets with the query.
  def handle_event("omnibox_scope", %{"scope" => scope}, socket) when scope in ~w(upcoming released) do
    scope = String.to_existing_atom(scope)
    current = socket.assigns.omnibox_scope

    {:noreply, assign(socket, omnibox_scope: if(current == scope, do: :all, else: scope))}
  end

  def handle_event("omnibox_mode", %{"mode" => mode}, socket) when mode in ~w(media release) do
    # Release mode does not exist without an indexer — ignore a stale flip
    # (the hint hides the control, but a lagging DOM can still fire it).
    if mode == "release" and not Capabilities.prowlarr_ready?() do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         omnibox_mode: String.to_existing_atom(mode),
         omnibox_results: [],
         omnibox_query: "",
         omnibox_searching?: false,
         omnibox_searched: nil,
         omnibox_scope: :all
       )}
    end
  end

  def handle_event("omnibox_pick", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    picked =
      Enum.find(socket.assigns.omnibox_results, fn result ->
        to_string(result.tmdb_id) == to_string(tmdb_id) &&
          to_string(result.media_type) == media_type
      end)

    cond do
      not Capabilities.prowlarr_ready?() ->
        # Forecast-only page: the hero promised tracking, so a pick tracks —
        # never the plan (grab) flow. Same shape the track modal uses.
        {:noreply, track_picked_result(socket, tmdb_id)}

      picked && MediaResults.release_status(picked, Date.utc_today()) == :upcoming ->
        # An unreleased title has nothing to grab — the row's verb says
        # "Track release" and the pick does exactly that, in place.
        {:noreply, track_picked_result(socket, tmdb_id)}

      true ->
        plan_type = if media_type == "movie", do: "movie", else: "tv"

        # Carry the picked result into the plan flow — the modal opens
        # already wearing its identity instead of a gray loading box.
        {:noreply,
         socket
         |> assign(plan_identity: picked)
         |> push_patch(to: "/incoming?plan=new&tmdb_id=#{tmdb_id}&tmdb_type=#{plan_type}")}
    end
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

  # --- Ledger / calendar disclosures ---

  def handle_event("expand_ledger", _params, socket) do
    {:noreply, socket |> assign(ledger_expanded?: true) |> build_view()}
  end

  def handle_event("expand_shelf", _params, socket) do
    {:noreply, socket |> assign(shelf_expanded?: true) |> build_view()}
  end

  # --- Forecast detail / tracking events ---

  def handle_event("select_event", %{"item-id" => item_id}, socket) do
    {:noreply, assign(socket, detail: build_detail(socket, item_id))}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, detail: nil)}
  end

  def handle_event("toggle_auto_grab", %{"item-id" => item_id}, socket) do
    with %Item{} = item <- ReleaseTracking.get_item(item_id) do
      default = socket.assigns.auto_grab_default_mode

      summary =
        Present.auto_grab_summary(item.auto_grab_mode, default, Capabilities.acquisition_ready?())

      ReleaseTracking.update_auto_grab(item, %{
        auto_grab_mode: if(summary.on?, do: "off", else: "all_releases")
      })
    end

    socket = build_view(socket)
    {:noreply, assign(socket, detail: build_detail(socket, item_id))}
  end

  def handle_event("stop_tracking", %{"item-id" => item_id}, socket) do
    case ReleaseTracking.get_item(item_id) do
      nil ->
        {:noreply, socket}

      item ->
        ReleaseTracking.create_event!(%{
          item_id: item.id,
          item_name: item.name,
          event_type: :stopped_tracking,
          description: "Stopped tracking #{item.name}"
        })

        ReleaseTracking.delete_item(item)

        {:noreply,
         socket
         |> assign(detail: nil)
         |> build_view()
         |> put_flash(:info, "Stopped tracking #{item.name}")}
    end
  end

  # Track without grabbing, from inside the plan modal — the TV picker's
  # "Track only" and the movie confirm's "Track release". TV tracks all
  # upcoming episodes (the back catalog is exactly what the open picker
  # grabs); the async task and its TMDB enrichment are ReleaseTracking's.
  def handle_event("plan_track_only", _params, socket) do
    case tracked_plan_identity(socket.assigns) do
      nil ->
        {:noreply, socket}

      {tmdb_id, media_type, name} ->
        scope = if media_type == :tv_series, do: %{start_season: 0, start_episode: 0}, else: %{}

        ReleaseTracking.track_from_search_async(
          %{tmdb_id: tmdb_id, media_type: media_type, name: name, poster_path: nil},
          scope
        )

        {:noreply,
         socket
         |> put_flash(:info, "Tracking #{name} — it will appear under Coming up.")
         |> push_patch(to: "/incoming")}
    end
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
                  header.search_queries,
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
    prowlarr? = Capabilities.prowlarr_ready?()

    socket =
      cond do
        prowlarr? and not socket.assigns.subscribed_acquisition? ->
          # Prowlarr just appeared mid-session: we never subscribed to
          # acquisition topics on mount — do it now, load the acquisition
          # state, and ping QueueMonitor so the queue populates without
          # waiting for the idle 30 s cadence.
          Acquisition.poll_queue_now()

          socket
          |> subscribe_acquisition_once()
          |> load_acquisition()
          |> assign(download_client_ready: Capabilities.download_client_ready?())

        prowlarr? ->
          # Some other capability changed (a TMDB test, the download client):
          # refresh the client flag and nudge the queue, but do NOT re-run
          # load_acquisition — it recomputes omnibox_mode from the session
          # and would snap a user out of a manually chosen mode.
          Acquisition.poll_queue_now()
          assign(socket, download_client_ready: Capabilities.download_client_ready?())

        true ->
          socket
      end

    {:noreply, build_view(socket)}
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

  # Terminal transitions also move pursuits from the active list into the
  # ledger — refresh both projections, then recompose.
  def handle_info(:reload_history, socket) do
    {:noreply, socket |> load_history() |> load_pursuit_rows() |> build_view()}
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
          |> assign(plan_drafts: load_drafts())
          |> build_view()
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
    {:noreply, socket |> load_pursuit_rows() |> build_view()}
  end

  # --- Forecast (shelf / detail / calendar / track modal) ---

  def handle_info({:releases_updated, _item_ids}, socket) do
    {:noreply, debounce(socket, :forecast_reload_timer, :reload_forecast, 500)}
  end

  def handle_info({:entities_changed, %{entity_ids: _ids}}, socket) do
    {:noreply, debounce(socket, :forecast_reload_timer, :reload_forecast, 500)}
  end

  def handle_info(:reload_forecast, socket) do
    {:noreply, build_view(socket)}
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

  def handle_async({:plan_artwork, plan_id}, {:ok, urls}, socket) do
    if socket.assigns.plan_param == plan_id do
      {:noreply, assign(socket, plan_artwork: urls)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:plan_artwork, _plan_id}, {:exit, reason}, socket) do
    Log.warning(:acquisition, "plan artwork fetch crashed — #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async(:plan_approve, {:ok, outcome}, socket) do
    socket = assign(socket, plan_approving?: false)

    case outcome do
      {:ok, committed} ->
        {:noreply,
         socket
         |> assign(plan_drafts: load_drafts())
         |> build_view()
         |> put_flash(:info, "Pursuit started.")
         |> push_patch(to: "/incoming?selected=#{committed.pursuit_id}")}

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
      # One TMDB page, relevance-ranked — the dropdown scrolls; depth
      # past 20 is a query-refinement problem, not a pagination one.
      rows = Enum.take(results, 20)

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

  def handle_async(:indexer_health, {:ok, health}, socket) do
    {:noreply, assign(socket, search_health: health)}
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

    if recipe.type == :tmdb and recipe.tmdb_id != nil and is_nil(header.backdrop_url) and
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
            header.search_queries,
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
          build_decision(pursuit, header.awaiting_decision?, header.search_queries, nil)

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

  # Draft rows carry their identity artwork when release tracking's local
  # cache has it (`Artwork.resolve` — DB + disk only, no network); the
  # synthetic hue gradient stays the fallback.
  defp load_drafts do
    Enum.map(Plans.list_drafts(), fn plan ->
      %{
        id: plan.id,
        title: plan.title,
        status: plan.status,
        backdrop_url: Acquisition.Artwork.resolve(plan.tmdb_id, plan.tmdb_type).backdrop_url
      }
    end)
  end

  defp apply_plan_modal_params(socket, params) do
    case Map.get(params, "plan") do
      nil ->
        socket
        # Closing the plan modal hands the page back to searching: refocus
        # the omnibox (client-side, pointer users only — see the
        # `omnibox:refocus` listener in app.js; keyboard/gamepad focus is
        # the input system's, ADR-053).
        |> then(fn socket ->
          if socket.assigns.plan_param, do: push_event(socket, "omnibox:refocus", %{}), else: socket
        end)
        |> assign(
          plan_param: nil,
          plan_selection: nil,
          plan_movie: nil,
          plan_board: nil,
          plan_descent: nil,
          plan_alternatives: nil,
          plan_error: nil,
          plan_discard_confirm?: false,
          plan_identity: nil,
          plan_artwork: nil
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
        plan_error: nil,
        plan_identity: matching_plan_identity(socket, tmdb_id, tmdb_type),
        plan_artwork: nil
      )
      |> start_async(:plan_targeting, fn -> load_targeting(tmdb_id, tmdb_type) end)
    end
  end

  defp open_plan_targeting(socket, _params) do
    assign(socket, plan_param: nil, plan_stage: :error, plan_error: "Malformed plan link.")
  end

  # The picked search result survives into the loading stage only when it
  # actually is this plan's title — a URL-driven open (refresh, shared
  # link) has nothing in hand and gets the scrim-only shell.
  defp matching_plan_identity(socket, tmdb_id, tmdb_type) do
    identity = socket.assigns[:plan_identity]
    wanted_type = if tmdb_type == "movie", do: :movie, else: :tv_series

    if identity && to_string(identity.tmdb_id) == to_string(tmdb_id) &&
         identity.media_type == wanted_type do
      identity
    end
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

        {:movie, PlanLogic.movie_preview(movie, in_library?)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp open_plan_board(socket, plan_id) do
    case Plans.get(plan_id) do
      {:ok, plan} ->
        board = Plans.board_for(plan)
        socket = maybe_load_plan_artwork(socket, plan_id, plan)

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

  # The board's identity artwork — release tracking's local cache first
  # (same store the pursuit modal reads), the network `Artwork.ensure`
  # kicked off-process only on a fresh open with an empty cache, mirroring
  # `maybe_fetch_artwork/2` for pursuits.
  defp maybe_load_plan_artwork(socket, plan_id, plan) do
    if socket.assigns.plan_param == plan_id do
      socket
    else
      artwork = Acquisition.Artwork.resolve(plan.tmdb_id, plan.tmdb_type)
      socket = assign(socket, plan_artwork: artwork)

      if is_nil(artwork.backdrop_url) and Capabilities.tmdb_ready?() do
        start_async(socket, {:plan_artwork, plan_id}, fn ->
          Acquisition.Artwork.ensure(plan.tmdb_id, plan.tmdb_type)
        end)
      else
        socket
      end
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
      socket
      |> assign(:search_health, IndexerHealth.cached())
      |> open_plan_board(plan_id)
    else
      socket
    end
  end

  defp maybe_note_plan_activity(socket, %PlanEvents.SearchActivity{} = activity) do
    if socket.assigns.plan_param == activity.plan_id do
      # A zero-result live search just refreshed the IndexerHealth cache
      # (Corpus disambiguates empty-vs-blind at search time, UIDR-016) —
      # re-read it so the ticker and the gap banner speak from the same
      # moment-of-truth observation.
      search_health = IndexerHealth.cached()

      assign(socket,
        plan_last_activity: PlanLogic.search_activity_line(activity, search_health),
        search_health: search_health
      )
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

    assign(socket,
      history_rows: rows,
      loaded_history_params: {socket.assigns.history_filter, socket.assigns.history_search}
    )
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
