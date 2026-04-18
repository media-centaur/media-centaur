defmodule MediaCentarrWeb.AcquisitionLive do
  @moduledoc """
  Download page — Prowlarr search + queue monitor.

  Searches Prowlarr using brace-expansion query syntax (one search per
  expansion), groups results by query, lets the user select one release per
  group, and submits the selection to Prowlarr's grab endpoint. The Prowlarr
  download queue polls every 5 seconds below the search section.

  Mounted at `/download`. Only available when Prowlarr is configured —
  unauthenticated requests redirect to the library.

  See `MediaCentarr.Acquisition.QueryExpander` for the supported brace syntax
  and `MediaCentarrWeb.AcquisitionLive.Logic` for extracted pure helpers.
  """

  use MediaCentarrWeb, :live_view

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{QueryExpander, Quality}
  alias MediaCentarrWeb.AcquisitionLive.Logic

  @queue_poll_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if Acquisition.available?() do
      if connected?(socket) do
        Acquisition.subscribe()
        Process.send_after(self(), :poll_queue, 0)
      end

      {:ok,
       assign(socket,
         query: "",
         expansion_preview: :idle,
         searching?: false,
         groups: [],
         selections: %{},
         grabbing?: false,
         grab_message: nil,
         active_queue: [],
         queue_loaded?: false,
         cancel_confirm: nil
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/download">
      <div
        data-page-behavior="download"
        data-nav-default-zone="download"
        class="max-w-4xl mx-auto space-y-6 py-6"
      >
        <h1 class="text-2xl font-bold">Download</h1>

        <%!-- Search section --%>
        <section data-nav-zone="sections" class="glass-surface rounded-xl p-4 space-y-3">
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
                value={@query}
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
            <button
              type="submit"
              class="btn btn-soft btn-primary"
              disabled={expansion_blocked?(@expansion_preview)}
              data-nav-item
              tabindex="0"
            >
              <span :if={@searching?} class="loading loading-spinner loading-sm"></span>
              <.icon :if={!@searching?} name="hero-magnifying-glass" class="size-4" /> Search
            </button>
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

          <p class={["text-xs", expansion_color(@expansion_preview)]}>
            {expansion_text(@expansion_preview)}
          </p>
        </section>

        <%!-- Grab feedback --%>
        <div
          :if={@grab_message}
          class={[
            "glass-inset rounded-lg px-4 py-3 text-sm flex items-center gap-2",
            grab_message_color(@grab_message)
          ]}
        >
          <.icon name={grab_message_icon(@grab_message)} class="size-4 shrink-0" />
          {grab_message_text(@grab_message)}
        </div>

        <%!-- Results --%>
        <section :if={@groups != []} data-nav-zone="grid" class="space-y-3">
          <div :for={group <- @groups} class="space-y-1">
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
                <% {:ready, []} -> %>
                  <span class="flex-1 text-sm text-base-content/40">No results</span>
                <% {:ready, [_ | _]} -> %>
                  <% featured = Logic.featured_result(group, @selections) %>
                  <span class={[
                    "text-xs font-bold w-10 shrink-0",
                    quality_color(featured.quality)
                  ]}>
                    {Quality.label(featured.quality)}
                  </span>
                  <span class="flex-1 min-w-0 text-sm truncate" title={featured.title}>
                    {featured.title}
                  </span>
                  <span
                    :if={featured.seeders}
                    class={["text-xs tabular-nums shrink-0", seeder_color(featured.seeders)]}
                  >
                    {featured.seeders}S
                  </span>
              <% end %>
            </button>

            <%!-- Failed-search helper: link to Prowlarr settings --%>
            <div :if={match?({:failed, _}, group.status)} class="pl-44">
              <.link
                patch={~p"/settings?section=acquisition"}
                class="btn btn-soft btn-primary btn-xs"
                data-nav-item
                tabindex="0"
              >
                Open Prowlarr settings <.icon name="hero-chevron-right-mini" class="size-3" />
              </.link>
            </div>

            <%!-- Expanded alternatives --%>
            <div :if={group.expanded? && group.results != []} class="ml-6 space-y-1">
              <button
                :for={result <- group.results}
                type="button"
                class={[
                  "glass-surface rounded-lg w-full px-4 py-2 flex items-center gap-3 text-left text-sm",
                  selected?(@selections, group.term, result.guid) && "bg-primary/10",
                  !selected?(@selections, group.term, result.guid) && "hover:bg-base-content/5"
                ]}
                phx-click="select_result"
                phx-value-term={group.term}
                phx-value-guid={result.guid}
                data-nav-item
                tabindex="0"
              >
                <.icon
                  name={
                    if selected?(@selections, group.term, result.guid),
                      do: "hero-check-circle-mini",
                      else: "hero-minus-circle-mini"
                  }
                  class={selection_icon_class(@selections, group.term, result.guid)}
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

          <%!-- Grab button --%>
          <div class="flex justify-end">
            <button
              type="button"
              class="btn btn-soft btn-success"
              phx-click="grab_selected"
              disabled={@grabbing? || map_size(@selections) == 0}
              data-nav-item
              tabindex="0"
            >
              <span :if={@grabbing?} class="loading loading-spinner loading-sm"></span>
              <.icon :if={!@grabbing?} name="hero-arrow-down-tray-mini" class="size-4" />
              Grab {map_size(@selections)} selected
            </button>
          </div>
        </section>

        <%!-- Active downloads from configured download client. Completed
        torrents are intentionally hidden — qBittorrent manages seeding. --%>
        <section class="glass-surface rounded-xl overflow-hidden">
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
    {:noreply, assign(socket, query: query, expansion_preview: Logic.expansion_preview(query))}
  end

  def handle_event("submit_search", _params, %{assigns: %{searching?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit_search", %{"query" => query}, socket) do
    trimmed = String.trim(query)

    case QueryExpander.expand(trimmed) do
      {:ok, queries} when queries != [] ->
        Enum.each(queries, fn query -> send(self(), {:run_search_one, query}) end)

        {:noreply,
         assign(socket,
           query: trimmed,
           searching?: true,
           groups: Logic.placeholder_groups(queries),
           selections: %{},
           grab_message: nil,
           expansion_preview: {:ok, length(queries)}
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_group", %{"term" => term}, socket) do
    {:noreply, assign(socket, groups: Logic.toggle_group(socket.assigns.groups, term))}
  end

  def handle_event("select_result", %{"term" => term, "guid" => guid}, socket) do
    selections =
      if Map.get(socket.assigns.selections, term) == guid do
        Map.delete(socket.assigns.selections, term)
      else
        Map.put(socket.assigns.selections, term, guid)
      end

    {:noreply, assign(socket, selections: selections)}
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
    selections = socket.assigns.selections

    if map_size(selections) == 0 do
      {:noreply, socket}
    else
      results =
        selections
        |> Map.values()
        |> Enum.map(&Logic.find_result(socket.assigns.groups, &1))
        |> Enum.reject(&is_nil/1)

      send(self(), {:run_grabs, results})
      {:noreply, assign(socket, grabbing?: true, grab_message: nil)}
    end
  end

  # ---------------------------------------------------------------------------
  # Async work + queue polling
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:run_search_one, query}, socket) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      outcome =
        try do
          Acquisition.search(query)
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      send(parent, {:search_result, query, outcome})
    end)

    {:noreply, socket}
  end

  def handle_info({:search_result, query, outcome}, socket) do
    groups = Logic.apply_search_result(socket.assigns.groups, query, outcome)

    selections =
      case Enum.find(groups, &(&1.term == query)) do
        nil -> socket.assigns.selections
        group -> Logic.add_default_selection(socket.assigns.selections, group)
      end

    searching? = not Logic.all_loaded?(groups)

    if not searching? do
      Log.info(:acquisition, "search complete — #{length(groups)} groups")
    end

    {:noreply, assign(socket, groups: groups, selections: selections, searching?: searching?)}
  end

  def handle_info({:run_grabs, results}, socket) do
    pairs = Enum.map(results, fn result -> {result, Acquisition.grab(result)} end)

    Enum.each(pairs, fn
      {result, {:error, reason}} ->
        Log.warning(:acquisition, "grab failed — #{result.title} — #{inspect(reason)}")

      _ ->
        :ok
    end)

    ok_count = Enum.count(pairs, fn {_, outcome} -> outcome == :ok end)
    err_count = length(pairs) - ok_count
    Log.info(:acquisition, "grab batch complete — #{ok_count} ok, #{err_count} failed")

    message = Logic.build_grab_message(pairs)
    {:noreply, assign(socket, grabbing?: false, grab_message: message, selections: %{})}
  end

  def handle_info(:poll_queue, socket) do
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
  end

  # Acquisition PubSub events — informational, no-op for now.
  def handle_info({:grab_submitted, _grab}, socket), do: {:noreply, socket}
  def handle_info({:grab_failed, _reason}, socket), do: {:noreply, socket}
  def handle_info({:search_retry_scheduled, _grab}, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

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
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-circle text-base-content/40 hover:text-error"
          phx-click="cancel_download_prompt"
          phx-value-id={@item.id}
          phx-value-title={@item.title}
          title="Cancel and delete"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
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
      phx-window-keydown="cancel_download_cancel"
      phx-key="Escape"
      style="z-index: 60;"
    >
      <div class="modal-panel modal-panel-sm p-6" phx-click-away="cancel_download_cancel">
        <h3 class="text-lg font-bold text-error">Cancel download?</h3>
        <p class="mt-2 text-sm text-base-content/70">
          The torrent and any downloaded files will be deleted from qBittorrent.
        </p>
        <div class="mt-3 rounded-lg bg-base-content/5 p-3 text-sm break-words">
          {@cancel_confirm.title}
        </div>
        <div class="mt-4 flex justify-end gap-2">
          <button type="button" phx-click="cancel_download_cancel" class="btn btn-ghost btn-sm">
            Keep
          </button>
          <button
            type="button"
            phx-click="cancel_download_confirm"
            class="btn btn-soft btn-error btn-sm"
          >
            Cancel download
          </button>
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
