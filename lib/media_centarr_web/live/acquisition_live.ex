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
  """

  use MediaCentarrWeb, :live_view

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.Quality
  alias MediaCentarr.Capabilities
  alias MediaCentarrWeb.AcquisitionLive.{Activity, Logic}

  @queue_poll_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    # The Prowlarr-readiness gate is the only DB read on the static HTTP
    # mount path — without it we can't decide whether to render or
    # redirect. All other state (search session, download-client gate)
    # is loaded after the WebSocket connects via `ensure_loaded/1`.
    if Capabilities.prowlarr_ready?() do
      if connected?(socket) do
        Acquisition.subscribe()
        Acquisition.subscribe_search()
        Capabilities.subscribe()
        Process.send_after(self(), :poll_queue, 0)
      end

      {:ok,
       assign(socket,
         loaded?: false,
         search_session: %Acquisition.SearchSession{},
         active_queue: [],
         queue_loaded?: false,
         cancel_confirm: nil,
         download_client_ready: false,
         activity_filter: :active,
         activity_search: "",
         activity_grabs: [],
         reload_timer: nil
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # First-render data load — gated by `connected?` so the static HTTP
  # render ships empty defaults and the WebSocket render fills them in
  # once. See CLAUDE.md → LiveView Callbacks (Iron Law).
  defp ensure_loaded(socket) do
    if connected?(socket) and not socket.assigns.loaded? do
      socket
      |> assign(:search_session, Acquisition.current_search_session())
      |> assign(:download_client_ready, Capabilities.download_client_ready?())
      |> assign(:loaded?, true)
    else
      socket
    end
  end

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
        activity_filter: parse_activity_filter(params)
      )
      |> load_activity()
      |> maybe_trigger_prowlarr_search(Map.get(params, "prowlarr_search"))

    {:noreply, socket}
  end

  defp parse_activity_filter(params) do
    case Map.get(params, "filter") do
      "active" -> :active
      "abandoned" -> :abandoned
      "cancelled" -> :cancelled
      "grabbed" -> :grabbed
      "all" -> :all
      _ -> :active
    end
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
      <div
        data-page-behavior="download"
        data-nav-default-zone="download"
        class="max-w-4xl mx-auto space-y-6 py-6"
      >
        <h1 class="text-2xl font-bold">Downloads</h1>

        <%!-- Active queue from configured download client. Completed
        torrents are intentionally hidden — qBittorrent manages seeding.
        Hidden entirely unless the download client has passed a test in
        Settings — without a green test we can't poll the queue. --%>
        <section
          :if={@download_client_ready}
          data-nav-zone="queue"
          class="glass-surface rounded-xl overflow-hidden"
        >
          <div class="px-4 py-2 border-b border-base-content/5 flex items-center justify-between">
            <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Downloading
            </h2>
            <span
              :if={!@queue_loaded?}
              class="loading loading-spinner loading-xs text-base-content/30"
            >
            </span>
          </div>

          <p
            :if={@queue_loaded? && @active_queue == []}
            class="px-4 py-6 text-center text-sm text-base-content/40"
          >
            No active downloads
          </p>

          <div :if={@active_queue != []}>
            <.queue_row :for={item <- @active_queue} item={item} />
          </div>
        </section>

        <section
          :if={!@download_client_ready}
          class="glass-surface rounded-xl px-4 py-6 text-center text-sm text-base-content/50"
        >
          Connect a download client in
          <.link navigate="/settings?section=acquisition" class="link link-primary">
            Settings
          </.link>
          to see the active queue.
        </section>

        <Activity.activity_zone
          grabs={@activity_grabs}
          filter={@activity_filter}
          search={@activity_search}
        />

        <%!-- Search section --%>
        <section data-nav-zone="search" class="glass-surface rounded-xl p-4 space-y-3">
          <form
            phx-change="query_change"
            phx-submit="submit_search"
            onsubmit="this.querySelector('button[type=submit]').focus()"
            class="flex gap-3 items-end"
          >
            <div class="flex-1">
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Query
              </label>
              <input
                type="text"
                name="query"
                value={@search_session.query}
                class="input input-bordered w-full font-mono text-sm"
                placeholder="Title S01E{01-10}"
                autofocus
                phx-debounce="200"
                data-nav-item
                data-captures-keys
                tabindex="0"
                onkeydown="if (event.key === 'Escape') { event.preventDefault(); this.form.querySelector('button[type=submit]').focus() }"
              />
            </div>
            <.button
              type="submit"
              variant="secondary"
              disabled={expansion_blocked?(@search_session.expansion_preview)}
              data-nav-item
              tabindex="0"
            >
              <span :if={@any_loading?} class="loading loading-spinner loading-sm"></span>
              <.icon :if={!@any_loading?} name="hero-magnifying-glass" class="size-4" /> Search
            </.button>
          </form>

          <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs">
            <span class="text-base-content/40">Syntax:</span>
            <span class="flex items-center gap-2">
              <span class="text-base-content/50">List</span>
              <code class="font-mono px-2 py-0.5 rounded bg-base-content/10 text-base-content/70">
                {"{a,b,c}"}
              </code>
            </span>
            <span class="flex items-center gap-2">
              <span class="text-base-content/50">Range</span>
              <code class="font-mono px-2 py-0.5 rounded bg-base-content/10 text-base-content/70">
                {"{00-09}"}
              </code>
            </span>
            <span class="text-base-content/30">— each expansion runs as its own search</span>
          </div>

          <p class={["text-xs", expansion_color(@search_session.expansion_preview)]}>
            {expansion_text(@search_session.expansion_preview)}
          </p>
        </section>

        <%!-- Grab feedback --%>
        <div
          :if={@search_session.grab_message}
          class={[
            "glass-inset rounded-lg px-4 py-3 text-sm flex items-center gap-2",
            grab_message_color(@search_session.grab_message)
          ]}
        >
          <.icon name={grab_message_icon(@search_session.grab_message)} class="size-4 shrink-0" />
          {grab_message_text(@search_session.grab_message)}
        </div>

        <%!-- Results --%>
        <section :if={@search_session.groups != []} data-nav-zone="grid" class="space-y-3">
          <div :for={group <- @search_session.groups} class="space-y-1">
            <%!-- Group header (top-seeder summary) --%>
            <button
              type="button"
              class="glass-surface rounded-lg w-full px-4 py-3 flex items-center gap-3 text-left hover:bg-base-content/5"
              phx-click="toggle_group"
              phx-value-term={group.term}
              data-nav-item
              tabindex="0"
            >
              <.icon
                name={
                  if group.expanded?, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"
                }
                class="size-4 shrink-0 text-base-content/40"
              />
              <span class="text-xs font-medium text-base-content/50 w-32 shrink-0 truncate">
                {group.term}
              </span>
              <%= case {group.status, group.results} do %>
                <% {:loading, _} -> %>
                  <span class="loading loading-spinner loading-xs text-base-content/40"></span>
                  <span class="flex-1 text-sm text-base-content/40">Searching…</span>
                <% {{:failed, reason}, _} -> %>
                  <span class="flex-1 text-sm text-error/70">
                    {Logic.format_search_error(reason)}
                  </span>
                <% {:abandoned, _} -> %>
                  <span class="flex-1 text-sm text-base-content/40">
                    Search was interrupted — Retry to resume
                  </span>
                <% {:ready, []} -> %>
                  <span class="flex-1 text-sm text-base-content/40">No results</span>
                <% {:ready, [_ | _]} -> %>
                  <span class={[
                    "text-xs font-bold w-10 shrink-0",
                    quality_color(group.featured.quality)
                  ]}>
                    {Quality.label(group.featured.quality)}
                  </span>
                  <span class="flex-1 min-w-0 text-sm truncate" title={group.featured.title}>
                    {group.featured.title}
                  </span>
                  <span
                    :if={group.featured.seeders}
                    class={[
                      "text-xs tabular-nums shrink-0",
                      seeder_color(group.featured.seeders)
                    ]}
                  >
                    {group.featured.seeders}S
                  </span>
              <% end %>
            </button>

            <%!-- Failed/abandoned-search helpers: retry the same term, jump to settings --%>
            <div
              :if={match?({:failed, _}, group.status) or group.status == :abandoned}
              class="pl-44 flex items-center gap-2"
            >
              <.button
                variant="risky"
                size="xs"
                phx-click="retry_search"
                phx-value-term={group.term}
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-arrow-path-mini" class="size-3" /> Retry
              </.button>
              <.button
                :if={match?({:failed, _}, group.status)}
                variant="secondary"
                size="xs"
                patch={~p"/settings?section=acquisition"}
                data-nav-item
                tabindex="0"
              >
                Open Prowlarr settings <.icon name="hero-chevron-right-mini" class="size-3" />
              </.button>
            </div>

            <%!-- Expanded alternatives --%>
            <div :if={group.expanded? && group.results != []} class="ml-6 space-y-1">
              <button
                :for={result <- group.results}
                type="button"
                class={[
                  "glass-surface rounded-lg w-full px-4 py-2 flex items-center gap-3 text-left text-sm",
                  selected?(@search_session.selections, group.term, result.guid) && "bg-primary/10",
                  !selected?(@search_session.selections, group.term, result.guid) &&
                    "hover:bg-base-content/5"
                ]}
                phx-click="select_result"
                phx-value-term={group.term}
                phx-value-guid={result.guid}
                data-nav-item
                tabindex="0"
              >
                <.icon
                  name={
                    if selected?(@search_session.selections, group.term, result.guid),
                      do: "hero-check-circle-mini",
                      else: "hero-minus-circle-mini"
                  }
                  class={selection_icon_class(@search_session.selections, group.term, result.guid)}
                />
                <span class={["text-xs font-bold w-10 shrink-0", quality_color(result.quality)]}>
                  {Quality.label(result.quality)}
                </span>
                <span class="flex-1 min-w-0 truncate" title={result.title}>
                  {result.title}
                </span>
                <span class="flex items-center gap-3 shrink-0 text-xs text-base-content/50">
                  <span :if={result.size_bytes} class="tabular-nums">
                    {format_bytes(result.size_bytes)}
                  </span>
                  <span :if={result.seeders} class={["tabular-nums", seeder_color(result.seeders)]}>
                    {result.seeders}S
                  </span>
                  <span class="max-w-24 truncate">{result.indexer_name}</span>
                </span>
              </button>
            </div>
          </div>

          <%!-- Footer actions: bulk-retry + grab --%>
          <div class="flex justify-end items-center gap-2">
            <.button
              :if={!@any_loading? && @timeout_terms != []}
              variant="risky"
              phx-click="retry_all_timeouts"
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-arrow-path-mini" class="size-4" />
              Retry {length(@timeout_terms)} timeouts
            </.button>
            <.button
              variant="action"
              phx-click="grab_selected"
              disabled={@search_session.grabbing? || map_size(@search_session.selections) == 0}
              data-nav-item
              tabindex="0"
            >
              <span :if={@search_session.grabbing?} class="loading loading-spinner loading-sm"></span>
              <.icon
                :if={!@search_session.grabbing?}
                name="hero-arrow-down-tray-mini"
                class="size-4"
              /> Grab {map_size(@search_session.selections)} selected
            </.button>
          </div>
        </section>
      </div>

      <.cancel_confirmation cancel_confirm={@cancel_confirm} />
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
          # Refresh the queue now so the row disappears without waiting for
          # the next 5 s poll.
          send(self(), :poll_queue)
          put_flash(socket, :info, "Cancelled “#{title}”.")

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

      Acquisition.set_grabbing(true)
      send(self(), {:run_grabs, results})
      {:noreply, refresh_search_session(socket)}
    end
  end

  # Activity-zone events (filter, search, cancel, re-arm).

  def handle_event("set_activity_filter", %{"filter" => filter}, socket) do
    filter_atom =
      case filter do
        "active" -> :active
        "abandoned" -> :abandoned
        "cancelled" -> :cancelled
        "grabbed" -> :grabbed
        _ -> :all
      end

    {:noreply, socket |> assign(activity_filter: filter_atom) |> load_activity()}
  end

  def handle_event("set_activity_search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(activity_search: search) |> load_activity()}
  end

  def handle_event("cancel_activity_grab", %{"id" => id}, socket) do
    case Acquisition.cancel_grab(id, "user_disabled") do
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
    Acquisition.clear_selections()
    Acquisition.set_grabbing(false)

    {:noreply, socket}
  end

  def handle_info(:poll_queue, socket) do
    if socket.assigns.download_client_ready do
      queue =
        case Acquisition.list_downloads(:all) do
          {:ok, items} ->
            Enum.reject(items, &(&1.state == :completed))

          {:error, :not_configured} ->
            # Download client not set up — show empty list, no log noise.
            []

          {:error, reason} ->
            Log.warning(:acquisition, "download client poll failed: #{inspect(reason)}")
            socket.assigns.active_queue
        end

      Process.send_after(self(), :poll_queue, @queue_poll_interval_ms)

      {:noreply, assign(socket, active_queue: queue, queue_loaded?: true)}
    else
      # Skip this tick; :capabilities_changed will re-arm polling when the
      # download client comes online. Avoid hammering an unreachable endpoint.
      Process.send_after(self(), :poll_queue, @queue_poll_interval_ms)
      {:noreply, socket}
    end
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
  # Template helpers
  # ---------------------------------------------------------------------------

  defp expansion_blocked?({:error, _}), do: true
  defp expansion_blocked?(:idle), do: true
  defp expansion_blocked?(_), do: false

  defp expansion_text(:idle), do: "Type a title and press Enter to search."
  defp expansion_text({:ok, 1}), do: "1 query — press Enter to search."
  defp expansion_text({:ok, n}), do: "#{n} queries in parallel — press Enter to search."
  defp expansion_text({:error, :invalid_syntax}), do: "Invalid brace syntax — see examples above."

  defp expansion_color({:error, _}), do: "text-error"
  defp expansion_color(_), do: "text-base-content/50"

  defp selected?(selections, term, guid), do: Map.get(selections, term) == guid

  defp selection_icon_class(selections, term, guid) do
    if selected?(selections, term, guid) do
      "size-4 shrink-0 text-primary"
    else
      "size-4 shrink-0 text-base-content/30"
    end
  end

  defp grab_message_color({:ok, _}), do: "text-success"
  defp grab_message_color({:partial, _}), do: "text-warning"
  defp grab_message_color({:error, _}), do: "text-error"

  defp grab_message_icon({:ok, _}), do: "hero-check-circle-mini"
  defp grab_message_icon({:partial, _}), do: "hero-exclamation-triangle-mini"
  defp grab_message_icon({:error, _}), do: "hero-x-circle-mini"

  defp grab_message_text({_, text}), do: text

  defp quality_color(:uhd_4k), do: "text-success"
  defp quality_color(:hd_1080p), do: "text-info"
  defp quality_color(nil), do: "text-base-content/40"

  defp seeder_color(n) when n >= 10, do: "text-success"
  defp seeder_color(n) when n >= 3, do: "text-warning"
  defp seeder_color(_), do: "text-error"

  attr :item, MediaCentarr.Acquisition.QueueItem, required: true

  defp queue_row(assigns) do
    ~H"""
    <div class="px-4 py-3 border-b border-base-content/5 last:border-0 space-y-1.5">
      <div class="flex items-center gap-3">
        <span class="flex-1 min-w-0 text-sm truncate" title={@item.title}>
          {@item.title}
        </span>
        <span :if={@item.state} class={["text-xs", Logic.state_badge_class(@item.state)]}>
          {Logic.state_label(@item.state)}
        </span>
        <span :if={@item.timeleft} class="text-xs text-base-content/40 tabular-nums">
          {@item.timeleft}
        </span>
        <.button
          variant="destructive_inline"
          size="xs"
          shape="circle"
          class="text-base-content/40 hover:text-error"
          phx-click="cancel_download_prompt"
          phx-value-id={@item.id}
          phx-value-title={@item.title}
          title="Cancel and delete"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.button>
      </div>

      <div :if={@item.progress} class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
        <div
          class="progress-fill h-full bg-primary rounded-full"
          style={"width: #{@item.progress}%"}
        >
        </div>
      </div>

      <div class="flex items-center gap-3 text-xs text-base-content/40">
        <span :if={@item.download_client}>{@item.download_client}</span>
        <span :if={@item.indexer}>{@item.indexer}</span>
        <span :if={@item.progress} class="tabular-nums">{@item.progress}%</span>
      </div>
    </div>
    """
  end

  attr :cancel_confirm, :any, required: true

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
          <.button
            variant="danger"
            size="sm"
            phx-click="cancel_download_confirm"
          >
            Cancel download
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{round(bytes / 1_048_576)} MB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"
end
