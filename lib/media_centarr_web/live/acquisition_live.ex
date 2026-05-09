defmodule MediaCentarrWeb.AcquisitionLive do
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

  See `MediaCentarr.Acquisition.QueryExpander` for the supported brace
  syntax, `MediaCentarrWeb.AcquisitionLive.Logic` for search/group
  helpers, and `MediaCentarrWeb.AcquisitionLive.ActivityLogic` for the
  activity table helpers.

  ## External-state reconciliation

  This LiveView mirrors three external sources of truth — qBittorrent's
  queue (via `QueueMonitor` polls), the in-memory `SearchSession`, and
  the `acquisition_grabs` table. Each lives behind its own PubSub
  subscription, declared in `mount/3`:

      Acquisition.subscribe()        # acquisition:updates  → grab lifecycle
      Acquisition.subscribe_queue()  # acquisition:queue    → queue snapshots
      Acquisition.subscribe_search() # acquisition:search   → search session

  See the matching `subscribe_*/0` functions on `MediaCentarr.Acquisition`
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

  use MediaCentarrWeb, :live_view

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.CancelReasons
  alias MediaCentarr.Capabilities
  alias MediaCentarrWeb.AcquisitionLive.{Activity, ActivityLogic, Logic, Queue, Search}

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
        Capabilities.subscribe()
      end

      {:ok,
       socket
       |> assign(
         loaded?: false,
         search_session: %Acquisition.SearchSession{},
         active_queue: [],
         queue_status: :initializing,
         queue_loaded?: false,
         expanded_queue_groups: MapSet.new(),
         cancel_confirm: nil,
         pending_cancels: %{},
         download_client_ready: false,
         activity_filter: :active,
         activity_search: "",
         activity_grabs: [],
         pursuit_rows: [],
         pursuits_reload_timer: nil,
         reload_timer: nil
       )
       |> stream_configure(:queue_ops, dom_id: &queue_op_dom_id/1)
       |> stream(:queue_ops, [])}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # First-render data load — gated by `connected?` so the static HTTP
  # render ships empty defaults and the WebSocket render fills them in
  # once. See AGENTS.md → LiveView callbacks (Iron Law).
  defp ensure_loaded(socket) do
    if connected?(socket) and not socket.assigns.loaded? do
      socket
      |> assign(:search_session, Acquisition.current_search_session())
      |> assign(:download_client_ready, Capabilities.download_client_ready?())
      |> assign_queue_from_state(Acquisition.queue_state())
      |> load_pursuit_rows()
      |> assign(:loaded?, true)
    else
      socket
    end
  end

  defp load_pursuit_rows(socket) do
    assign(socket, pursuit_rows: MediaCentarr.Acquisition.Pursuits.list_active_rows())
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

  defp assign_queue_from_state(socket, %MediaCentarr.Acquisition.QueueState{} = state) do
    active = Enum.reject(state.items, &(&1.state == :completed))

    {visible, pending_cancels} =
      Logic.apply_pending_cancels(
        active,
        socket.assigns.pending_cancels,
        System.monotonic_time(:second)
      )

    status = MediaCentarr.Acquisition.QueueStatus.derive(state, @watched_cadence_ms)

    socket
    |> assign(
      active_queue: visible,
      queue_status: status,
      pending_cancels: pending_cancels,
      queue_loaded?: true
    )
    |> stream_queue_ops(visible)
  end

  # Re-streams the queue ops using the supplied items list and the
  # current `expanded_queue_groups`. Use `reset: true` so the stream
  # mirrors `prepare_queue_for_render/2` exactly — Phoenix's stream
  # client computes the minimal set of insert/move/delete ops to
  # transition from the prior DOM to the new ordered list, keying by
  # `queue_op_dom_id/1` so morphdom moves rows by id rather than
  # morphing them positionally in place. The latter is the original
  # bug: cancelling row N visually removed row N+1 because the
  # comprehension re-rendered position N's content with N+1's data
  # and dropped the trailing position.
  defp stream_queue_ops(socket, items) do
    ops = Logic.prepare_queue_for_render(items, socket.assigns.expanded_queue_groups)
    stream(socket, :queue_ops, ops, reset: true)
  end

  defp queue_op_dom_id({:item, item}), do: "queue-item-#{item.id}"
  defp queue_op_dom_id({:summary, summary}), do: "queue-summary-#{summary.state}"

  # `?search=…` and `?filter=…` deep-link from the upcoming-zone badges
  # straight to a pre-filtered activity view. `?prowlarr_search=…` from
  # the same zone pre-fills the manual-search box and auto-fires the
  # search so a user clicking a "no acquisition yet" row immediately
  # sees Prowlarr results.
  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> ensure_loaded()
      |> assign(
        activity_search: Map.get(params, "search", ""),
        activity_filter: ActivityLogic.parse_filter(Map.get(params, "filter"))
      )
      |> load_activity()
      |> maybe_trigger_prowlarr_search(Map.get(params, "prowlarr_search"))

    {:noreply, socket}
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
    assigns =
      assigns
      |> Phoenix.Component.assign(:any_loading?, Logic.any_loading?(assigns.search_session.groups))
      |> Phoenix.Component.assign(:timeout_terms, Logic.timeout_terms(assigns.search_session.groups))

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/download">
      <:overlays>
        <.cancel_confirmation cancel_confirm={@cancel_confirm} />
      </:overlays>
      <div
        data-page-behavior="download"
        data-nav-default-zone="download"
        class="max-w-4xl mx-auto space-y-6 py-6"
      >
        <h1 class="text-2xl font-bold">Downloads</h1>

        <%!-- Active queue from the configured download client. Completed
        torrents are intentionally hidden — qBittorrent manages seeding.
        Hidden entirely unless the download client has passed a Settings
        connection test. --%>
        <Queue.queue_zone
          download_client_ready={@download_client_ready}
          queue_loaded?={@queue_loaded?}
          queue_status={@queue_status}
          active_queue={@active_queue}
          queue_ops={@streams.queue_ops}
        />

        <section :if={@pursuit_rows != []} data-nav-zone="pursuits" class="space-y-3">
          <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
            Active pursuits
          </h2>
          <div class="grid gap-3">
            <MediaCentarrWeb.Components.Acquisition.PursuitRow.pursuit_row
              :for={vm <- @pursuit_rows}
              vm={vm}
            />
          </div>
        </section>

        <Activity.activity_zone
          grabs={@activity_grabs}
          filter={@activity_filter}
          search={@activity_search}
        />

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
    Acquisition.set_query_preview(query)
    {:noreply, refresh_search_session(socket)}
  end

  def handle_event("submit_search", %{"query" => query}, socket) do
    if socket.assigns.search_session.grabbing? do
      {:noreply, socket}
    else
      Acquisition.set_query_preview(query)

      case Acquisition.start_search(query) do
        {:ok, %{queries: queries}} ->
          Enum.each(queries, fn q -> send(self(), {:run_search_one, q}) end)
          {:noreply, refresh_search_session(socket)}

        {:error, _} ->
          {:noreply, refresh_search_session(socket)}
      end
    end
  end

  def handle_event("retry_search", %{"term" => term}, socket) do
    retry_terms(socket, [term])
    {:noreply, refresh_search_session(socket)}
  end

  def handle_event("retry_all_timeouts", _params, socket) do
    retry_terms(socket, Logic.timeout_terms(socket.assigns.search_session.groups))
    {:noreply, refresh_search_session(socket)}
  end

  def handle_event("toggle_group", %{"term" => term}, socket) do
    Acquisition.toggle_group(term)
    {:noreply, refresh_search_session(socket)}
  end

  def handle_event("select_result", %{"term" => term, "guid" => guid}, socket) do
    case Map.get(socket.assigns.search_session.selections, term) do
      ^guid -> Acquisition.clear_selection(term)
      _ -> Acquisition.set_selection(term, guid)
    end

    {:noreply, refresh_search_session(socket)}
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
          |> stream_queue_ops(remaining)
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

  def handle_event("toggle_queue_group", %{"state" => state}, socket) do
    state_atom =
      case state do
        "queued" -> :queued
        "error" -> :error
        _ -> nil
      end

    if state_atom do
      expanded =
        if MapSet.member?(socket.assigns.expanded_queue_groups, state_atom) do
          MapSet.delete(socket.assigns.expanded_queue_groups, state_atom)
        else
          MapSet.put(socket.assigns.expanded_queue_groups, state_atom)
        end

      socket =
        socket
        |> assign(expanded_queue_groups: expanded)
        |> stream_queue_ops(socket.assigns.active_queue)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
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

      Acquisition.set_grabbing(true)
      send(self(), {:run_grabs, results})
      {:noreply, refresh_search_session(socket)}
    end
  end

  # Activity-zone events (filter, search, cancel, re-arm).

  def handle_event("set_activity_filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(activity_filter: ActivityLogic.parse_filter(filter))
     |> load_activity()}
  end

  def handle_event("set_activity_search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(activity_search: search) |> load_activity()}
  end

  def handle_event("cancel_activity_grab", %{"id" => id}, socket) do
    case Acquisition.cancel_grab(id, CancelReasons.user_disabled()) do
      {:ok, _} -> {:noreply, load_activity(socket)}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Grab no longer exists")}
    end
  end

  def handle_event("rearm_activity_grab", %{"id" => id}, socket) do
    case Acquisition.rearm_grab(id) do
      {:ok, _} -> {:noreply, load_activity(socket)}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Grab no longer exists")}
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
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      outcome =
        try do
          Acquisition.search(query)
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      Acquisition.record_search_result(query, outcome)
    end)

    {:noreply, socket}
  end

  def handle_info({:search_session, session}, socket) do
    {:noreply, assign(socket, search_session: session)}
  end

  def handle_info({:run_grabs, results}, socket) do
    query = socket.assigns.search_session.query
    pairs = Enum.map(results, fn result -> {result, Acquisition.grab(result, query)} end)

    Enum.each(pairs, fn
      {result, {:error, reason}} ->
        Log.warning(:acquisition, "grab failed — #{result.title} — #{inspect(reason)}")

      _ ->
        :ok
    end)

    ok_count = Enum.count(pairs, fn {_, outcome} -> match?({:ok, _}, outcome) end)
    err_count = length(pairs) - ok_count
    Log.info(:acquisition, "grab batch complete — #{ok_count} ok, #{err_count} failed")

    Acquisition.set_grab_message(Logic.build_grab_message(pairs))
    Acquisition.clear_search_results()
    Acquisition.set_grabbing(false)

    {:noreply, socket}
  end

  def handle_info({:queue_state, %MediaCentarr.Acquisition.QueueState{} = state}, socket) do
    {:noreply, assign_queue_from_state(socket, state)}
  end

  # Acquisition PubSub events — refresh the activity zone so lifecycle
  # state changes appear without waiting for a manual reload.
  def handle_info({event, _payload}, socket)
      when event in [
             :grab_submitted,
             :grab_failed,
             :auto_grab_armed,
             :auto_grab_snoozed,
             :auto_grab_abandoned,
             :auto_grab_cancelled
           ] do
    {:noreply, debounce(socket, :reload_timer, :reload_activity, 500)}
  end

  def handle_info(:reload_activity, socket) do
    {:noreply, load_activity(socket)}
  end

  # Typed pursuit-event structs ride the same `acquisition:updates` topic
  # the legacy grab tuples use. Pattern-match on the namespace prefix and
  # trigger a debounced pursuit-row refresh.
  def handle_info(%struct{} = _event, socket) do
    if MediaCentarr.Acquisition.Pursuits.Events.event?(struct) do
      {:noreply, debounce(socket, :pursuits_reload_timer, :reload_pursuits, 500)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:reload_pursuits, socket) do
    {:noreply, load_pursuit_rows(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_activity(socket) do
    grabs =
      socket.assigns.activity_filter
      |> Acquisition.list_auto_grabs()
      |> MediaCentarrWeb.AcquisitionLive.ActivityLogic.filter_by_search(socket.assigns.activity_search)

    assign(socket, activity_grabs: grabs)
  end

  defp retry_terms(_socket, []), do: :ok

  defp retry_terms(_socket, terms) do
    Acquisition.retry_search_terms(terms)
    Enum.each(terms, fn term -> send(self(), {:run_search_one, term}) end)
    :ok
  end

  # LiveView's main loop renders between mailbox messages. After a session
  # mutation, the broadcast lands in the mailbox but isn't processed until
  # AFTER the post-handle_event render — so without this helper that render
  # would show stale assigns. The follow-up {:search_session, _} message
  # then lands the same struct (a no-op assign).
  defp refresh_search_session(socket) do
    assign(socket, search_session: Acquisition.current_search_session())
  end

  # ---------------------------------------------------------------------------
  # Cancel-confirmation modal — kept on the parent because the
  # confirm/cancel events flip parent socket assigns (`pending_cancels`).
  # ---------------------------------------------------------------------------

  attr :cancel_confirm, :any,
    required: true,
    doc:
      "transient cancel-confirmation state — `nil` or a `%{id, title}` map. Heterogeneous nil-or-map shape; `:any` is intentional."

  defp cancel_confirmation(%{cancel_confirm: nil} = assigns), do: ~H""

  defp cancel_confirmation(assigns) do
    ~H"""
    <div
      class="modal-backdrop"
      data-state="open"
      data-detail-mode="modal"
      data-dismiss-event="cancel_download_cancel"
      phx-click="cancel_download_cancel"
      phx-window-keydown="cancel_download_cancel"
      phx-key="Escape"
      style="z-index: 60;"
    >
      <div class="modal-panel modal-panel-sm p-6" phx-click={%Phoenix.LiveView.JS{}}>
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
    </div>
    """
  end
end
