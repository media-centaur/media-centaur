defmodule MediaCentaurWeb.AcquisitionLive do
  @moduledoc """
  Unified Downloads page at `/download`. Three stacked zones:

  1. **Active queue** (top, `data-nav-zone="queue"`) — live torrent
     activity from the configured download client. Polled every 5s.
  2. **Activity** (middle, `data-nav-zone="activity"`) — every
     `acquisition_grabs` row, manual + auto. Filter chips, title
     search, cancel + re-arm actions. Refreshes live via PubSub.
  3. **Manual search** (bottom, `data-nav-zone="search"`) — Prowlarr
     brace-expansion search, grouped results, batch grab. Successful
     grabs flow through `Acquisition.grab/2` which inserts a
     `manual`-origin row in the activity zone above.

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
      Acquisition.subscribe_search() # acquisition:search   → search session

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
  alias MediaCentaur.Acquisition.ViewModels.{Alternative, PursuitWithDownload}
  alias MediaCentaur.Capabilities
  alias MediaCentaurWeb.AcquisitionLive.{History, HistoryLogic, Logic, OrphanQueue, Search}

  alias MediaCentaurWeb.Components.Acquisition.{
    PursuitGroup,
    PursuitModal,
    PursuitRow,
    QueueStatusBadge
  }

  @decision_prompt "Pick an alternative release."

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
        Acquisition.subscribe_search()
      end

      {:ok,
       assign(socket,
         loaded?: false,
         search_session: %MediaCentaur.Search.SearchSession{},
         active_queue: [],
         queue_status: :initializing,
         queue_loaded?: false,
         cancel_confirm: nil,
         pending_cancels: %{},
         download_client_ready: false,
         history_filter: :failed,
         history_search: "",
         history_rows: [],
         pursuit_rows: [],
         expanded_pursuit_groups: MapSet.new(),
         pursuits_reload_timer: nil,
         reload_timer: nil,
         selected_pursuit_id: nil,
         pursuit_detail: nil
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
  defp load_acquisition(socket) do
    assign(socket,
      search_session: Acquisition.current_search_session(),
      download_client_ready: Capabilities.download_client_ready?(),
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
  # The 1500 ms cadence is the watched cadence — the QueueMonitor uses
  # that whenever this LiveView is subscribed, so the staleness
  # thresholds match what the user actually experiences here.
  @watched_cadence_ms 1_500

  defp assign_queue_from_state(socket, %MediaCentaur.Downloads.QueueState{} = state) do
    active = Enum.reject(state.items, &(&1.state == :completed))

    {visible, pending_cancels} =
      Logic.apply_pending_cancels(
        active,
        socket.assigns.pending_cancels,
        System.monotonic_time(:second)
      )

    status = MediaCentaur.Downloads.QueueStatus.derive(state, @watched_cadence_ms)

    assign(socket,
      active_queue: visible,
      queue_status: status,
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
      |> ensure_loaded()
      |> maybe_load_history(was_loaded?)
      |> apply_pursuit_modal_params(params)
      |> maybe_trigger_prowlarr_search(Map.get(params, "prowlarr_search"))

    {:noreply, socket}
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
      |> load_pursuit_detail()
    end
  end

  defp apply_pursuit_modal_params(socket, _params) do
    if socket.assigns.selected_pursuit_id == nil do
      socket
    else
      assign(socket, selected_pursuit_id: nil, pursuit_detail: nil)
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
        case Acquisition.start_search(trimmed) do
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
      Enum.split_with(paired_rows, fn %PursuitWithDownload{download: d} -> not is_nil(d) end)

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
      |> Phoenix.Component.assign(:telemetry_age, Logic.telemetry_age_label(assigns.queue_status))

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/download"
      acquisition_ready={@acquisition_ready}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
    >
      <:overlays>
        <.cancel_confirmation cancel_confirm={@cancel_confirm} />
        <PursuitModal.pursuit_modal
          open={@selected_pursuit_id != nil}
          pursuit_id={@selected_pursuit_id}
          header={@pursuit_detail && @pursuit_detail.header}
          status={@pursuit_detail && @pursuit_detail.status}
          timeline={@pursuit_detail && @pursuit_detail.timeline}
          decision_card={@pursuit_detail && @pursuit_detail.decision_card}
          not_found?={(@pursuit_detail && @pursuit_detail.not_found?) || false}
        />
      </:overlays>
      <div
        data-page-behavior="download"
        data-nav-default-zone="pursuits"
        class="max-w-4xl mx-auto space-y-6 py-6"
      >
        <h1 class="text-2xl font-bold">Downloads</h1>

        <p
          :if={!@download_client_ready}
          class="glass-surface rounded-xl px-4 py-3 text-center text-sm text-base-content/50"
        >
          Connect a download client in
          <.link navigate="/settings?section=acquisition" class="link link-primary">Settings</.link>
          to see live torrent activity under each pursuit.
        </p>

        <section :if={@paired_rows != []} data-nav-zone="pursuits" class="space-y-3">
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Active pursuits
            </h2>
            <div :if={@download_client_ready} class="flex items-center gap-2">
              <QueueStatusBadge.queue_status_badge status={@queue_status} />
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
                %PursuitWithDownload{row: row, download: download, queue_item_id: qid} <-
                  @download_cards
              }
              vm={row}
              download={download}
              queue_item_id={qid}
              telemetry_age={@telemetry_age}
            />
            <.grouped_compact_rows entries={@active_compact} />
          </div>
        </section>

        <section
          :if={@paired_rows == [] && @loaded? && @download_client_ready}
          class="glass-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/40"
        >
          No active pursuits.
        </section>

        <History.history_zone
          empty?={@history_rows == []}
          filter={@history_filter}
          search={@history_search}
        >
          <.grouped_compact_rows entries={@history_compact} />
        </History.history_zone>

        <OrphanQueue.orphan_zone items={@orphan_queue} />

        <Search.search_zone
          session={@search_session}
          any_loading?={@any_loading?}
          timeout_terms={@timeout_terms}
        />
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("query_change", %{"query" => query}, socket) do
    session = Acquisition.set_query_preview(query)
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_event("submit_search", %{"query" => query}, socket) do
    if socket.assigns.search_session.grabbing? do
      {:noreply, socket}
    else
      session = Acquisition.set_query_preview(query)

      session =
        case Acquisition.start_search(query) do
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

  def handle_event("toggle_group", %{"term" => term}, socket) do
    session = Acquisition.toggle_group(term)
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_event("select_result", %{"term" => term, "guid" => guid}, socket) do
    session =
      case Map.get(socket.assigns.search_session.selections, term) do
        ^guid -> Acquisition.clear_selection(term)
        _ -> Acquisition.set_selection(term, guid)
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

  def handle_event("grab_selected", _params, socket) do
    selections = socket.assigns.search_session.selections

    if map_size(selections) == 0 do
      {:noreply, socket}
    else
      results =
        selections
        |> Map.values()
        |> Enum.map(&Logic.find_result(socket.assigns.search_session.groups, &1))
        |> Enum.reject(&is_nil/1)

      session = Acquisition.set_grabbing(true)
      send(self(), {:run_grabs, results})
      {:noreply, assign(socket, search_session: session)}
    end
  end

  # History-zone events (filter, search). Row-level cancel / re-arm
  # actions are gone — rows are passive and clicking one opens the
  # pursuit modal where Cancel / Change target live.

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

  def handle_event("change_target", _params, socket) do
    case ChangeTarget.execute(%{pursuit_id: socket.assigns.selected_pursuit_id}) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Looking for a new target…") |> load_pursuit_detail()}

      {:error, :not_eligible} ->
        {:noreply, put_flash(socket, :error, "This pursuit can't change target right now.")}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit change-target failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not change target for this pursuit.")}
    end
  end

  def handle_event("request_decision", _params, socket) do
    case RequestDecision.execute(%{
           pursuit_id: socket.assigns.selected_pursuit_id,
           prompt: @decision_prompt
         }) do
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
                build_decision(pursuit, Pursuits.header_from(pursuit).recipe.search_queries, nil)

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
    Acquisition.run_search_one_async(query)
    {:noreply, socket}
  end

  def handle_info({:search_session, session}, socket) do
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_info({:run_grabs, results}, socket) do
    query = socket.assigns.search_session.query
    pairs = Enum.map(results, fn result -> {result, Acquisition.pick_target(result, query)} end)

    Enum.each(pairs, fn
      {result, {:error, reason}} ->
        Log.warning(:acquisition, "manual pick failed — #{result.title} — #{inspect(reason)}")

      _ ->
        :ok
    end)

    ok_count = Enum.count(pairs, fn {_, outcome} -> match?({:ok, _}, outcome) end)
    err_count = length(pairs) - ok_count
    Log.info(:acquisition, "manual pick batch complete — #{ok_count} ok, #{err_count} failed")

    Acquisition.set_grab_message(Logic.build_grab_message(pairs))
    Acquisition.clear_search_results()
    Acquisition.set_grabbing(false)

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

  # All `acquisition:updates` broadcasts are typed structs — either
  # `Pursuits.Events.*` (persisted timeline events) or `TargetEvents.*`
  # (transient lifecycle signals). TargetEvents trigger a History
  # reload (terminal state transitions show up there);
  # Pursuits.Events trigger a pursuit-row reload + modal sync.
  def handle_info(%struct{} = event, socket) do
    cond do
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
        timeline = Pursuits.timeline_for(pursuit.id)

        {card, results_by_guid, needs_fetch?} =
          decision_card_or_placeholder(
            pursuit,
            header.recipe.search_queries,
            socket.assigns.pursuit_detail
          )

        socket =
          assign(socket,
            pursuit_detail: %{
              header: header,
              status: status,
              timeline: timeline,
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
  defp decision_card_or_placeholder(
         %Pursuit{awaiting_decision_at: %DateTime{}} = pursuit,
         queries,
         cached
       ) do
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

  defp decision_card_or_placeholder(_pursuit, _queries, _cached), do: {nil, %{}, false}

  # Owned async (ADR-049): runs off the LV process via start_async/3 so the
  # WebSocket handler returns immediately, the task is cancelled with the
  # LiveView, and tests can await it. Result lands in
  # `handle_async({:alternatives_fetch, pursuit_id}, …)`, which ignores it
  # if the user has closed the modal or selected a different pursuit.
  defp start_async_alternatives_fetch(socket, pursuit_id) do
    start_async(socket, {:alternatives_fetch, pursuit_id}, fn ->
      case Pursuits.get(pursuit_id) do
        {:ok, pursuit} ->
          queries = Pursuits.header_from(pursuit).recipe.search_queries
          build_decision(pursuit, queries, nil)

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
  defp build_decision(%Pursuit{awaiting_decision_at: %DateTime{}} = pursuit, search_queries, cached) do
    case cached do
      %{decision_card: %ViewModels.DecisionCard{pursuit_id: id} = vm, decision_results_by_guid: results}
      when id == pursuit.id ->
        %{card: vm, results_by_guid: results}

      _ ->
        results = Acquisition.list_alternatives_for(pursuit)

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

  defp build_decision(_pursuit, _search_queries, _cached), do: %{card: nil, results_by_guid: %{}}

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
    session = Acquisition.retry_search_terms(terms)
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
          <.button variant="dismiss" size="sm" phx-click="cancel_download_cancel">
            Keep
          </.button>
          <.button variant="danger" size="sm" phx-click="cancel_download_confirm">
            Cancel download
          </.button>
        </div>
      </div>
    </.modal>
    """
  end
end
