defmodule MediaCentarrWeb.ReviewLive do
  @moduledoc """
  Master/detail UI for files awaiting review (`Review.PendingFile` records).

  Lists pending files in the left pane with a detail editor on the right —
  user accepts the proposed match, manually rematches, or skips the file.
  """
  use MediaCentarrWeb, :live_view

  import MediaCentarrWeb.ReviewHelpers

  alias MediaCentarr.Review

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Review.subscribe()
      MediaCentarr.Capabilities.subscribe()
    end

    {:ok,
     socket
     |> assign(loaded?: false)
     |> assign(groups: [])
     |> assign(groups_by_key: %{})
     |> assign(tmdb_ready: false)
     |> assign(processing: MapSet.new())
     |> assign(selected_key: nil)
     |> assign(search_open: nil)
     |> assign(search_query: "")
     |> assign(search_type: :movie)
     |> assign(search_results: [])
     |> assign(searching: false)
     |> assign(searched: false)
     |> assign(reload_timer: nil)
     |> apply_group_stats()
     |> ensure_selection()}
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
      groups = Review.fetch_pending_groups()

      socket
      |> assign(groups: groups)
      |> assign(groups_by_key: Map.new(groups, &{&1.key, &1}))
      |> assign(tmdb_ready: MediaCentarr.Capabilities.tmdb_ready?())
      |> assign(loaded?: true)
      |> apply_group_stats()
      |> ensure_selection()
    else
      socket
    end
  end

  @impl true
  def handle_event("select_item", %{"key" => key}, socket) do
    group_key = decode_key(key)

    {:noreply,
     socket
     |> assign(selected_key: group_key)
     |> assign(search_open: nil)
     |> assign(search_query: "")
     |> assign(search_results: [])
     |> assign(searching: false)
     |> assign(searched: false)}
  end

  def handle_event("approve", %{"key" => key}, socket) do
    group_key = decode_key(key)
    group = socket.assigns.groups_by_key[group_key]

    if group do
      socket = assign(socket, processing: MapSet.put(socket.assigns.processing, group_key))

      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        {approved, errors} = Review.approve_group(group.files)

        if errors > 0 do
          Phoenix.PubSub.broadcast(
            MediaCentarr.PubSub,
            MediaCentarr.Topics.review_updates(),
            {:group_error, group_key, "#{errors} file(s) failed to approve"}
          )
        end

        if approved > 0 do
          Phoenix.PubSub.broadcast(
            MediaCentarr.PubSub,
            MediaCentarr.Topics.review_updates(),
            {:group_approved, group_key, approved}
          )
        end
      end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss", %{"key" => key}, socket) do
    group_key = decode_key(key)
    group = socket.assigns.groups_by_key[group_key]

    if group do
      socket = assign(socket, processing: MapSet.put(socket.assigns.processing, group_key))

      {_dismissed, errors} = Review.dismiss_group(group.files)

      socket =
        if errors > 0 do
          socket
          |> assign(processing: MapSet.delete(socket.assigns.processing, group_key))
          |> put_flash(:error, "#{errors} file(s) failed to dismiss")
        else
          assign(socket, processing: MapSet.delete(socket.assigns.processing, group_key))
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_search", %{"key" => key}, socket) do
    group_key = decode_key(key)
    group = socket.assigns.groups_by_key[group_key]
    file = group && group.representative

    search_type =
      case file && file.parsed_type do
        "tv" -> :tv
        _ -> :movie
      end

    {:noreply,
     socket
     |> assign(search_open: group_key)
     |> assign(search_query: (file && file.parsed_title) || "")
     |> assign(search_type: search_type)
     |> assign(search_results: [])
     |> assign(searching: false)
     |> assign(searched: false)}
  end

  def handle_event("close_search", _params, socket) do
    {:noreply,
     socket
     |> assign(search_open: nil)
     |> assign(search_query: "")
     |> assign(search_results: [])
     |> assign(searching: false)
     |> assign(searched: false)}
  end

  def handle_event("update_search", %{"query" => query, "type" => type}, socket) do
    {:noreply, assign(socket, search_query: query, search_type: String.to_existing_atom(type))}
  end

  def handle_event("search", %{"query" => query, "type" => type}, socket) do
    type = String.to_existing_atom(type)
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      outcome =
        try do
          Review.search_tmdb(query, type)
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      send(parent, {:tmdb_search_result, query, type, outcome})
    end)

    {:noreply, assign(socket, searching: true, search_query: query, search_type: type)}
  end

  def handle_event(
        "select_match",
        %{"key" => key, "tmdb-id" => tmdb_id, "title" => title} = params,
        socket
      ) do
    group_key = decode_key(key)
    group = socket.assigns.groups_by_key[group_key]

    if group do
      match = %{
        tmdb_id: tmdb_id,
        tmdb_type: to_string(socket.assigns.search_type),
        title: title,
        year: params["year"],
        poster_path: params["poster-path"]
      }

      {updated, errors} = Review.set_group_match(group.files, match)

      socket =
        if errors > 0 do
          put_flash(socket, :error, "Failed to set match on #{errors} file(s)")
        else
          socket
        end

      if updated > 0 do
        # Reload groups to reflect updated match info
        groups = Review.fetch_pending_groups()

        {:noreply,
         socket
         |> assign(groups: groups)
         |> assign(groups_by_key: Map.new(groups, &{&1.key, &1}))
         |> assign(search_open: nil)
         |> assign(search_results: [])
         |> apply_group_stats()
         |> ensure_selection()}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_files", %{"key" => key}, socket) do
    group_key = decode_key(key)
    current = socket.assigns[:expanded_group]
    expanded = if current != group_key, do: group_key
    {:noreply, assign(socket, expanded_group: expanded)}
  end

  @impl true
  def handle_info({:file_added, _pending_file_id}, socket) do
    {:noreply, debounce(socket, :reload_timer, :reload_groups, 500)}
  end

  def handle_info(:reload_groups, socket) do
    groups = Review.fetch_pending_groups()

    {:noreply,
     socket
     |> assign(groups: groups)
     |> assign(groups_by_key: Map.new(groups, &{&1.key, &1}))
     |> assign(reload_timer: nil)
     |> apply_group_stats()
     |> ensure_selection()}
  end

  def handle_info({:file_reviewed, file_id}, socket) do
    {groups, groups_by_key} =
      Enum.reduce(
        socket.assigns.groups,
        {[], socket.assigns.groups_by_key},
        fn group, {acc, by_key} ->
          files = Enum.reject(group.files, &(&1.id == file_id))

          cond do
            files == group.files ->
              {[group | acc], by_key}

            files == [] ->
              {acc, Map.delete(by_key, group.key)}

            true ->
              updated = %{group | files: files, representative: List.first(files)}
              {[updated | acc], Map.put(by_key, group.key, updated)}
          end
        end
      )

    groups = Enum.reverse(groups)

    {:noreply,
     socket
     |> assign(groups: groups)
     |> assign(groups_by_key: groups_by_key)
     |> assign(processing: MapSet.delete(socket.assigns.processing, file_id))
     |> apply_group_stats()
     |> advance_selection(socket.assigns.selected_key)}
  end

  def handle_info({:group_error, group_key, message}, socket) do
    {:noreply,
     socket
     |> assign(processing: MapSet.delete(socket.assigns.processing, group_key))
     |> put_flash(:error, message)}
  end

  def handle_info({:group_approved, group_key, _count}, socket) do
    groups = Enum.reject(socket.assigns.groups, &(&1.key == group_key))

    {:noreply,
     socket
     |> assign(groups: groups)
     |> assign(groups_by_key: Map.delete(socket.assigns.groups_by_key, group_key))
     |> assign(processing: MapSet.delete(socket.assigns.processing, group_key))
     |> apply_group_stats()
     |> advance_selection(group_key)}
  end

  def handle_info(:capabilities_changed, socket) do
    {:noreply, assign(socket, tmdb_ready: MediaCentarr.Capabilities.tmdb_ready?())}
  end

  def handle_info({:tmdb_search_result, query, type, outcome}, socket) do
    # Discard stale results — the user may have changed query/type while the
    # async TMDB call was in flight. Without this guard, a slow earlier
    # search would clobber the latest one.
    if socket.assigns.search_query == query and socket.assigns.search_type == type do
      case outcome do
        {:ok, results} ->
          {:noreply, assign(socket, search_results: results, searching: false, searched: true)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(search_results: [], searching: false, searched: true)
           |> put_flash(:error, "TMDB search failed")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/review">
      <div
        class="flex flex-col h-full gap-4"
        data-page-behavior="review"
        data-nav-default-zone="review"
      >
        <%!-- Header with stats chips --%>
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Review</h1>
          <div :if={@total_files > 0} class="flex items-center gap-2">
            <span class="px-3 py-1 rounded-full text-xs font-semibold bg-warning/15 text-warning">
              {@total_files} pending
            </span>
            <span
              :if={@reason_counts.no_results > 0}
              class="px-3 py-1 rounded-full text-xs font-semibold bg-error/12 text-error"
            >
              {@reason_counts.no_results} no results
            </span>
            <span
              :if={@reason_counts.tied > 0}
              class="px-3 py-1 rounded-full text-xs font-semibold bg-info/12 text-info"
            >
              {@reason_counts.tied} tied
            </span>
            <span
              :if={@reason_counts.low_confidence > 0}
              class="px-3 py-1 rounded-full text-xs font-semibold bg-warning/12 text-warning"
            >
              {@reason_counts.low_confidence} low confidence
            </span>
          </div>
        </div>

        <%!-- Empty state --%>
        <div :if={@groups == []} data-nav-zone="review-list">
          <div
            class="glass-surface rounded-2xl py-12 flex flex-col items-center justify-center gap-3"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-check-circle" class="size-16 text-success/30" />
            <h2 class="text-xl font-semibold">All clear</h2>
            <p class="text-base-content/60">No files awaiting review.</p>
          </div>
        </div>

        <%!-- Master-detail layout --%>
        <div :if={@groups != []} class="flex gap-6 flex-1 min-h-0 overflow-x-auto">
          <%!-- Left: scrollable list --%>
          <div
            class="w-[340px] shrink-0 overflow-hidden flex flex-col h-full glass-surface rounded-lg"
            data-nav-zone="review-list"
          >
            <.list_section
              groups={@sorted_groups}
              selected_key={@selected_key}
              processing={@processing}
            />
          </div>

          <%!-- Right: detail panel --%>
          <div class="flex-1 min-w-[360px] min-h-0" data-nav-zone="review-detail">
            <.detail_panel
              :if={@selected_key && @groups_by_key[@selected_key]}
              group={@groups_by_key[@selected_key]}
              processing={MapSet.member?(@processing, @selected_key)}
              search_open={@search_open == @selected_key}
              search_query={@search_query}
              search_type={@search_type}
              search_results={@search_results}
              searching={@searching}
              searched={@searched}
              expanded={assigns[:expanded_group] == @selected_key}
              tmdb_ready={@tmdb_ready}
            />
            <div
              :if={!@selected_key || !@groups_by_key[@selected_key]}
              class="glass-surface rounded-lg h-full flex flex-col items-center justify-center gap-3 text-base-content/30"
            >
              <.icon name="hero-arrow-left" class="size-8" />
              <p class="text-sm">Select an item to review</p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Private Function Components ---

  defp list_section(assigns) do
    {movies, tv} =
      Enum.split_with(assigns.groups, fn group ->
        group.representative.parsed_type != "tv"
      end)

    assigns =
      assigns
      |> assign(movies: movies)
      |> assign(tv: tv)

    ~H"""
    <div class="flex-1 overflow-y-auto p-2 thin-scrollbar">
      <div
        :if={@movies != []}
        class="text-[0.5625rem] font-semibold uppercase tracking-[0.06em] text-base-content/30 px-3 pt-3 pb-1.5"
      >
        Movies
      </div>
      <.list_item
        :for={group <- @movies}
        group={group}
        selected={group.key == @selected_key}
        processing={MapSet.member?(@processing, group.key)}
      />
      <div
        :if={@tv != []}
        class="text-[0.5625rem] font-semibold uppercase tracking-[0.06em] text-base-content/30 px-3 pt-3 pb-1.5 mt-2"
      >
        TV Series
      </div>
      <.list_item
        :for={group <- @tv}
        group={group}
        selected={group.key == @selected_key}
        processing={MapSet.member?(@processing, group.key)}
      />
    </div>
    """
  end

  defp list_item(assigns) do
    file = assigns.group.representative
    file_count = length(assigns.group.files)
    reason = review_reason(file)

    assigns =
      assigns
      |> assign(file: file)
      |> assign(file_count: file_count)
      |> assign(reason: reason)
      |> assign(encoded_key: encode_key(assigns.group.key))

    ~H"""
    <div
      class={[
        "flex items-center gap-3 py-2 px-3 rounded-md cursor-pointer transition-[background,opacity] duration-150 border border-transparent relative hover:bg-base-content/6",
        @selected && "bg-primary/12 !border-primary/25"
      ]}
      phx-click="select_item"
      phx-focus="select_item"
      phx-value-key={@encoded_key}
      data-nav-item
      data-review-pending
      tabindex="0"
    >
      <div
        :if={@processing}
        class="absolute inset-0 flex items-center justify-center bg-base-300/60 rounded-md z-[1]"
      >
        <span class="loading loading-spinner loading-xs"></span>
      </div>
      <img
        :if={@file.match_poster_path}
        src={"https://image.tmdb.org/t/p/w92#{@file.match_poster_path}"}
        alt=""
        class="w-10 h-[60px] rounded object-cover shrink-0"
      />
      <div
        :if={!@file.match_poster_path}
        class="w-10 h-[60px] rounded flex items-center justify-center shrink-0 glass-inset"
      >
        <.icon name="hero-film" class="size-4 opacity-30" />
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium whitespace-nowrap overflow-hidden text-ellipsis">
          {display_title(@group)}
        </div>
        <div
          :if={@file_count > 1}
          class="text-[0.6875rem] text-base-content/40 mt-0.5"
        >
          {@file_count} episodes{if @file.season_number, do: " · S#{zero_pad(@file.season_number)}"}
        </div>
        <div :if={@file_count == 1} class="text-xs text-base-content/50 mt-0.5">
          {if @file.parsed_year, do: "#{@file.parsed_year} · "}{format_type(@file.parsed_type)}
        </div>
      </div>
      <.list_badge reason={@reason} confidence={@file.confidence} />
    </div>
    """
  end

  defp list_badge(%{reason: :no_results} = assigns) do
    ~H"""
    <span class="text-xs text-error shrink-0">None</span>
    """
  end

  defp list_badge(%{reason: :tied} = assigns) do
    ~H"""
    <span class="text-xs text-info shrink-0">Tied</span>
    """
  end

  defp list_badge(%{reason: :low_confidence} = assigns) do
    confidence_pct = if assigns.confidence, do: round(assigns.confidence * 100), else: 0

    assigns = assign(assigns, confidence_pct: confidence_pct)

    ~H"""
    <span class={["text-xs shrink-0", confidence_text_class(@confidence)]}>
      {@confidence_pct}%
    </span>
    """
  end

  defp detail_panel(assigns) do
    file = assigns.group.representative
    file_count = length(assigns.group.files)
    tied = tied_candidates?(file)
    reason = review_reason(file)

    assigns =
      assigns
      |> assign(file: file)
      |> assign(file_count: file_count)
      |> assign(tied: tied)
      |> assign(reason: reason)
      |> assign(encoded_key: encode_key(assigns.group.key))

    ~H"""
    <div class="glass-surface rounded-lg overflow-y-auto h-full max-h-full thin-scrollbar relative">
      <div
        :if={@processing}
        class="absolute inset-0 bg-base-300/60 backdrop-blur-sm z-10 flex items-center justify-center rounded-lg"
      >
        <span class="loading loading-spinner loading-lg"></span>
      </div>

      <div class="p-6 space-y-5">
        <%!-- Header: title + filepath + reason --%>
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <h2 class="text-lg font-semibold">{display_title(@group)}</h2>
            <p
              :if={@file_count == 1}
              class="font-mono text-xs text-base-content/50 truncate-left mt-1"
              title={relative_file_path(@file)}
            >
              <bdo dir="ltr">{relative_file_path(@file)}</bdo>
            </p>
          </div>
          <span class={["text-sm shrink-0", reason_text_class(@reason)]}>
            {reason_label(@reason)}
          </span>
        </div>

        <%!-- Parsed info (compact row) --%>
        <div class="glass-inset rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
          <span class="text-[0.625rem] font-semibold uppercase tracking-wide text-base-content/40 shrink-0">
            Parsed
          </span>
          <span class="text-sm font-medium">{@file.parsed_title || "Unknown"}</span>
          <span :if={@file.parsed_year} class="text-sm text-base-content/50">
            ({@file.parsed_year})
          </span>
          <span class="badge badge-sm badge-outline">{format_type(@file.parsed_type)}</span>
          <span
            :if={@file.season_number && @file.episode_number}
            class="text-sm text-base-content/60"
          >
            S{zero_pad(@file.season_number)}E{zero_pad(@file.episode_number)}
          </span>
        </div>

        <%!-- TMDB match --%>
        <div class="glass-inset rounded-lg p-4">
          <p class="text-[0.625rem] font-semibold uppercase tracking-[0.05em] text-base-content/40 mb-3">
            TMDB Match
          </p>
          <%= if @file.tmdb_id && !@tied do %>
            <div class="flex gap-4">
              <img
                :if={@file.match_poster_path}
                src={"https://image.tmdb.org/t/p/w342#{@file.match_poster_path}"}
                alt="poster"
                class="w-[120px] rounded-lg shrink-0 self-start"
              />
              <div
                :if={!@file.match_poster_path}
                class="w-[120px] aspect-[2/3] glass-inset rounded-lg flex items-center justify-center shrink-0"
              >
                <.icon name="hero-film" class="size-8 opacity-20" />
              </div>
              <div class="flex-1 min-w-0 space-y-2">
                <p class="text-sm font-medium">
                  {@file.match_title || "TMDB ##{@file.tmdb_id}"}
                </p>
                <p :if={@file.match_year} class="text-sm text-base-content/50">
                  ({@file.match_year})
                </p>
                <div :if={@file.confidence} class="mt-1">
                  <p class="text-xs text-base-content/50 mb-1">Confidence</p>
                  <div class="h-1.5 rounded-full bg-base-content/8 overflow-hidden max-w-48">
                    <div
                      class={["h-full rounded-full", confidence_bar_class(@file.confidence)]}
                      style={"width: #{round(@file.confidence * 100)}%"}
                    >
                    </div>
                  </div>
                  <p class={[
                    "text-xs font-semibold mt-1",
                    confidence_text_class(@file.confidence)
                  ]}>
                    {round(@file.confidence * 100)}%
                  </p>
                </div>
                <a
                  href={tmdb_url(@file.tmdb_type, @file.tmdb_id)}
                  target="_blank"
                  rel="noopener"
                  class="text-xs text-info hover:underline inline-flex items-center gap-1"
                >
                  TMDB #{@file.tmdb_id}
                  <.icon name="hero-arrow-top-right-on-square" class="size-3" />
                </a>
              </div>
            </div>
          <% else %>
            <div class="flex flex-col items-center justify-center py-8 gap-2 text-base-content/30">
              <.icon name="hero-question-mark-circle" class="size-10" />
              <p class="text-sm">
                {if @tied, do: "Multiple tied matches", else: "No results found"}
              </p>
            </div>
          <% end %>
        </div>

        <%!-- Tied candidates chooser --%>
        <.tied_candidates
          :if={@tied}
          candidates={sort_candidates_by_year(@file.candidates)}
          tmdb_type={@file.tmdb_type}
          encoded_key={@encoded_key}
        />

        <%!-- Episode list for multi-file groups --%>
        <div :if={@file_count > 1} class="space-y-2">
          <.button
            variant="dismiss"
            size="sm"
            class="gap-1"
            phx-click="toggle_files"
            phx-value-key={@encoded_key}
          >
            <span class="badge badge-sm badge-neutral">{@file_count} episodes</span>
            <.icon
              name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="size-4"
            />
          </.button>
          <div :if={@expanded} class="glass-inset rounded-lg p-3">
            <ul class="space-y-1">
              <li :for={file <- @group.files} class="flex items-center gap-2">
                <span
                  :if={file.season_number && file.episode_number}
                  class="badge badge-xs badge-ghost font-mono"
                >
                  S{zero_pad(file.season_number)}E{zero_pad(file.episode_number)}
                </span>
                <span
                  class="font-mono text-xs text-base-content/70 truncate-left"
                  title={relative_file_path(file)}
                >
                  <bdo dir="ltr">{relative_file_path(file)}</bdo>
                </span>
              </li>
            </ul>
          </div>
        </div>

        <%!-- Action buttons --%>
        <div class="flex flex-wrap gap-2 pt-3 border-t border-base-content/6">
          <.button
            :if={@file.tmdb_id && !@tied}
            variant="action"
            size="sm"
            phx-click="approve"
            phx-value-key={@encoded_key}
            disabled={@processing}
            data-nav-item
            tabindex="0"
          >
            {if @file_count > 1, do: "Approve All", else: "Approve"}
          </.button>
          <.button
            :if={@tmdb_ready}
            variant="info"
            size="sm"
            phx-click="open_search"
            phx-value-key={@encoded_key}
            disabled={@processing}
            data-nav-item
            tabindex="0"
          >
            Search TMDB
          </.button>
          <.button
            variant="dismiss"
            size="sm"
            phx-click="dismiss"
            phx-value-key={@encoded_key}
            disabled={@processing}
            data-nav-item
            tabindex="0"
          >
            {if @file_count > 1, do: "Dismiss All", else: "Dismiss"}
          </.button>
        </div>

        <%!-- Search panel --%>
        <.search_panel
          :if={@search_open}
          file={@file}
          encoded_key={@encoded_key}
          query={@search_query}
          type={@search_type}
          results={@search_results}
          searching={@searching}
          searched={@searched}
        />
      </div>
    </div>
    """
  end

  defp tied_candidates(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg p-4 space-y-3">
      <div class="flex items-center gap-2 text-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <p class="text-sm font-medium">
          Multiple TMDB results matched equally — choose the correct one:
        </p>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div
          :for={candidate <- @candidates}
          class="glass-surface p-3 rounded-lg flex flex-col hover:border-primary transition-colors"
        >
          <div class="flex gap-3">
            <div :if={candidate["poster_path"]} class="shrink-0">
              <img
                src={"https://image.tmdb.org/t/p/w154#{candidate["poster_path"]}"}
                alt="poster"
                class="w-[100px] rounded"
              />
            </div>
            <div
              :if={!candidate["poster_path"]}
              class="shrink-0 w-[100px] h-[150px] glass-inset rounded flex items-center justify-center"
            >
              <.icon name="hero-film" class="size-6 opacity-30" />
            </div>
            <div class="flex-1 min-w-0 space-y-1">
              <div class="flex items-baseline gap-2">
                <p class="text-sm font-medium">{candidate["title"]}</p>
                <span :if={candidate["year"]} class="text-xs text-base-content/60">
                  ({candidate["year"]})
                </span>
              </div>
              <p :if={candidate["overview"]} class="text-xs text-base-content/60 line-clamp-3">
                {candidate["overview"]}
              </p>
            </div>
          </div>
          <div class="flex items-center justify-between mt-auto pt-3">
            <a
              href={tmdb_url(@tmdb_type, candidate["tmdb_id"])}
              target="_blank"
              rel="noopener"
              class="text-xs text-info hover:underline inline-flex items-center gap-1"
            >
              TMDB #{candidate["tmdb_id"]}
              <.icon name="hero-arrow-top-right-on-square" class="size-3" />
            </a>
            <.button
              variant="info"
              size="sm"
              phx-click="select_match"
              phx-value-key={@encoded_key}
              phx-value-tmdb-id={candidate["tmdb_id"]}
              phx-value-title={candidate["title"]}
              phx-value-year={candidate["year"]}
              phx-value-poster-path={candidate["poster_path"]}
            >
              Select
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp search_panel(assigns) do
    ~H"""
    <div class="glass-inset rounded-lg p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <.icon name="hero-magnifying-glass" class="size-5 text-base-content/60" />
          <span class="text-[10px] font-semibold uppercase tracking-wide text-base-content/40">
            TMDB Search
          </span>
        </div>
        <.button variant="dismiss" size="xs" shape="circle" phx-click="close_search">
          <.icon name="hero-x-mark" class="size-4" />
        </.button>
      </div>

      <p :if={@type == :tv} class="text-sm text-base-content/70">
        Match this episode to a TV series.
        <span :if={@file.season_number && @file.episode_number}>
          Season {@file.season_number}, Episode {@file.episode_number} already parsed from the
          filename.
        </span>
      </p>
      <p :if={@type != :tv} class="text-sm text-base-content/70">
        Find the correct title for this file.
      </p>

      <form
        phx-submit="search"
        phx-change="update_search"
        class="flex gap-2 items-end"
        data-captures-keys
      >
        <div class="form-control flex-1">
          <label class="label py-0"><span class="label-text text-xs">Search</span></label>
          <input
            type="text"
            name="query"
            value={@query}
            class="input input-bordered input-sm w-full"
            placeholder={if @type == :tv, do: "Show name", else: "Movie title"}
          />
        </div>
        <div class="form-control">
          <label class="label py-0"><span class="label-text text-xs">Type</span></label>
          <select name="type" class="select select-bordered select-sm">
            <option value="movie" selected={@type == :movie}>Movie</option>
            <option value="tv" selected={@type == :tv}>TV</option>
          </select>
        </div>
        <.button type="submit" variant="primary" size="sm" disabled={@searching}>
          {if @searching, do: "Searching...", else: "Search"}
        </.button>
      </form>

      <p class="text-xs text-base-content/50">
        {if @type == :tv,
          do: "Search by show name only — season and episode numbers are stripped automatically.",
          else: "Search by movie title. Year is optional and will be ignored."}
      </p>

      <p :if={@results == [] && @searched} class="text-sm text-base-content/50">
        No results found. Try a simpler title — leave out years, seasons, and episode numbers.
      </p>

      <div :if={@results != []} class="space-y-2">
        <div
          :for={result <- @results}
          class="glass-surface p-3 rounded-lg flex items-center gap-3 hover:border-primary transition-colors"
        >
          <div :if={result.poster_path} class="shrink-0">
            <img
              src={"https://image.tmdb.org/t/p/w92#{result.poster_path}"}
              alt="poster"
              class="w-12 rounded"
            />
          </div>
          <div
            :if={!result.poster_path}
            class="shrink-0 w-12 aspect-[2/3] glass-inset rounded flex items-center justify-center"
          >
            <.icon name="hero-film" class="size-4 opacity-30" />
          </div>

          <div class="flex-1 min-w-0">
            <p class="font-medium text-sm">
              {result.title}
              <span :if={result.year} class="text-base-content/60">({result.year})</span>
            </p>
            <p :if={result.overview} class="text-xs text-base-content/60 line-clamp-2">
              {result.overview}
            </p>
          </div>

          <.button
            variant="info"
            size="sm"
            class="shrink-0"
            phx-click="select_match"
            phx-value-key={@encoded_key}
            phx-value-tmdb-id={result.tmdb_id}
            phx-value-title={result.title}
            phx-value-year={result.year}
            phx-value-poster-path={result.poster_path}
          >
            Select
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # --- Derived Assigns ---

  defp apply_group_stats(socket) do
    groups = socket.assigns.groups
    total_files = Enum.reduce(groups, 0, fn group, acc -> acc + length(group.files) end)

    assign(socket,
      sorted_groups: sort_groups(groups),
      total_files: total_files,
      reason_counts: count_by_reason(groups)
    )
  end

  defp ensure_selection(socket) do
    selected = socket.assigns.selected_key
    sorted = socket.assigns.sorted_groups

    if selected && socket.assigns.groups_by_key[selected] do
      socket
    else
      case sorted do
        [first | _] -> assign(socket, selected_key: first.key)
        [] -> assign(socket, selected_key: nil)
      end
    end
  end

  defp advance_selection(socket, removed_key) do
    sorted = socket.assigns.sorted_groups

    case sorted do
      [] ->
        assign(socket, selected_key: nil)

      _ ->
        if socket.assigns.groups_by_key[removed_key] do
          # Key still exists (e.g. group still has files), keep it
          socket
        else
          # Find where the removed key was in the old sort order and pick the next
          # Since it's already removed, just ensure_selection picks first available
          ensure_selection(assign(socket, selected_key: nil))
        end
    end
  end

  # --- Helpers ---

  defp display_title(%{representative: file} = group) do
    file_count = length(group.files)

    if file_count > 1 do
      series_root_name(group)
    else
      file.parsed_title || "Unknown"
    end
  end

  defp series_root_name(%{key: {_watch_dir, root}}), do: root

  defp tmdb_url("tv", id), do: "https://www.themoviedb.org/tv/#{id}"
  defp tmdb_url(_, id), do: "https://www.themoviedb.org/movie/#{id}"

  defp zero_pad(number) when number < 10, do: "0#{number}"
  defp zero_pad(number), do: "#{number}"

  defp relative_file_path(file) do
    case file.watch_directory do
      nil -> file.file_path
      dir -> String.replace_prefix(file.file_path, dir <> "/", "")
    end
  end

  # Group keys are `{watch_dir, series_root}` tuples. We encode them as a
  # single string for phx-value-key attributes and decode on the way back.
  defp encode_key({watch_dir, root}) do
    Base.url_encode64(:erlang.term_to_binary({watch_dir, root}))
  end

  # sobelow_skip ["Misc.BinToTerm"]
  # `:safe` prevents atom creation; the encoded payload is always a
  # `{watch_dir, root}` string tuple created by `encode_key/1` above and
  # round-tripped through the URL by the same LiveView. Phoenix's request
  # size limits bound any DoS-via-large-term attack surface.
  defp decode_key(encoded) do
    encoded
    |> Base.url_decode64!()
    |> :erlang.binary_to_term([:safe])
  end
end
