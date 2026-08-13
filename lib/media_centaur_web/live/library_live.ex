defmodule MediaCentaurWeb.LibraryLive do
  @moduledoc """
  Library Browse page — the full entity catalog as a poster grid with
  type tabs, sort, and text filter. Selecting an entity opens a
  DetailPanel detail overlay. Mounted at `/library`.

  ## Read path (Library Schema v2 Phase 3.1)

  The grid reads from the `Library.Views.Browse` ETS projection
  (ADR-041) — pre-shaped `BrowseItem` structs in recent-first
  (`inserted_at desc`) order. Progress and availability live in
  separate per-id maps populated via the bulk context functions
  `Library.ProgressRecords.summaries/1` and
  `Library.Availability.available_for_ids/1`. The mount issues a
  bounded number of queries that does not scale with catalog size.

  ## Update path

  Subscriptions split by concern:

    * `library:views` — projection refresh broadcasts. On
      `{:library_view_updated, :browse}` the LiveView re-reads
      `Views.browse/0` (microsecond ETS lookup) and refreshes the
      progress + availability maps.
    * `library:updates` — wired by the EntityModal hook for the
      selected modal state; the grid no longer reacts directly.
    * `playback:events` — pulse dot + flash on `playback_state_changed`
      / `playback_failed`.
    * `library:availability` — drive-mount / unmount events.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.EntityModal
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LibraryCardInfoAware
  use MediaCentaurWeb.Live.LibraryBackdropAware

  alias MediaCentaur.{
    Library,
    Library.Availability
  }

  alias MediaCentaur.Pipeline.Stats

  alias MediaCentaurWeb.Components.LibraryCards
  alias MediaCentaurWeb.HomeLive.Logic

  import MediaCentaurWeb.LibraryHelpers
  import MediaCentaurWeb.LibraryFormatters
  import MediaCentaurWeb.LibraryAvailability

  @impl true
  def mount(_params, _session, socket) do
    # `Library.subscribe()` and `Playback.subscribe()` are auto-wired
    # by the EntityModal on_mount callback; `Settings.subscribe()` by
    # SpoilerFreeAware; `Capabilities.subscribe()` by CapabilitiesAware.
    # Do not duplicate any of them here.
    if connected?(socket) do
      Library.Views.subscribe()
      Availability.subscribe()
      MediaCentaur.Config.subscribe()
      Process.send_after(self(), :tick_pipeline, 1_000)
    end

    {:ok,
     socket
     |> assign(
       loaded?: false,
       entries: [],
       progress_by_id: %{},
       availability_map: %{},
       visible_ids: MapSet.new(),
       hero_backdrop: nil,
       active_tab: :all,
       sort_order: :recent,
       sort_open: false,
       sort_highlight: 0,
       filter_text: "",
       counts: %{all: 0, movies: 0, tv: 0},
       grid_count: 0,
       unavailable_count: 0,
       media_dirs: MediaCentaur.Config.get(:media_dirs) || [],
       media_dirs_configured: media_dirs_configured?(),
       dir_status: Availability.dir_status(),
       pipeline_queue_depth: 0,
       scanning: false,
       scan_task: nil
     )
     |> stream_configure(:grid, dom_id: &"entity-#{&1.id}")
     |> stream(:grid, [])}
  end

  @doc """
  True when at least one `media_dirs` entry is configured — used by
  the empty-state branch to decide between "no media yet" (user hasn't
  set up a library root) and "media_dirs configured but no files found".
  """
  def media_dirs_configured?(dirs \\ MediaCentaur.Config.get(:media_dirs)) do
    case dirs do
      list when is_list(list) and list != [] -> true
      _ -> false
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    was_loaded? = socket.assigns.loaded?
    socket = ensure_loaded(socket)
    just_loaded = not was_loaded? and socket.assigns.loaded?

    tab = parse_tab(params["tab"])
    sort = parse_sort(params["sort"])
    filter_text = params["filter"] || ""

    grid_changed =
      just_loaded ||
        tab != socket.assigns.active_tab ||
        sort != socket.assigns.sort_order ||
        filter_text != socket.assigns.filter_text

    socket =
      socket
      |> assign(
        active_tab: tab,
        sort_order: sort,
        filter_text: filter_text
      )
      |> then(fn socket -> if grid_changed, do: cache_visible_ids(socket), else: socket end)
      |> apply_modal_params(params)
      |> then(fn socket -> if grid_changed, do: reset_stream(socket), else: socket end)

    {:noreply, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(
           %{socket | assigns: Map.put(socket.assigns, :active_tab, parse_tab(tab))},
           %{}
         )
     )}
  end

  # Order must match `LibraryCards.@sort_options` — the keyboard
  # highlight index selects from this list while the component renders
  # the menu from its own.
  @sort_options [:recent, :watched, :alpha, :year]

  def handle_event("toggle_sort", _params, socket) do
    if socket.assigns.sort_open do
      {:noreply, assign(socket, sort_open: false)}
    else
      highlight = Enum.find_index(@sort_options, &(&1 == socket.assigns.sort_order)) || 0
      {:noreply, assign(socket, sort_open: true, sort_highlight: highlight)}
    end
  end

  def handle_event("close_sort", _params, socket) do
    {:noreply, assign(socket, sort_open: false)}
  end

  def handle_event("sort_key", %{"key" => key}, socket) do
    sort_key(key, socket)
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    sort = parse_sort(sort)

    socket = assign(socket, sort_open: false)

    {:noreply,
     push_patch(socket,
       to: build_path(%{socket | assigns: Map.put(socket.assigns, :sort_order, sort)}, %{})
     )}
  end

  def handle_event("filter", %{"filter_text" => text}, socket) do
    {:noreply,
     push_patch(socket,
       to: build_path(%{socket | assigns: Map.put(socket.assigns, :filter_text, text)}, %{}),
       replace: true
     )}
  end

  # Inline × on the search box — drop only the text filter, preserving the
  # active tab and sort.
  def handle_event("clear_filter", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{filter: ""}))}
  end

  # "Clear filters" in the no-matches empty state — reset every filter that
  # can hide a card (tab, text) so the grid is guaranteed to repopulate;
  # sort is a presentation choice, not a filter, so it stays.
  def handle_event("reset_filters", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{tab: :all, filter: ""}))}
  end

  # Run on a supervised Task so the socket stays responsive — a
  # synchronous call would block render and the "Scanning…" label would
  # never appear. Same pattern as `SettingsLive.handle_event("scan", ...)`.
  def handle_event("scan", _params, socket) do
    task =
      Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn ->
        MediaCentaur.Watcher.Supervisor.scan()
      end)

    {:noreply, assign(socket, scanning: true, scan_task: task)}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:library_view_updated, :browse}, socket) do
    # The Browse projection refreshed; re-read everything from scratch.
    # The projection itself broadcasts coalesced events upstream, so we
    # do not need to debounce here.
    {:noreply,
     socket
     |> load_library()
     |> cache_visible_ids()
     |> reset_stream()}
  end

  def handle_info({:entity_progress_updated, %{entity_id: entity_id}}, socket) do
    # The EntityModal hook keeps `:selected_entry`'s progress fresh on
    # its own. Here we refresh just the affected card's progress
    # summary so the bar / completion overlay reflects the change.
    updated_summaries = Library.ProgressRecords.summaries([entity_id])

    progress_by_id =
      case Map.get(updated_summaries, entity_id) do
        nil -> Map.delete(socket.assigns.progress_by_id, entity_id)
        summary -> Map.put(socket.assigns.progress_by_id, entity_id, summary)
      end

    {:noreply,
     socket
     |> assign(progress_by_id: progress_by_id)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info({:playback_state_changed, %{entity_id: entity_id}}, socket) do
    # The EntityModal hook owns the `:playback` map. Here we only
    # re-render the affected poster card so the "playing" badge
    # appears/disappears.
    {:noreply, touch_stream_entries(socket, [entity_id])}
  end

  def handle_info({:playback_failed, %{payload: payload}}, socket) do
    {:noreply, put_flash(socket, :error, playback_failed_flash(payload))}
  end

  def handle_info({:availability_changed, _dir, state}, socket) do
    availability_map = availability_map(socket.assigns.entries)

    socket =
      assign(socket,
        dir_status: Availability.dir_status(),
        availability_map: availability_map,
        unavailable_count: Enum.count(availability_map, fn {_id, available} -> not available end)
      )

    # When storage comes back online, reset the grid stream so the
    # browser re-requests images instead of serving cached 404s.
    socket =
      if state == :watching do
        stream(socket, :grid, socket.assigns.entries, reset: true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:config_updated, :media_dirs, _entries}, socket) do
    {:noreply,
     assign(socket,
       media_dirs: MediaCentaur.Config.get(:media_dirs) || [],
       media_dirs_configured: media_dirs_configured?()
     )}
  end

  # `LibraryCardInfoAware` has already updated `:show_card_info` via its
  # `attach_hook`; we reset the grid stream so existing card items
  # re-render with the new `show_info` attr (stream items are not part
  # of subsequent diffs — they only re-render when the stream is reset).
  def handle_info({:setting_changed, "library_show_card_info", _value}, socket) do
    {:noreply, stream(socket, :grid, socket.assigns.entries, reset: true)}
  end

  # Polled once per second so the empty-state can show "Ingesting N
  # files…" while the pipeline drains. Same cadence StatusLive uses.
  # Cheap: Pipeline.Stats keeps the snapshot in ETS, no DB query.
  def handle_info(:tick_pipeline, socket) do
    Process.send_after(self(), :tick_pipeline, 1_000)
    snapshot = Stats.get_snapshot()
    depth = snapshot.discovery_queue_depth + snapshot.import_queue_depth
    {:noreply, assign(socket, pipeline_queue_depth: depth)}
  end

  # Reply from the async scan Task. Matches on the stored ref so we
  # don't confuse it with any other async_nolink result on this socket.
  def handle_info({ref, {:ok, _count}}, %{assigns: %{scan_task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, scanning: false, scan_task: nil)}
  end

  # Scan task exit — either after its result was reaped above or after
  # a future Task.shutdown. Clear the ref either way.
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{scan_task: %Task{ref: ref}}} = socket
      ) do
    {:noreply, assign(socket, scan_task: nil)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    offline_summary = offline_summary(assigns.dir_status, assigns.unavailable_count)

    assigns = assign(assigns, :offline_summary, offline_summary)

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/library"
      full_width
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <div
        class="relative"
        data-page-behavior="library"
        data-nav-default-zone="library"
        data-nav-transient-params="selected,view,autoplay"
      >
        <%!-- Calm backdrop band behind the header — a sense of place that
              ties the browse page to the home page's visual language without
              a full hero. Masked + dimmed by `.page-atmosphere`. Off when the
              user disables the Library backdrop preference. --%>
        <div :if={@hero_backdrop && @library_backdrop} class="page-atmosphere" aria-hidden="true">
          <img
            src={sized_image_url(@hero_backdrop, :full_bleed)}
            alt=""
            loading="eager"
            decoding="sync"
          />
        </div>
        <%!-- Same fixed dark scrim the home page uses (left-weighted + a
              vertical dim that holds down the page) so the library reads as a
              rich dark surface rather than flat grey. It sits behind the grid
              (z-0), so it darkens the background, never the posters.
              Unconditional — the scrim carries the page's depth with or
              without the artwork band. --%>
        <div class="page-side-dim" aria-hidden="true"></div>

        <div class="relative z-[1]">
          <header class="mb-5">
            <h1 class="text-3xl font-bold tracking-tight">Library</h1>
            <p class="mt-1 text-sm text-base-content/60">
              {count_label(@counts.movies, "movie")} · {count_label(@counts.tv, "show")}
            </p>
          </header>

          <%!-- Storage offline banner --%>
          <LibraryCards.storage_offline_banner :if={@offline_summary} summary={@offline_summary} />

          <%!-- Library Browse zone --%>
          <section id="browse">
            <LibraryCards.toolbar
              active_tab={@active_tab}
              sort_order={@sort_order}
              sort_open={@sort_open}
              sort_highlight={@sort_highlight}
              filter_text={@filter_text}
            />

            <%!-- Genuinely-empty library: prompt to scan or configure. --%>
            <div
              :if={empty_grid_reason(@grid_count, @counts.all) == :library_empty}
              class="py-8 text-center empty-state-enter space-y-3"
            >
              <div :if={@media_dirs_configured} class="max-w-md mx-auto space-y-3">
                <p class="text-base-content/80">No media yet.</p>
                <p :if={@pipeline_queue_depth > 0} class="text-sm opacity-70">
                  Ingesting {@pipeline_queue_depth} file{if @pipeline_queue_depth == 1,
                    do: "",
                    else: "s"}…
                </p>
                <.button
                  variant="primary"
                  size="sm"
                  phx-click="scan"
                  disabled={@scanning}
                  data-nav-item
                >
                  {if @scanning, do: "Scanning…", else: "Scan media directories"}
                </.button>
              </div>
              <div :if={not @media_dirs_configured} class="max-w-md mx-auto space-y-2">
                <p class="text-base-content/80">
                  No media yet — tell Media Centaur where your files live.
                </p>
                <.button
                  variant="primary"
                  size="sm"
                  navigate={~p"/settings?section=library"}
                  data-nav-item
                >
                  Configure library
                </.button>
              </div>
            </div>

            <%!-- Library has entries but the active filter hid them all:
                  offer to clear the filter, never to scan. --%>
            <div
              :if={empty_grid_reason(@grid_count, @counts.all) == :no_matches}
              class="py-8 text-center empty-state-enter space-y-3"
            >
              <div class="max-w-md mx-auto space-y-3">
                <p class="text-base-content/80">{no_matches_label(@filter_text)}</p>
                <.button variant="dismiss" size="sm" phx-click="reset_filters" data-nav-item>
                  Clear filters
                </.button>
              </div>
            </div>

            <div :if={@grid_count > 0} data-nav-zone="grid" class="mt-4">
              <div
                id="library-grid"
                phx-update="stream"
                class="poster-grid poster-grid-dense"
                data-nav-grid
              >
                <LibraryCards.poster_card
                  :for={{dom_id, entry} <- @streams.grid}
                  id={dom_id}
                  entry={entry}
                  progress={Map.get(@progress_by_id, entry.id)}
                  selected={@selected_entity_id == entry.id}
                  playing={playing?(@playback, entry.id)}
                  available={Map.get(@availability_map, entry.id, true)}
                  show_info={@show_card_info}
                />
              </div>
            </div>
          </section>
        </div>

        <%!-- Detail modal (always in DOM for smooth backdrop-filter) --%>
        <.entity_modal
          selected_entry={@selected_entry}
          selected_entity_id={@selected_entity_id}
          selected_member_id={@selected_member_id}
          detail_presentation={@detail_presentation}
          detail_view={@detail_view}
          cast_filter={@cast_filter}
          cast_limit={@cast_limit}
          detail_files={@detail_files}
          expanded_file_groups={@expanded_file_groups}
          expanded_seasons={@expanded_seasons}
          expanded_item_details={@expanded_item_details}
          all_episode_details_open={@all_episode_details_open}
          rematch_confirm={@rematch_confirm}
          delete_confirm={@delete_confirm}
          deleting={@deleting}
          tracking_status={@tracking_status}
          availability_map={@availability_map}
          tmdb_ready={@tmdb_ready}
          spoiler_free={@spoiler_free}
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Data Loading ---

  # First-render data load — gated by `connected?` so the static HTTP
  # render ships empty defaults and the WebSocket render fills them in
  # once. See AGENTS.md → LiveView callbacks (Iron Law).
  # Loads on BOTH the disconnected (static) render and the connected
  # render — deliberately NOT gated on `connected?/1`. This is a desktop
  # app (UIDR-012): the first paint must already carry real data, never the
  # 0-count / empty-grid mount placeholders that would otherwise flash
  # before the socket connects. The read is cheap (a `Library.Views.browse`
  # ETS lookup plus a bounded set of local SQLite queries), so building it
  # once more on the static render is the right trade. Do not re-add a
  # `connected?` gate "to avoid the double load" — that reintroduces the
  # flash.
  defp ensure_loaded(socket) do
    if socket.assigns.loaded? do
      socket
    else
      socket
      |> load_library()
      |> assign(loaded?: true)
    end
  end

  defp load_library(socket) do
    entries = Library.Views.browse()
    ids = Enum.map(entries, & &1.id)
    progress_by_id = Library.ProgressRecords.summaries(ids)
    availability_map = Availability.available_for_ids(ids)

    assign(socket,
      entries: entries,
      progress_by_id: progress_by_id,
      availability_map: availability_map,
      unavailable_count: Enum.count(availability_map, fn {_id, available} -> not available end),
      counts: tab_counts(entries),
      hero_backdrop: library_backdrop(),
      playback: load_playback_sessions()
    )
  end

  # The header atmosphere draws from the same hero-candidate pool as the
  # home page (ETS read, no DB query), but `select_alt_hero/1` deliberately
  # picks a *different* candidate than the home hero whenever the pool has
  # 2+ entries — so the two pages show two distinct backdrops. Re-read on
  # every `load_library/1` (browse refresh).
  defp library_backdrop do
    case Logic.select_alt_hero(Library.Views.hero_candidates()) do
      %{backdrop_url: url} when is_binary(url) -> url
      _ -> nil
    end
  end

  # --- Stream Management ---

  defp reset_stream(socket) do
    filtered = compute_filtered(socket)

    socket
    |> stream(:grid, filtered, reset: true)
    |> assign(grid_count: length(filtered))
  end

  defp touch_stream_entries(socket, entity_ids) do
    filtered_ids = socket.assigns.visible_ids
    by_id = entries_index(socket.assigns.entries)

    Enum.reduce(entity_ids, socket, fn id, sock ->
      entry = Map.get(by_id, id)

      cond do
        entry == nil ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")

        MapSet.member?(filtered_ids, id) ->
          stream_insert(sock, :grid, entry)

        true ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")
      end
    end)
  end

  defp entries_index(entries), do: Map.new(entries, &{&1.id, &1})

  defp compute_filtered(socket) do
    assigns = socket.assigns

    assigns.entries
    |> filtered_by_tab(assigns.active_tab)
    |> filtered_by_text(assigns.filter_text)
    |> sorted_by(assigns.sort_order, assigns.progress_by_id)
  end

  # Caches the filtered visible-ID set so subsequent
  # `touch_stream_entries` calls (one per PubSub event burst) read O(1)
  # from assigns instead of rescanning `entries`. Invalidate by calling
  # this whenever `entries` or any filter assign (active_tab,
  # filter_text) changes.
  defp cache_visible_ids(socket) do
    assigns = socket.assigns

    visible_ids =
      assigns.entries
      |> filtered_by_tab(assigns.active_tab)
      |> filtered_by_text(assigns.filter_text)
      |> MapSet.new(& &1.id)

    assign(socket, visible_ids: visible_ids)
  end

  # --- Sort Dropdown Keyboard ---

  defp sort_key("Enter", socket) do
    if socket.assigns.sort_open do
      selected = Enum.at(@sort_options, socket.assigns.sort_highlight)
      socket = assign(socket, sort_open: false)

      {:noreply,
       push_patch(socket,
         to: build_path(%{socket | assigns: Map.put(socket.assigns, :sort_order, selected)}, %{})
       )}
    else
      highlight = Enum.find_index(@sort_options, &(&1 == socket.assigns.sort_order)) || 0
      {:noreply, assign(socket, sort_open: true, sort_highlight: highlight)}
    end
  end

  defp sort_key("Escape", socket) do
    {:noreply, assign(socket, sort_open: false)}
  end

  defp sort_key("ArrowDown", socket) do
    if socket.assigns.sort_open do
      max = length(@sort_options) - 1
      highlight = min(socket.assigns.sort_highlight + 1, max)
      {:noreply, assign(socket, sort_highlight: highlight)}
    else
      {:noreply, socket}
    end
  end

  defp sort_key("ArrowUp", socket) do
    if socket.assigns.sort_open do
      highlight = max(socket.assigns.sort_highlight - 1, 0)
      {:noreply, assign(socket, sort_highlight: highlight)}
    else
      {:noreply, socket}
    end
  end

  defp sort_key(_key, socket), do: {:noreply, socket}

  # --- URL Params ---

  defp parse_tab("movies"), do: :movies
  defp parse_tab("tv"), do: :tv
  defp parse_tab(_), do: :all

  defp parse_sort("alpha"), do: :alpha
  defp parse_sort("year"), do: :year
  defp parse_sort("watched"), do: :watched
  defp parse_sort(_), do: :recent

  @impl true
  def build_modal_path(socket, overrides), do: build_path(socket, overrides)

  # Build a URL path preserving current socket state with overrides.
  # Page-level params here; the modal slice comes whole from
  # `EntityModal.modal_query_params/2` so it can't drift per host.
  defp build_path(socket, overrides) do
    assigns = socket.assigns

    tab = Map.get(overrides, :tab, assigns.active_tab)
    sort = Map.get(overrides, :sort, assigns.sort_order)
    filter = Map.get(overrides, :filter, assigns.filter_text)

    params = %{}
    params = if tab == :all, do: params, else: Map.put(params, :tab, tab)
    params = if sort == :recent, do: params, else: Map.put(params, :sort, sort)
    params = if filter == "", do: params, else: Map.put(params, :filter, filter)
    params = Map.merge(params, EntityModal.modal_query_params(assigns, overrides))

    if params == %{}, do: ~p"/library", else: ~p"/library?#{params}"
  end

  # --- Helpers ---

  defp playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)
end
