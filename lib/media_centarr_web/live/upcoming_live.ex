defmodule MediaCentarrWeb.UpcomingLive do
  @moduledoc """
  Standalone Upcoming page — calendar + tracking + active shows + recent
  changes + unscheduled.

  Extracted from LibraryLive zone-3 in the page-redistribution refactor
  (see docs/plans/2026-04-27-page-redistribution.md). The existing
  `MediaCentarrWeb.Components.UpcomingCards` component does all rendering;
  this LiveView wires assigns and PubSub subscriptions.

  Phase 3 leaves the LibraryLive Upcoming zone in place for backward
  compatibility — Phase 4 will remove it.
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Acquisition, Capabilities, ReleaseTracking}
  alias MediaCentarrWeb.Components.{TrackModal, UpcomingCards}

  # Acquisition events that only invalidate grab statuses — not the underlying
  # release / image / tracked-item data. Routing them to a dedicated reloader
  # keeps the page from rebuilding the full upcoming model on every grab tick.
  @grab_status_events [
    :grab_submitted,
    :auto_grab_armed,
    :auto_grab_snoozed,
    :auto_grab_abandoned,
    :auto_grab_cancelled
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MediaCentarr.Library.subscribe()
      ReleaseTracking.subscribe()
      Acquisition.subscribe()
      Acquisition.subscribe_queue()
      Capabilities.subscribe()
    end

    today = Date.utc_today()

    socket =
      assign(socket,
        loaded?: false,
        calendar_month: {today.year, today.month},
        selected_day: nil,
        confirm_stop_item: nil,
        tmdb_ready: false,
        acquisition_ready: false,
        queue_items: [],
        track_modal_open: false,
        track_suggestions: [],
        track_suggestions_loading: false,
        track_search_query: "",
        track_search_results: [],
        track_search_loading: false,
        track_scope_item: nil,
        track_collection_item: nil,
        track_confirmed_ids: MapSet.new(),
        upcoming_releases: %{upcoming: [], released: []},
        upcoming_events: [],
        upcoming_images: %{},
        release_grab_statuses: %{},
        tracked_items: [],
        reload_timer: nil,
        grab_statuses_timer: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, ensure_loaded(socket)}
  end

  # First-render data load — gated by `connected?` so the static HTTP render
  # ships empty defaults and the WebSocket render fills them in once. See
  # AGENTS.md → LiveView callbacks (Iron Law).
  defp ensure_loaded(socket) do
    if connected?(socket) and not socket.assigns.loaded? do
      socket
      |> assign(
        tmdb_ready: Capabilities.tmdb_ready?(),
        queue_items: Acquisition.queue_snapshot()
      )
      |> load_upcoming()
      |> assign(:loaded?, true)
    else
      socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/upcoming" full_width>
      <div class="space-y-6 py-2">
        <div class="flex items-baseline justify-between">
          <h1 class="text-2xl font-bold">Upcoming</h1>
        </div>

        <UpcomingCards.upcoming_zone
          releases={@upcoming_releases}
          events={@upcoming_events}
          images={@upcoming_images}
          calendar_month={@calendar_month}
          selected_day={@selected_day}
          tracked_items={@tracked_items}
          confirm_stop_item={@confirm_stop_item}
          tmdb_ready={@tmdb_ready}
          grab_statuses={@release_grab_statuses}
          queue_items={@queue_items}
          acquisition_ready={@acquisition_ready}
        />

        <%!-- Track New Show modal (always in DOM) --%>
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
      </div>
    </Layouts.app>
    """
  end

  # --- Events ---

  @impl true
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
     assign(socket,
       track_search_query: query,
       track_search_results: [],
       track_search_loading: false
     )}
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
      tv_series_id = params["tv-series-id"]
      name = params["name"]

      {last_season, last_episode} =
        ReleaseTracking.find_last_library_episode(tv_series_id)

      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        ReleaseTracking.track_from_search(
          %{tmdb_id: tmdb_id, media_type: :tv_series, name: name, poster_path: nil},
          %{start_season: last_season, start_episode: last_episode}
        )
      end)

      {:noreply, assign(socket, track_confirmed_ids: MapSet.put(confirmed, tmdb_id_str))}
    end
  end

  def handle_event("select_search_result", params, socket) do
    tmdb_id = String.to_integer(params["tmdb-id"])
    media_type = String.to_existing_atom(params["media-type"])
    name = params["name"]
    poster_path = params["poster-path"]

    result = %{tmdb_id: tmdb_id, media_type: media_type, name: name, poster_path: poster_path}

    case media_type do
      :tv_series ->
        {:noreply, assign(socket, track_scope_item: result, track_collection_item: nil)}

      :movie ->
        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          ReleaseTracking.track_from_search(result, %{})
        end)

        results =
          Enum.map(socket.assigns.track_search_results, fn r ->
            if r.tmdb_id == tmdb_id, do: Map.put(r, :already_tracked, true), else: r
          end)

        {:noreply, assign(socket, track_search_results: results, track_collection_item: nil)}
    end
  end

  def handle_event("confirm_track", params, socket) do
    tmdb_id = String.to_integer(params["tmdb_id"])
    name = params["name"]
    poster_path = params["poster_path"]

    {start_season, start_episode} =
      case params["scope"] do
        "custom" ->
          {String.to_integer(params["start_season"] || "1"),
           String.to_integer(params["start_episode"] || "1")}

        _ ->
          {0, 0}
      end

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      ReleaseTracking.track_from_search(
        %{tmdb_id: tmdb_id, media_type: :tv_series, name: name, poster_path: poster_path},
        %{start_season: start_season, start_episode: start_episode}
      )
    end)

    results =
      Enum.map(socket.assigns.track_search_results, fn r ->
        if r.tmdb_id == tmdb_id, do: Map.put(r, :already_tracked, true), else: r
      end)

    {:noreply, assign(socket, track_search_results: results, track_scope_item: nil)}
  end

  def handle_event("dismiss_release", %{"release-id" => release_id}, socket) do
    ReleaseTracking.dismiss_release(release_id)
    {:noreply, socket}
  end

  def handle_event("queue_all_show", %{"item-id" => item_id}, socket) do
    case Acquisition.enqueue_all_pending_for_item(item_id) do
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Show not found — couldn't queue")}

      {:ok, summary} ->
        {kind, message} = queue_all_summary_message(summary)
        {:noreply, put_flash(socket, kind, message)}
    end
  end

  def handle_event("stop_tracking", %{"item-id" => item_id}, socket) do
    case ReleaseTracking.get_item(item_id) do
      nil -> {:noreply, socket}
      item -> {:noreply, assign(socket, confirm_stop_item: item)}
    end
  end

  def handle_event("confirm_stop_tracking", _params, socket) do
    case socket.assigns.confirm_stop_item do
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

        {:noreply, assign(socket, confirm_stop_item: nil)}
    end
  end

  def handle_event("cancel_stop_tracking", _params, socket) do
    {:noreply, assign(socket, confirm_stop_item: nil)}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = socket.assigns.calendar_month
    date = Date.add(Date.new!(year, month, 1), -1)
    {:noreply, assign(socket, calendar_month: {date.year, date.month}, selected_day: nil)}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = socket.assigns.calendar_month
    last_day = Date.end_of_month(Date.new!(year, month, 1))
    date = Date.add(last_day, 1)
    {:noreply, assign(socket, calendar_month: {date.year, date.month}, selected_day: nil)}
  end

  def handle_event("jump_today", _params, socket) do
    today = Date.utc_today()
    {:noreply, assign(socket, calendar_month: {today.year, today.month}, selected_day: nil)}
  end

  def handle_event("select_day", %{"date" => ""}, socket) do
    {:noreply, assign(socket, selected_day: nil)}
  end

  def handle_event("select_day", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        selected = if socket.assigns.selected_day != date, do: date
        {:noreply, assign(socket, selected_day: selected)}

      _ ->
        {:noreply, socket}
    end
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:releases_updated, _item_ids}, socket) do
    {:noreply, debounce(socket, :reload_timer, :reload_upcoming, 500)}
  end

  def handle_info({event, _payload}, socket) when event in @grab_status_events do
    {:noreply, debounce(socket, :grab_statuses_timer, :reload_grab_statuses, 500)}
  end

  def handle_info(:reload_grab_statuses, socket) do
    grab_statuses = load_release_grab_statuses(socket.assigns.upcoming_releases)
    {:noreply, assign(socket, release_grab_statuses: grab_statuses)}
  end

  def handle_info({:queue_snapshot, items}, socket) do
    {:noreply, assign(socket, queue_items: items)}
  end

  def handle_info(:load_track_suggestions, socket) do
    suggestions = ReleaseTracking.suggest_trackable_items()
    {:noreply, assign(socket, track_suggestions: suggestions, track_suggestions_loading: false)}
  end

  def handle_info({:do_track_search, query}, socket) do
    if query == socket.assigns.track_search_query do
      results = ReleaseTracking.search_tmdb(query)
      {:noreply, assign(socket, track_search_results: results, track_search_loading: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:entities_changed, _entity_ids}, socket) do
    {:noreply, debounce(socket, :reload_timer, :reload_upcoming, 500)}
  end

  def handle_info(:reload_upcoming, socket) do
    {:noreply, load_upcoming(socket)}
  end

  def handle_info(:capabilities_changed, socket) do
    {:noreply,
     assign(socket,
       tmdb_ready: Capabilities.tmdb_ready?(),
       acquisition_ready: Capabilities.prowlarr_ready?()
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private ---

  defp queue_all_summary_message(%{
         queued: queued,
         rearmed: rearmed,
         in_progress: in_progress,
         already_grabbed: already_grabbed,
         failed: failed
       }) do
    action = queued + rearmed
    total = action + in_progress + already_grabbed + length(failed)

    cond do
      total == 0 ->
        {:info, "Nothing to queue"}

      failed != [] ->
        {:error, "Queued #{action} of #{total} — #{length(failed)} failed"}

      action == 0 and in_progress > 0 and already_grabbed == 0 ->
        {:info, "Already in progress — #{in_progress} #{pluralize("release", in_progress)} searching"}

      action == 0 and already_grabbed > 0 and in_progress == 0 ->
        {:info, "All #{already_grabbed} #{pluralize("release", already_grabbed)} already grabbed"}

      action == 0 ->
        {:info, "Nothing new — #{in_progress} in progress, #{already_grabbed} already grabbed"}

      queued > 0 and rearmed > 0 ->
        {:info, "Queued #{queued}, re-armed #{rearmed}"}

      rearmed > 0 ->
        {:info, "Re-armed #{rearmed} #{pluralize("release", rearmed)}"}

      true ->
        {:info, "Queued #{queued} #{pluralize("episode", queued)}"}
    end
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"

  defp load_upcoming(socket) do
    releases = ReleaseTracking.list_releases()
    events = ReleaseTracking.list_recent_events(10)
    image_map = load_tracking_images(releases)
    tracked_items = build_tracked_items_from_watching()
    grab_statuses = load_release_grab_statuses(releases)

    assign(socket,
      upcoming_releases: releases,
      upcoming_events: events,
      upcoming_images: image_map,
      tracked_items: tracked_items,
      release_grab_statuses: grab_statuses,
      acquisition_ready: Capabilities.prowlarr_ready?()
    )
  end

  defp load_release_grab_statuses(%{upcoming: upcoming, released: released}) do
    if Capabilities.prowlarr_ready?() do
      keys =
        (upcoming ++ released)
        |> Enum.map(&release_grab_key/1)
        |> Enum.uniq()

      Acquisition.statuses_for_releases(keys)
    else
      %{}
    end
  end

  defp release_grab_key(release) do
    {to_string(release.item.tmdb_id), to_string(release.item.media_type), release.season_number,
     release.episode_number}
  end

  defp build_tracked_items_from_watching do
    Enum.map(ReleaseTracking.list_watching_items(), fn item ->
      releases = item.releases || []
      upcoming_count = Enum.count(releases, &(not &1.released and not &1.in_library))
      released_count = Enum.count(releases, &(&1.released and not &1.in_library))

      status_text =
        case {upcoming_count, released_count} do
          {0, 0} -> "tracking"
          {u, 0} -> "#{u} upcoming"
          {0, r} -> "#{r} released"
          {u, r} -> "#{u} upcoming, #{r} released"
        end

      %{
        item_id: item.id,
        name: item.name,
        media_type: item.media_type,
        status_text: status_text
      }
    end)
  end

  defp load_tracking_images(%{upcoming: upcoming, released: released}) do
    items =
      (upcoming ++ released)
      |> Enum.map(& &1.item)
      |> Enum.uniq_by(& &1.id)

    logo_urls =
      items
      |> Enum.flat_map(fn item ->
        if item.library_entity_id, do: [{item.media_type, item.library_entity_id}], else: []
      end)
      |> MediaCentarr.Library.logo_urls_for_entities()

    Enum.reduce(items, %{}, fn item, acc ->
      images =
        %{}
        |> maybe_put_image(:backdrop, item.backdrop_path)
        |> maybe_put_image(:poster, item.poster_path)
        |> maybe_put_logo(item, logo_urls)

      if images == %{}, do: acc, else: Map.put(acc, item.id, images)
    end)
  end

  defp maybe_put_image(map, _role, nil), do: map
  defp maybe_put_image(map, role, path), do: Map.put(map, role, "/media-images/#{path}")

  defp maybe_put_logo(map, item, logo_urls) do
    case ReleaseTracking.logo_url_for_item(item, logo_urls) do
      nil -> map
      url -> Map.put(map, :logo, url)
    end
  end
end
