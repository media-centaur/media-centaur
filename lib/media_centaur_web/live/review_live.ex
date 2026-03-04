defmodule MediaCentaurWeb.ReviewLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Review

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "review:updates")
        groups = Review.fetch_pending_groups()

        socket
        |> assign(groups: groups)
        |> assign(groups_by_key: Map.new(groups, &{&1.key, &1}))
      else
        socket
        |> assign(groups: [])
        |> assign(groups_by_key: %{})
      end

    {:ok,
     socket
     |> assign(processing: MapSet.new())
     |> assign(search_open: nil)
     |> assign(search_query: "")
     |> assign(search_type: :movie)
     |> assign(search_results: [])
     |> assign(searching: false)
     |> assign(searched: false)
     |> assign(reload_timer: nil)}
  end

  @impl true
  def handle_event("approve", %{"key" => key}, socket) do
    group_key = decode_key(key)
    group = socket.assigns.groups_by_key[group_key]

    if group do
      socket = assign(socket, processing: MapSet.put(socket.assigns.processing, group_key))

      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        {approved, errors} = Review.approve_group(group.files)

        if errors > 0 do
          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            "review:updates",
            {:group_error, group_key, "#{errors} file(s) failed to approve"}
          )
        end

        if approved > 0 do
          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            "review:updates",
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

  def handle_event("search", %{"query" => query, "type" => type}, socket) do
    type = String.to_existing_atom(type)
    socket = assign(socket, searching: true, search_query: query, search_type: type)

    case Review.search_tmdb(query, type) do
      {:ok, results} ->
        {:noreply, assign(socket, search_results: results, searching: false, searched: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(search_results: [], searching: false, searched: true)
         |> put_flash(:error, "TMDB search failed")}
    end
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
         |> assign(search_results: [])}
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
    expanded = if current == group_key, do: nil, else: group_key
    {:noreply, assign(socket, expanded_group: expanded)}
  end

  @impl true
  def handle_info({:file_added, _pending_file_id}, socket) do
    if socket.assigns.reload_timer, do: Process.cancel_timer(socket.assigns.reload_timer)
    timer = Process.send_after(self(), :reload_groups, 500)
    {:noreply, assign(socket, reload_timer: timer)}
  end

  def handle_info(:reload_groups, socket) do
    groups = Review.fetch_pending_groups()

    {:noreply,
     socket
     |> assign(groups: groups)
     |> assign(groups_by_key: Map.new(groups, &{&1.key, &1}))
     |> assign(reload_timer: nil)}
  end

  def handle_info({:file_reviewed, file_id}, socket) do
    groups =
      socket.assigns.groups
      |> Enum.map(fn group ->
        files = Enum.reject(group.files, &(&1.id == file_id))
        %{group | files: files, representative: List.first(files)}
      end)
      |> Enum.reject(fn group -> group.files == [] end)

    {:noreply,
     socket
     |> assign(groups: groups)
     |> assign(groups_by_key: Map.new(groups, &{&1.key, &1}))
     |> assign(processing: MapSet.delete(socket.assigns.processing, file_id))}
  end

  def handle_info({:group_error, group_key, message}, socket) do
    {:noreply,
     socket
     |> assign(processing: MapSet.delete(socket.assigns.processing, group_key))
     |> put_flash(:error, message)}
  end

  def handle_info({:group_approved, _group_key, _count}, socket) do
    # Files will be removed individually via :file_reviewed as pipeline completes
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    total_files = Enum.reduce(assigns.groups, 0, fn group, acc -> acc + length(group.files) end)
    reason_counts = count_by_reason(assigns.groups)

    assigns =
      assigns
      |> assign(total_files: total_files)
      |> assign(reason_counts: reason_counts)

    ~H"""
    <Layouts.app flash={@flash} current_path="/review">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Review</h1>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div class={[
            "p-4 rounded-lg glass-surface",
            if(@total_files > 0, do: "border-l-3 border-warning")
          ]}>
            <div class="text-2xl font-bold">{@total_files}</div>
            <div class="text-sm text-base-content/60">Pending Files</div>
          </div>
          <div class="p-4 rounded-lg glass-surface">
            <div class="text-2xl font-bold">{@reason_counts.no_results}</div>
            <div class="text-sm text-base-content/60">No Results</div>
          </div>
          <div class="p-4 rounded-lg glass-surface">
            <div class="text-2xl font-bold">{@reason_counts.tied}</div>
            <div class="text-sm text-base-content/60">Tied</div>
          </div>
          <div class="p-4 rounded-lg glass-surface">
            <div class="text-2xl font-bold">{@reason_counts.low_confidence}</div>
            <div class="text-sm text-base-content/60">Low Confidence</div>
          </div>
        </div>

        <div
          :if={@groups == []}
          class="glass-surface rounded-2xl py-12 flex flex-col items-center justify-center gap-3"
        >
          <.icon name="hero-check-circle" class="size-16 text-success/30" />
          <h2 class="text-xl font-semibold">All clear</h2>
          <p class="text-base-content/60">No files awaiting review.</p>
        </div>

        <div class="space-y-4">
          <.group_card
            :for={group <- sort_groups(@groups)}
            group={group}
            processing={MapSet.member?(@processing, group.key)}
            search_open={@search_open == group.key}
            search_query={@search_query}
            search_type={@search_type}
            search_results={@search_results}
            searching={@searching}
            searched={@searched}
            expanded={assigns[:expanded_group] == group.key}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Private Function Components ---

  defp group_card(assigns) do
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
    <div class="card glass-surface relative">
      <div
        :if={@processing}
        class="absolute inset-0 bg-base-300/60 backdrop-blur-sm z-10 flex items-center justify-center rounded-2xl"
      >
        <span class="loading loading-spinner loading-lg"></span>
      </div>

      <div class="card-body p-4">
        <%!-- Group heading for multi-file groups --%>
        <div :if={@file_count > 1} class="flex items-center justify-between mb-2">
          <h3 class="font-semibold text-base">{series_root_name(@group)}</h3>
          <button
            phx-click="toggle_files"
            phx-value-key={@encoded_key}
            class="btn btn-ghost btn-sm gap-1"
          >
            <span class="badge badge-sm badge-neutral">{@file_count} episodes</span>
            <.icon
              name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="size-4"
            />
          </button>
        </div>

        <div class="flex gap-5">
          <%!-- Poster --%>
          <div :if={@file.match_poster_path} class="shrink-0">
            <img
              src={"https://image.tmdb.org/t/p/w185#{@file.match_poster_path}"}
              alt="poster"
              class="w-[140px] rounded-lg"
            />
          </div>
          <div
            :if={!@file.match_poster_path}
            class="shrink-0 w-[140px] h-[210px] glass-inset rounded-lg flex items-center justify-center"
          >
            <.icon name="hero-film" class="size-12 opacity-30" />
          </div>

          <div class="flex-1 min-w-0 space-y-3">
            <%!-- File path + reason badge --%>
            <div class="flex items-start justify-between gap-2">
              <p
                :if={@file_count == 1}
                class="font-mono text-xs text-base-content/70 truncate-left"
                title={relative_file_path(@file)}
              >
                {relative_file_path(@file)}
              </p>
              <div :if={@file_count > 1} />
              <span class={["text-xs shrink-0", reason_text_class(@reason)]}>
                {reason_label(@reason)}
              </span>
            </div>

            <%!-- Parsed from filename panel --%>
            <div class="glass-inset rounded-lg p-3 space-y-1">
              <p class="text-[10px] font-semibold uppercase tracking-wide text-base-content/40">
                Parsed from filename
              </p>
              <p class="text-sm">
                <span class="font-medium">{@file.parsed_title || "Unknown"}</span>
                <span :if={@file.parsed_year} class="text-base-content/60">
                  ({@file.parsed_year})
                </span>
                <span class="badge badge-sm badge-outline ml-1">
                  {format_type(@file.parsed_type)}
                </span>
                <span
                  :if={@file_count == 1 && @file.season_number && @file.episode_number}
                  class="text-base-content/60 ml-1"
                >
                  S{zero_pad(@file.season_number)}E{zero_pad(@file.episode_number)}
                </span>
              </p>
            </div>

            <%!-- TMDB match panel (hidden when tied — candidates section replaces it) --%>
            <div :if={!@tied} class="glass-inset rounded-lg p-3 space-y-1">
              <p class="text-[10px] font-semibold uppercase tracking-wide text-base-content/40">
                TMDB Match
              </p>
              <p :if={@file.tmdb_id} class="text-sm">
                <span class="font-medium">{@file.match_title || "TMDB ##{@file.tmdb_id}"}</span>
                <span :if={@file.match_year} class="text-base-content/60">
                  ({@file.match_year})
                </span>
                <span class="text-base-content/50 ml-1">TMDB #{@file.tmdb_id}</span>
                <span
                  :if={@file.confidence}
                  class={["ml-1", confidence_text_class(@file.confidence)]}
                >
                  {round(@file.confidence * 100)}% confidence
                </span>
              </p>
              <p :if={!@file.tmdb_id} class="text-sm text-base-content/50">
                No results found
              </p>
            </div>

            <%!-- Tied candidates chooser --%>
            <.tied_candidates
              :if={@tied}
              candidates={sort_candidates_by_year(@file.candidates)}
              tmdb_type={@file.tmdb_type}
              encoded_key={@encoded_key}
            />

            <%!-- Action buttons --%>
            <div class="flex gap-2 pt-1">
              <button
                :if={@file.tmdb_id && !@tied}
                phx-click="approve"
                phx-value-key={@encoded_key}
                disabled={@processing}
                class="btn btn-soft btn-success btn-sm"
              >
                {if @file_count > 1, do: "Approve All", else: "Approve"}
              </button>
              <button
                phx-click="open_search"
                phx-value-key={@encoded_key}
                disabled={@processing}
                class="btn btn-soft btn-info btn-sm"
              >
                Search TMDB
              </button>
              <button
                phx-click="dismiss"
                phx-value-key={@encoded_key}
                disabled={@processing}
                class="btn btn-ghost btn-sm"
              >
                {if @file_count > 1, do: "Dismiss All", else: "Dismiss"}
              </button>
            </div>
          </div>
        </div>

        <%!-- Collapsible file list for multi-file groups --%>
        <div :if={@file_count > 1 && @expanded} class="glass-inset rounded-lg p-3 mt-3">
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
                {relative_file_path(file)}
              </span>
            </li>
          </ul>
        </div>

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
            <button
              phx-click="select_match"
              phx-value-key={@encoded_key}
              phx-value-tmdb-id={candidate["tmdb_id"]}
              phx-value-title={candidate["title"]}
              phx-value-year={candidate["year"]}
              phx-value-poster-path={candidate["poster_path"]}
              class="btn btn-sm btn-outline"
            >
              Select
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp search_panel(assigns) do
    ~H"""
    <div class="mt-4 glass-inset rounded-lg p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <.icon name="hero-magnifying-glass" class="size-5 text-base-content/60" />
          <span class="text-[10px] font-semibold uppercase tracking-wide text-base-content/40">
            TMDB Search
          </span>
        </div>
        <button phx-click="close_search" class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-x-mark" class="size-4" />
        </button>
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

      <form phx-submit="search" class="flex gap-2 items-end">
        <div class="form-control flex-1">
          <label class="label py-0"><span class="label-text text-xs">Search</span></label>
          <input
            type="text"
            name="query"
            value={@query}
            class="input input-bordered input-sm w-full"
            placeholder={
              if @type == :tv, do: "Show name, e.g. Sample Show One", else: "Movie title, e.g. The Matrix"
            }
          />
        </div>
        <div class="form-control">
          <label class="label py-0"><span class="label-text text-xs">Type</span></label>
          <select name="type" class="select select-bordered select-sm">
            <option value="movie" selected={@type == :movie}>Movie</option>
            <option value="tv" selected={@type == :tv}>TV</option>
          </select>
        </div>
        <button type="submit" class="btn btn-primary btn-sm" disabled={@searching}>
          {if @searching, do: "Searching...", else: "Search"}
        </button>
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
            class="shrink-0 w-12 h-18 glass-inset rounded flex items-center justify-center"
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

          <button
            phx-click="select_match"
            phx-value-key={@encoded_key}
            phx-value-tmdb-id={result.tmdb_id}
            phx-value-title={result.title}
            phx-value-year={result.year}
            phx-value-poster-path={result.poster_path}
            class="btn btn-sm btn-outline shrink-0"
          >
            Select
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp sort_groups(groups) do
    Enum.sort_by(groups, fn %{representative: file} ->
      {if(file.tmdb_id, do: 1, else: 0), file.confidence || 0}
    end)
  end

  defp review_reason(file) do
    cond do
      is_nil(file.tmdb_id) -> :no_results
      tied_candidates?(file) -> :tied
      true -> :low_confidence
    end
  end

  defp count_by_reason(groups) do
    Enum.reduce(groups, %{no_results: 0, tied: 0, low_confidence: 0}, fn group, acc ->
      reason = review_reason(group.representative)
      Map.update!(acc, reason, &(&1 + 1))
    end)
  end

  defp reason_label(:no_results), do: "No TMDB results"

  defp reason_label(:low_confidence), do: "Low confidence"

  defp reason_label(:tied), do: "Tied match"

  defp reason_text_class(:no_results), do: "text-error"
  defp reason_text_class(:low_confidence), do: "text-warning"
  defp reason_text_class(:tied), do: "text-info"

  defp tied_candidates?(%{candidates: candidates}) when is_list(candidates) do
    case candidates do
      [_, _ | _] ->
        scores = Enum.map(candidates, & &1["score"])
        length(Enum.uniq(scores)) == 1

      _ ->
        false
    end
  end

  defp tied_candidates?(_), do: false

  defp series_root_name(%{key: {_watch_dir, root}}), do: root

  defp tmdb_url("tv", id), do: "https://www.themoviedb.org/tv/#{id}"
  defp tmdb_url(_, id), do: "https://www.themoviedb.org/movie/#{id}"

  defp sort_candidates_by_year(candidates) do
    Enum.sort_by(candidates, fn c ->
      case c["year"] do
        nil -> 9999
        y when is_binary(y) -> String.to_integer(y)
        y when is_integer(y) -> y
      end
    end)
  end

  defp format_type("movie"), do: "Movie"
  defp format_type("tv"), do: "TV"
  defp format_type("extra"), do: "Extra"
  defp format_type("unknown"), do: "Unknown"
  defp format_type(nil), do: "Unknown"
  defp format_type(type) when is_atom(type), do: type |> Atom.to_string() |> String.capitalize()
  defp format_type(type), do: type |> to_string() |> String.capitalize()

  defp zero_pad(number) when number < 10, do: "0#{number}"
  defp zero_pad(number), do: "#{number}"

  defp confidence_text_class(score) when score >= 0.8, do: "text-success"
  defp confidence_text_class(score) when score >= 0.5, do: "text-warning"
  defp confidence_text_class(_), do: "text-error"

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

  defp decode_key(encoded) do
    encoded
    |> Base.url_decode64!()
    |> :erlang.binary_to_term([:safe])
  end
end
