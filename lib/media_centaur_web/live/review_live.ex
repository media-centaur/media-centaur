defmodule MediaCentaurWeb.ReviewLive do
  @moduledoc """
  Review → Identity: the bulk list of files waiting for a title
  (campaign `review-bulk-match`).

  One flat list of review items (`Review.list_queue/0`), sorted by how the
  files were named, with a divider where the parsed title changes. A
  person ticks rows — one, a divider's block, everything a filter shows —
  and the action bar acts on what is ticked: its search starts from the
  first ticked row's parsed title and runs at once, and pressing a result
  matches and imports every ticked row (`Review.match/2`). Accept best
  guess approves each ticked row under its own guess (`Review.approve/1`).
  Nothing groups files automatically: six episodes in six release folders
  are gathered by the divider or the filter, not by a folder rule that
  can split them.

  The page's state in the URL: `status` (`waiting` | `importing` |
  `dismissed`, the segmented control) and `q` (the filter). The ticks are
  the LiveView's and never outlive what they tick: a row that leaves the
  view or the queue leaves the selection.

  View logic lives in `MediaCentaurWeb.ReviewHelpers` (ADR-030); the rows
  and the bar are `Components.ReviewQueue`. Delete reads the media
  directory, so the plan resolves and the delete runs off the LiveView
  process (ADR-044), each release folder judged on its own by
  `MediaCentaur.DeleteTargets`.
  """
  use MediaCentaurWeb, :live_view

  require MediaCentaur.Log, as: Log

  import MediaCentaurWeb.Components.ReviewQueue
  import MediaCentaurWeb.Components.ReviewTabs
  import MediaCentaurWeb.ReviewHelpers

  alias MediaCentaur.DeleteTargets
  alias MediaCentaur.Library.Deletion
  alias MediaCentaur.Review
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.FilesApproved
  alias MediaCentaurWeb.Components.FilterField
  alias MediaCentaurWeb.Live.ArmGesture

  @statuses %{"waiting" => :waiting, "importing" => :importing, "dismissed" => :dismissed}

  @impl true
  def mount(_params, _session, socket) do
    # No Review.subscribe() here — MediaCentaurWeb.ShellBadges (default
    # live_session on_mount) already subscribes every LiveView to
    # review:updates; a second subscribe would double-deliver each message.
    {:ok,
     socket
     |> assign(page_title: "Review")
     |> assign(loaded?: false, files: [], visible: [], status: :waiting, query: "")
     |> assign(selected: MapSet.new(), tmdb_ready: false, reload_timer: nil)
     |> assign(deleting: false, delete_plan: nil)
     |> reset_search()}
  end

  # First-render data load runs on both the static and the connected
  # render, so the first paint lists the queue — never an empty-state
  # flash. `list_queue/0` is a local query; do not add a `connected?` gate.
  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(status: Map.get(@statuses, params["status"], :waiting), query: params["q"] || "")
      |> then(fn socket ->
        if socket.assigns.loaded?,
          do: socket,
          else: assign(socket, loaded?: true, tmdb_ready: MediaCentaur.Capabilities.tmdb_ready?())
      end)

    {:noreply, reload(socket)}
  end

  # --- The list ---

  @impl true
  def handle_event("set_status", %{"choice" => choice}, socket) do
    {:noreply, patch(socket, status: choice)}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    {:noreply, patch(socket, q: query)}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply, patch(socket, q: "")}
  end

  def handle_event("tick", %{"id" => id}, socket) do
    {:noreply, select(socket, toggle(socket.assigns.selected, [id]))}
  end

  def handle_event("tick_block", %{"ids" => ids}, socket) do
    {:noreply, select(socket, toggle(socket.assigns.selected, String.split(ids, ",")))}
  end

  def handle_event("tick_all", _params, socket) do
    {:noreply,
     select(socket, toggle(socket.assigns.selected, Enum.map(socket.assigns.visible, & &1.id)))}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, select(socket, MapSet.new())}
  end

  # --- The search ---

  def handle_event("update_search", %{"query" => query, "type" => type}, socket) do
    type = if type == "tv", do: :tv, else: :movie
    {:noreply, socket |> assign(search_edited: true) |> run_search(query, type)}
  end

  def handle_event("search", %{"query" => query, "type" => type}, socket) do
    type = if type == "tv", do: :tv, else: :movie
    {:noreply, socket |> assign(search_edited: true, search_cache: %{}) |> run_search(query, type)}
  end

  # --- Decisions on the ticked rows ---

  def handle_event(
        "match",
        %{"tmdb-id" => tmdb_id, "tmdb-type" => tmdb_type, "title" => title} = params,
        socket
      ) do
    title = %{
      tmdb_id: tmdb_id,
      tmdb_type: tmdb_type,
      title: title,
      year: params["year"],
      poster_path: params["poster-path"]
    }

    case Review.match(ticked_ids(socket), title) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "Matched #{plural(count, "file")} to #{title.title}")
         |> select(MapSet.new())
         |> reload()}

      {:error, :no_identity} ->
        {:noreply, put_flash(socket, :error, "That result has no TMDB id. Search again.")}
    end
  end

  def handle_event("accept_guesses", _params, socket) do
    {:ok, count} = Review.approve(ticked_ids(socket))

    {:noreply,
     socket
     |> put_flash(:info, "Accepted #{plural(count, "best guess")}")
     |> select(MapSet.new())
     |> reload()}
  end

  # Dismiss and Delete take the arm gesture (MC0027 tier 2): the first
  # press arms, the second fires; any other event — a tick — disarms.
  def handle_event("dismiss", _params, socket) do
    case ArmGesture.press(socket, "dismiss") do
      {:fire, socket} ->
        {:ok, _count} = Review.dismiss(ticked_ids(socket))
        {:noreply, socket |> select(MapSet.new()) |> reload()}

      {:armed, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("restore", _params, socket) do
    {:ok, _count} = Review.restore(ticked_ids(socket))
    {:noreply, socket |> select(MapSet.new()) |> reload()}
  end

  def handle_event("delete", _params, socket) do
    with false <- socket.assigns.deleting,
         {:fire, socket} <- ArmGesture.press(socket, "delete") do
      files = ticked_files(socket)

      {:noreply,
       socket
       |> assign(deleting: true)
       |> start_async(:delete, fn -> execute_delete(files) end)}
    else
      {:armed, socket} -> {:noreply, socket}
      true -> {:noreply, socket}
    end
  end

  # --- Queue updates ---

  @impl true
  def handle_info({:file_added, %FileAdded{}}, socket), do: {:noreply, debounced_reload(socket)}
  def handle_info({:file_reviewed, %FileReviewed{}}, socket), do: {:noreply, debounced_reload(socket)}
  def handle_info({:files_approved, %FilesApproved{}}, socket), do: {:noreply, debounced_reload(socket)}

  def handle_info(:reload_queue, socket) do
    {:noreply, socket |> assign(reload_timer: nil) |> reload()}
  end

  def handle_info(:capabilities_changed, socket) do
    {:noreply, assign(socket, tmdb_ready: MediaCentaur.Capabilities.tmdb_ready?())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Async results (owned via start_async/3, ADR-049) ---

  # A result for a query the bar no longer shows is cached and not shown:
  # the person typed on while it was in flight.
  @impl true
  def handle_async(:tmdb_search, {:ok, %{query: query, type: type, outcome: outcome}}, socket) do
    current? = socket.assigns.search_query == query and socket.assigns.search_type == type

    case outcome do
      {:ok, results} ->
        socket = update(socket, :search_cache, &Map.put(&1, {query, type}, results))

        if current?,
          do: {:noreply, assign(socket, search_results: results, searching: false, searched: true)},
          else: {:noreply, socket}

      {:error, _reason} when current? ->
        {:noreply,
         socket
         |> assign(search_results: [], searching: false, searched: true)
         |> put_flash(:error, "TMDB search failed")}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # A crashed search must clear `searching`, or the bar is stranded on a
  # disabled Search button (audit DS17).
  def handle_async(:tmdb_search, {:exit, reason}, socket) do
    Log.warning(:review, "TMDB search task exited — #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(search_results: [], searching: false, searched: true)
     |> put_flash(:error, "TMDB search failed")}
  end

  def handle_async(:delete_plan, {:ok, {paths, plan}}, socket) do
    if paths == ticked_paths(socket),
      do: {:noreply, assign(socket, delete_plan: plan)},
      else: {:noreply, socket}
  end

  # Unresolved, every ticked file is deleted on its own — never a folder.
  def handle_async(:delete_plan, {:exit, reason}, socket) do
    Log.warning(:review, "resolving the delete plan failed — #{inspect(reason)}")
    {:noreply, assign(socket, delete_plan: [{:files, ticked_paths(socket)}])}
  end

  def handle_async(:delete, {:ok, {_deleted, errors}}, socket) do
    socket =
      if errors > 0,
        do: put_flash(socket, :error, "#{plural(errors, "file")} failed to delete"),
        else: socket

    {:noreply, socket |> assign(deleting: false) |> select(MapSet.new()) |> reload()}
  end

  def handle_async(:delete, {:exit, reason}, socket) do
    Log.error(:review, "delete task crashed — #{inspect(reason)}")
    {:noreply, socket |> assign(deleting: false) |> put_flash(:error, "Delete failed") |> reload()}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:counts, count_by_status(assigns.files))
      |> assign(:selectable, assigns.status != :importing)

    ~H"""
    <Layouts.app
      profile={@profile}
      profiles={@profiles}
      viewing_layer={assigns[:viewing_layer]}
      features={@features}
      flash={@flash}
      current_path="/review"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <div
        class="flex flex-col h-full gap-4"
        data-page-behavior="review"
        data-nav-default-zone="review"
      >
        <.page_header title="Review" />

        <.review_tabs
          active={:identity}
          identity_count={@badges.review_pending}
          mapping_count={@badges.mapping_pending}
        />

        <.empty_state
          :if={@files == []}
          icon="hero-check-circle"
          headline="Unmatched files show up here"
        >
          When a file in your media directories cannot be matched to a title with confidence, it
          waits here for you to pick the right one by hand.
        </.empty_state>

        <div
          :if={@files != []}
          class="flex items-center gap-3 flex-wrap"
          data-nav-zone="review-toolbar"
        >
          <.segmented_control
            label="Show"
            options={[
              {"waiting", "Waiting · #{@counts.waiting}"},
              {"importing", "Importing · #{@counts.importing}"},
              {"dismissed", "Dismissed · #{@counts.dismissed}"}
            ]}
            selected={Atom.to_string(@status)}
            event="set_status"
          />
          <form id="review-filter-form" phx-change="filter" phx-submit="filter">
            <FilterField.filter_field
              id="review-filter"
              name="q"
              value={@query}
              placeholder="Filter by title or file name…"
              aria_label="Filter by title or file name"
              clear_event="clear_filter"
              class="w-72"
            />
          </form>
          <span class="ml-auto text-sm text-base-content/55">
            {length(@visible)} of {Map.fetch!(@counts, @status)} shown
          </span>
        </div>

        <div
          :if={@files != []}
          class="glass-surface rounded-lg flex-1 min-h-0 overflow-y-auto thin-scrollbar"
        >
          <.empty_state
            :if={@visible == [] && @query != ""}
            headline={"Nothing here matches “#{@query}”"}
          >
            The filter looks in the parsed title and the file name.
            <:action>
              <.button variant="secondary" size="sm" phx-click="clear_filter">Clear the filter</.button>
            </:action>
          </.empty_state>
          <.empty_state :if={@visible == [] && @query == ""} headline={empty_headline(@status)}>
            {empty_body(@status)}
          </.empty_state>

          <div :if={@visible != []} class="pb-2" data-nav-zone="review-rows">
            <div class="sticky top-0 z-[1] bg-base-200/95">
              <.queue_header
                state={tick_state(@selected, Enum.map(@visible, & &1.id))}
                selectable={@selectable}
                phx-click="tick_all"
              />
            </div>
            <%= for row <- rows(@visible) do %>
              <%= case row do %>
                <% {:divider, divider} -> %>
                  <.queue_divider
                    id={"review-#{divider.id}"}
                    label={divider.label}
                    count={length(divider.ids)}
                    state={tick_state(@selected, divider.ids)}
                    selectable={@selectable}
                    phx-click="tick_block"
                    phx-value-ids={Enum.join(divider.ids, ",")}
                  />
                <% {:item, file} -> %>
                  <.queue_item
                    id={"review-item-#{file.id}"}
                    file={file}
                    ticked={MapSet.member?(@selected, file.id)}
                    selectable={@selectable}
                    phx-click="tick"
                    phx-value-id={file.id}
                  />
              <% end %>
            <% end %>
          </div>
        </div>

        <.match_bar
          :if={@selectable && MapSet.size(@selected) > 0}
          count={MapSet.size(@selected)}
          status={@status}
          query={@search_query}
          type={@search_type}
          searching={@searching}
          searched={@searched}
          results={@search_results}
          tmdb_ready={@tmdb_ready}
          accept_guesses={accept_guesses?(ticked_files(@visible, @selected))}
          dismiss_armed={ArmGesture.armed?(@armed_gesture, "dismiss")}
          delete_armed={ArmGesture.armed?(@armed_gesture, "delete")}
          deleting={@deleting}
          delete_label={@delete_plan && delete_label(@delete_plan)}
        />
      </div>
    </Layouts.app>
    """
  end

  defp empty_headline(:waiting), do: "Nothing waits for a title"
  defp empty_headline(:importing), do: "Nothing is importing"
  defp empty_headline(:dismissed), do: "No dismissed files"

  defp empty_body(:waiting),
    do: "Every file found so far has a title. New ones that cannot be matched appear here."

  defp empty_body(:importing), do: "Files you match go here until they are in the library."

  defp empty_body(:dismissed),
    do: "Files you dismiss are skipped on every scan and listed here, where you can restore them."

  # --- State ---

  defp patch(socket, changes) do
    params =
      %{"status" => Atom.to_string(socket.assigns.status), "q" => socket.assigns.query}
      |> Map.merge(Map.new(changes, fn {key, value} -> {Atom.to_string(key), value} end))
      |> Enum.reject(fn {key, value} -> value == "" or {key, value} == {"status", "waiting"} end)

    push_patch(socket, to: ~p"/review?#{params}")
  end

  defp reload(socket) do
    files = Review.list_queue()

    socket
    |> assign(files: files, visible: visible(files, socket.assigns.status, socket.assigns.query))
    |> select(socket.assigns.selected)
  end

  defp debounced_reload(socket), do: debounce(socket, :reload_timer, :reload_queue, 500)

  # Every change of the ticks goes through here: the selection keeps only
  # rows the view shows and can act on; the bar's search follows the first
  # ticked row until the person types in it; the delete plan re-resolves.
  defp select(socket, selected) do
    visible_ids =
      if socket.assigns.status == :importing, do: [], else: Enum.map(socket.assigns.visible, & &1.id)

    selected = MapSet.intersection(selected, MapSet.new(visible_ids))
    changed? = selected != socket.assigns.selected
    socket = assign(socket, selected: selected)

    cond do
      MapSet.size(selected) == 0 ->
        socket |> reset_search() |> assign(delete_plan: nil)

      changed? ->
        socket |> follow_prefill() |> resolve_delete_plan()

      true ->
        socket
    end
  end

  defp follow_prefill(%{assigns: %{search_edited: true}} = socket), do: socket

  defp follow_prefill(socket) do
    {query, type} = search_prefill(socket.assigns.visible, socket.assigns.selected)

    if {query, type} == {socket.assigns.search_query, socket.assigns.search_type} and
         socket.assigns.searched,
       do: socket,
       else: run_search(socket, query, type)
  end

  defp reset_search(socket) do
    assign(socket,
      search_query: "",
      search_type: :tv,
      search_edited: false,
      search_results: [],
      searching: false,
      searched: false,
      search_cache: Map.get(socket.assigns, :search_cache, %{})
    )
  end

  defp run_search(socket, query, type) do
    socket = assign(socket, search_query: query, search_type: type)

    cond do
      String.trim(query) == "" or not socket.assigns.tmdb_ready ->
        assign(socket, search_results: [], searching: false, searched: false)

      results = socket.assigns.search_cache[{query, type}] ->
        assign(socket, search_results: results, searching: false, searched: true)

      true ->
        socket
        |> assign(searching: true)
        |> start_async(:tmdb_search, fn ->
          outcome =
            try do
              Review.Search.tmdb(query, type)
            catch
              kind, reason -> {:error, {kind, reason}}
            end

          %{query: query, type: type, outcome: outcome}
        end)
    end
  end

  defp resolve_delete_plan(socket) do
    paths = ticked_paths(socket)

    socket
    |> assign(delete_plan: nil)
    |> start_async(:delete_plan, fn -> {paths, delete_plan(paths)} end)
  end

  # Each release folder is judged on its own; a folder goes whole only when
  # `DeleteTargets` finds nothing else of the library under it.
  defp delete_plan(paths) do
    for part <- delete_partitions(paths) do
      case DeleteTargets.resolve_folder_target(part) do
        {:folder, dir} -> {:folder, dir, part}
        :file_only -> {:files, part}
      end
    end
  end

  # Resolved again at the moment of deleting — never from the cached plan
  # (`MediaCentaur.DeleteTargets`). Runs in the delete task.
  defp execute_delete(files) do
    ids_by_path = Map.new(files, &{&1.file_path, &1.id})

    files
    |> Enum.map(& &1.file_path)
    |> delete_plan()
    |> Enum.reduce({0, 0}, fn
      {:folder, dir, paths}, {deleted, errors} ->
        case Deletion.delete_folder(dir, paths) do
          {:ok, _entity_ids} ->
            Review.destroy_pending_files(Enum.map(paths, &ids_by_path[&1]))
            {deleted + length(paths), errors}

          {:error, reason} ->
            Log.warning(:library, "failed to delete folder #{dir}: #{inspect(reason)}")
            {deleted, errors + length(paths)}
        end

      {:files, paths}, {deleted, errors} ->
        {ok, failed} = Review.delete_files(Enum.map(paths, &ids_by_path[&1]))
        {deleted + ok, errors + failed}
    end)
  end

  defp ticked_files(socket), do: ticked_files(socket.assigns.visible, socket.assigns.selected)
  defp ticked_files(visible, selected), do: Enum.filter(visible, &MapSet.member?(selected, &1.id))
  defp ticked_ids(socket), do: socket |> ticked_files() |> Enum.map(& &1.id)
  defp ticked_paths(socket), do: socket |> ticked_files() |> Enum.map(& &1.file_path)

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(count, "best guess"), do: "#{count} best guesses"
  defp plural(count, noun), do: "#{count} #{noun}s"
end
