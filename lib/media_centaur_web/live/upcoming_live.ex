defmodule MediaCentaurWeb.UpcomingLive do
  @moduledoc """
  The Upcoming page — a time-first forecast of tracked releases.

  An editorial timeline rail (the spine) with a quiet sticky mini-month
  companion. The LiveView is thin: it reads `ReleaseTracking` + `Acquisition`,
  builds the pure `UpcomingFeed` view-model (bucketing / status / hero /
  season-drop collapse) and the per-title `Detail`, and wires events. All
  classification lives in the pure modules (ADR-030); rendering lives in the
  `Components.Upcoming.*` components.

  Capability gating: `acquisition_ready` (Prowlarr + download client) gates the
  honest `:armed` status and the detail automation section; `tmdb_ready` gates
  the Track action. The view-model bakes acquisition gating into each event's
  status, so the components render an honest forecast without reading globals.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Acquisition, Capabilities, ReleaseTracking}
  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Acquisition.TargetEvents
  alias MediaCentaur.ReleaseTracking.{Item, UpcomingFeed}
  alias MediaCentaurWeb.Components.TrackModal
  alias MediaCentaurWeb.Components.Upcoming.{Detail, MiniMonth, Present, Rail, Stragglers, TitleDetail}
  alias MediaCentaurWeb.HomeLive.Logic, as: HomeLogic

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MediaCentaur.Library.subscribe()
      ReleaseTracking.subscribe()
      Acquisition.subscribe()
    end

    today = Date.utc_today()

    socket =
      assign(socket,
        loaded?: false,
        today: today,
        mini_month: {today.year, today.month},
        focused_day: nil,
        detail: nil,
        feed: %UpcomingFeed{},
        mini_month_marks: %{},
        stragglers: [],
        subtitle: "",
        grab_status_by_key: %{},
        reload_timer: nil,
        track_modal_open: false,
        track_suggestions: [],
        track_suggestions_loading: false,
        track_search_query: "",
        track_search_results: [],
        track_search_loading: false,
        track_scope_item: nil,
        track_collection_item: nil,
        track_confirmed_ids: MapSet.new()
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, ensure_loaded(socket)}
  end

  # First-render load on BOTH the disconnected (static) and connected renders so
  # the first paint already carries the forecast — never an empty-state flash.
  # The reads are local ReleaseTracking/Acquisition queries (no traffic-scaling
  # reason to defer). Desktop first-paint correctness (AGENTS.md → LiveView).
  defp ensure_loaded(socket) do
    if socket.assigns.loaded?, do: socket, else: socket |> build_view() |> assign(loaded?: true)
  end

  defp build_view(socket) do
    today = socket.assigns.today
    %{upcoming: upcoming, released: released} = ReleaseTracking.list_releases()
    releases = upcoming ++ released

    acquisition? = Capabilities.acquisition_ready?()
    default_mode = AutoGrabSettings.load().default_mode
    grab = grab_status_by_key(releases, acquisition?)
    feed = UpcomingFeed.build(releases, view_context(today, acquisition?, default_mode, grab))
    {year, month} = socket.assigns.mini_month

    assign(socket,
      feed: feed,
      grab_status_by_key: grab,
      mini_month_marks: UpcomingFeed.mini_month_marks(feed, year, month),
      stragglers: UpcomingFeed.stragglers(ReleaseTracking.list_watching_items()),
      subtitle: summary_label(feed),
      page_backdrop: page_backdrop(),
      acquisition_ready: acquisition?,
      tmdb_ready: Capabilities.tmdb_ready?()
    )
  end

  # Ambient page backdrop — the same ETS-backed hero-candidate pool the
  # home/library/downloads pages draw from, in the Upcoming page's own slot
  # (3) so the backdrop differs from the other pages when the pool allows.
  defp page_backdrop do
    case HomeLogic.select_page_hero(MediaCentaur.Library.Views.hero_candidates(), 3) do
      %{backdrop_url: url} when is_binary(url) -> url
      _no_candidate -> nil
    end
  end

  defp view_context(today, acquisition?, default_mode, grab) do
    %{
      today: today,
      acquisition_ready?: acquisition?,
      auto_grab_default_mode: default_mode,
      grab_status_by_key: grab
    }
  end

  # `%{release_key => %{pursuit_id}}` for releases under an active pursuit, the
  # input the view-model needs to mark `:under_pursuit` and deep-link Downloads.
  defp grab_status_by_key(_releases, false), do: %{}

  defp grab_status_by_key(releases, true) do
    releases
    |> Enum.map(&UpcomingFeed.release_key/1)
    |> Enum.uniq()
    |> Acquisition.statuses_for_releases()
    # `statuses_for_releases/1` also returns cancelled/complete pursuits; only an
    # ACTIVE pursuit means a release is genuinely being grabbed right now.
    |> Enum.filter(fn {_key, {pursuit, _target}} -> pursuit.state == "active" end)
    |> Map.new(fn {key, {pursuit, _target}} -> {key, %{pursuit_id: pursuit.id}} end)
  end

  defp summary_label(%UpcomingFeed{buckets: buckets}) do
    count = buckets |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    "#{count} #{if count == 1, do: "release", else: "releases"} ahead"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/upcoming"
      full_width
      acquisition_ready={@acquisition_ready}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
    >
      <:overlays>
        <TrackModal.track_modal
          open={@track_modal_open}
          suggestions={@track_suggestions}
          suggestions_loading={@track_suggestions_loading}
          search_query={@track_search_query}
          search_results={@track_search_results}
          search_loading={@track_search_loading}
          scope_item={@track_scope_item}
          collection_item={@track_collection_item}
          confirmed_ids={@track_confirmed_ids}
        />
        <TitleDetail.title_detail :if={@detail} detail={@detail} today={@today} />
      </:overlays>

      <%!-- Outer relative wrapper carries the page-behavior + default zone and
            scopes the ambient backdrop, matching the library/downloads page
            shell exactly so the heading sits at the same height across all
            three pages. --%>
      <div class="relative" data-page-behavior="upcoming" data-nav-default-zone="upcoming">
        <%!-- Ambient backdrop band (masked + dimmed via `.page-atmosphere`) plus
              the fixed side scrim, both behind the content (z-0) so they enrich
              the surface, never the cards — same recipe as library/downloads. --%>
        <div :if={@page_backdrop} class="page-atmosphere" aria-hidden="true">
          <img src={@page_backdrop} alt="" loading="eager" decoding="sync" />
        </div>
        <div :if={@page_backdrop} class="page-side-dim" aria-hidden="true"></div>

        <div class="relative z-[1] space-y-6">
          <header class="flex items-start justify-between gap-3">
            <div>
              <h1 class="text-3xl font-bold tracking-tight">Upcoming</h1>
              <p class="mt-1 text-sm text-base-content/60">{@subtitle}</p>
            </div>
            <div :if={@tmdb_ready} data-nav-zone="actions">
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-lg border border-base-content/10 px-3 py-1.5 text-sm text-base-content/80 transition-colors hover:bg-base-content/[0.06]"
                data-nav-item
                tabindex="0"
                phx-click="open_track_modal"
              >
                <.icon name="hero-plus-mini" class="size-4" />
                <span>Track something</span>
              </button>
            </div>
          </header>

          <div class="grid grid-cols-1 gap-6 lg:grid-cols-[1fr_300px]">
            <div class="space-y-8">
              <Rail.rail feed={@feed} today={@today} />
              <Stragglers.stragglers stragglers={@stragglers} />
            </div>

            <%!-- Nudge the companion down so the calendar's top edge lines up
                  with the first hero card (which sits below its bucket marker)
                  rather than with the marker — visual balance at lg+. --%>
            <div class="lg:mt-7">
              <div class="lg:sticky lg:top-6">
                <MiniMonth.mini_month
                  year={elem(@mini_month, 0)}
                  month={elem(@mini_month, 1)}
                  today={@today}
                  focused_day={@focused_day}
                  marks={@mini_month_marks}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Rail / mini-month / detail events ---

  @impl true
  def handle_event("select_event", %{"item-id" => item_id}, socket) do
    {:noreply, assign(socket, detail: build_detail(socket, item_id))}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, detail: nil)}
  end

  def handle_event("mini_month_prev", _params, socket) do
    {:noreply, shift_month(socket, -1)}
  end

  def handle_event("mini_month_next", _params, socket) do
    {:noreply, shift_month(socket, +1)}
  end

  def handle_event("jump_to_day", %{"date" => iso}, socket) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> {:noreply, assign(socket, focused_day: date)}
      _error -> {:noreply, socket}
    end
  end

  def handle_event("toggle_auto_grab", %{"item-id" => item_id}, socket) do
    with %Item{} = item <- ReleaseTracking.get_item(item_id) do
      default = AutoGrabSettings.load().default_mode
      summary = Present.auto_grab_summary(item.auto_grab_mode, default, socket.assigns.acquisition_ready)

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

  # --- Track modal events (reused as-is) ---

  def handle_event("open_track_modal", _params, socket) do
    socket =
      assign(socket,
        track_modal_open: true,
        track_suggestions_loading: true,
        track_search_query: "",
        track_search_results: [],
        track_scope_item: nil,
        track_collection_item: nil
      )

    send(self(), :load_track_suggestions)
    {:noreply, socket}
  end

  def handle_event("close_track_modal", _params, socket) do
    {:noreply,
     assign(socket,
       track_modal_open: false,
       track_suggestions: [],
       track_suggestions_loading: false,
       track_search_query: "",
       track_search_results: [],
       track_search_loading: false,
       track_scope_item: nil,
       track_collection_item: nil,
       track_confirmed_ids: MapSet.new()
     )}
  end

  def handle_event("track_search", %{"query" => query}, socket) when byte_size(query) < 2 do
    {:noreply,
     assign(socket, track_search_query: query, track_search_results: [], track_search_loading: false)}
  end

  def handle_event("track_search", %{"query" => query}, socket) do
    socket = assign(socket, track_search_query: query, track_search_loading: true)
    send(self(), {:do_track_search, query})
    {:noreply, socket}
  end

  def handle_event("track_suggestion", params, socket) do
    tmdb_id = String.to_integer(params["tmdb-id"])
    tmdb_id_str = to_string(tmdb_id)
    confirmed = socket.assigns.track_confirmed_ids

    if MapSet.member?(confirmed, tmdb_id_str) do
      case ReleaseTracking.get_item_by_tmdb(tmdb_id, :tv_series) do
        nil -> :ok
        item -> ReleaseTracking.delete_item(item)
      end

      {:noreply, assign(socket, track_confirmed_ids: MapSet.delete(confirmed, tmdb_id_str))}
    else
      {last_season, last_episode} = ReleaseTracking.find_last_library_episode(params["tv-series-id"])

      ReleaseTracking.track_from_search_async(
        %{tmdb_id: tmdb_id, media_type: :tv_series, name: params["name"], poster_path: nil},
        %{start_season: last_season, start_episode: last_episode}
      )

      {:noreply, assign(socket, track_confirmed_ids: MapSet.put(confirmed, tmdb_id_str))}
    end
  end

  def handle_event("select_search_result", params, socket) do
    tmdb_id = String.to_integer(params["tmdb-id"])

    case String.to_existing_atom(params["media-type"]) do
      :tv_series ->
        scope_item = %TrackModal.ScopeItem{
          tmdb_id: tmdb_id,
          name: params["name"],
          poster_path: params["poster-path"]
        }

        {:noreply, assign(socket, track_scope_item: scope_item, track_collection_item: nil)}

      :movie ->
        ReleaseTracking.track_from_search_async(
          %{
            tmdb_id: tmdb_id,
            media_type: :movie,
            name: params["name"],
            poster_path: params["poster-path"]
          },
          %{}
        )

        {:noreply,
         assign(socket,
           track_search_results: mark_tracked(socket.assigns.track_search_results, tmdb_id),
           track_collection_item: nil
         )}
    end
  end

  def handle_event("confirm_track", params, socket) do
    tmdb_id = String.to_integer(params["tmdb_id"])

    {start_season, start_episode} =
      case params["scope"] do
        "custom" ->
          {String.to_integer(params["start_season"] || "1"),
           String.to_integer(params["start_episode"] || "1")}

        _all ->
          {0, 0}
      end

    ReleaseTracking.track_from_search_async(
      %{
        tmdb_id: tmdb_id,
        media_type: :tv_series,
        name: params["name"],
        poster_path: params["poster_path"]
      },
      %{start_season: start_season, start_episode: start_episode}
    )

    {:noreply,
     assign(socket,
       track_search_results: mark_tracked(socket.assigns.track_search_results, tmdb_id),
       track_scope_item: nil
     )}
  end

  # --- PubSub ---

  @impl true
  def handle_info({:releases_updated, _item_ids}, socket) do
    {:noreply, debounce(socket, :reload_timer, :reload_view, 500)}
  end

  def handle_info({:entities_changed, %{entity_ids: _ids}}, socket) do
    {:noreply, debounce(socket, :reload_timer, :reload_view, 500)}
  end

  def handle_info(:reload_view, socket) do
    {:noreply, build_view(socket)}
  end

  def handle_info(:capabilities_changed, socket) do
    {:noreply, build_view(socket)}
  end

  def handle_info(:load_track_suggestions, socket) do
    suggestions =
      Enum.map(ReleaseTracking.suggest_trackable_items(), &struct!(TrackModal.Suggestion, &1))

    {:noreply, assign(socket, track_suggestions: suggestions, track_suggestions_loading: false)}
  end

  def handle_info({:do_track_search, query}, socket) do
    if query == socket.assigns.track_search_query do
      results = Enum.map(ReleaseTracking.search_tmdb(query), &struct!(TrackModal.SearchResult, &1))
      {:noreply, assign(socket, track_search_results: results, track_search_loading: false)}
    else
      {:noreply, socket}
    end
  end

  # Acquisition target lifecycle ticks invalidate per-release status — rebuild
  # the forecast (debounced). Kept last: matches any struct message.
  def handle_info(%struct{}, socket) do
    if TargetEvents.event?(struct) do
      {:noreply, debounce(socket, :reload_timer, :reload_view, 500)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Detail building ---

  defp build_detail(socket, item_id) do
    case ReleaseTracking.get_item(item_id) do
      nil ->
        nil

      item ->
        acquisition? = socket.assigns.acquisition_ready
        default_mode = AutoGrabSettings.load().default_mode

        releases =
          item_id
          |> ReleaseTracking.list_releases_for_item()
          |> Enum.map(&%{&1 | item: item})

        context =
          view_context(
            socket.assigns.today,
            acquisition?,
            default_mode,
            socket.assigns.grab_status_by_key
          )

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

  # --- Helpers ---

  defp shift_month(socket, delta) do
    {year, month} = socket.assigns.mini_month
    anchor = Date.new!(year, month, 1)

    pivot =
      if delta < 0,
        do: Date.add(anchor, -1),
        else: Date.add(Date.end_of_month(anchor), 1)

    next = {pivot.year, pivot.month}

    assign(socket,
      mini_month: next,
      mini_month_marks: UpcomingFeed.mini_month_marks(socket.assigns.feed, pivot.year, pivot.month)
    )
  end

  defp mark_tracked(results, tmdb_id) do
    Enum.map(results, fn result ->
      if result.tmdb_id == tmdb_id, do: %{result | already_tracked: true}, else: result
    end)
  end
end
