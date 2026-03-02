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
     |> assign(searched: false)}
  end

  @impl true
  def handle_event("approve", %{"key" => key}, socket) do
    group_key = decode_key(key)
    group = socket.assigns.groups_by_key[group_key]

    if group do
      socket = assign(socket, processing: MapSet.put(socket.assigns.processing, group_key))

      Task.start(fn ->
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
          socket
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
    assigns = assign(assigns, total_files: total_files)

    ~H"""
    <Layouts.app flash={@flash} current_path="/review">
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Review</h1>
          <span class="badge badge-warning">{@total_files} pending</span>
        </div>

        <p :if={@groups == []} class="text-base-content/60">
          No files awaiting review.
        </p>

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
    <div class="card bg-base-100 shadow-sm relative">
      <div
        :if={@processing}
        class="absolute inset-0 bg-base-100/80 z-10 flex items-center justify-center rounded-2xl"
      >
        <span class="loading loading-spinner loading-lg"></span>
      </div>

      <div class="card-body p-4">
        <%!-- Group heading for multi-file groups --%>
        <div :if={@file_count > 1} class="flex items-center gap-2 mb-2">
          <h3 class="font-semibold text-base">{series_root_name(@group)}</h3>
          <span class="badge badge-sm badge-neutral">{@file_count} episodes</span>
        </div>

        <div class="flex gap-4">
          <div :if={@file.match_poster_path} class="shrink-0">
            <img
              src={"https://image.tmdb.org/t/p/w92#{@file.match_poster_path}"}
              alt="poster"
              class="w-[92px] rounded"
            />
          </div>
          <div
            :if={!@file.match_poster_path}
            class="shrink-0 w-[92px] h-[138px] bg-base-200 rounded flex items-center justify-center"
          >
            <.icon name="hero-film" class="size-8 opacity-30" />
          </div>

          <div class="flex-1 min-w-0 space-y-1">
            <p
              :if={@file_count == 1}
              class="font-mono text-xs text-base-content/70 truncate"
              title={@file.file_path}
            >
              {relative_file_path(@file)}
            </p>

            <p class="text-sm">
              <span class="font-medium">Parsed:</span>
              {@file.parsed_title || "Unknown"}
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
                · S{zero_pad(@file.season_number)}E{zero_pad(@file.episode_number)}
              </span>
            </p>

            <%!-- Review reason label --%>
            <p class="text-xs">
              <span class={["badge badge-sm", reason_badge_class(@reason)]}>
                {reason_label(@reason)}
              </span>
            </p>

            <p :if={@file.tmdb_id && !@tied} class="text-sm">
              <span class="font-medium">Match:</span>
              {@file.match_title || "TMDB ##{@file.tmdb_id}"}
              <span :if={@file.match_year} class="text-base-content/60">
                ({@file.match_year})
              </span>
              <span class="text-base-content/50">TMDB #{@file.tmdb_id}</span>
              <span
                :if={@file.confidence}
                class={["badge badge-sm ml-1", confidence_badge_class(@file.confidence)]}
              >
                {Float.round(@file.confidence, 2)}
              </span>
            </p>

            <p :if={!@file.tmdb_id} class="text-sm text-base-content/50">
              <span class="font-medium">Match:</span> No TMDB results
            </p>

            <%!-- Tied candidates chooser --%>
            <.tied_candidates
              :if={@tied}
              candidates={sort_candidates_by_year(@file.candidates)}
              tmdb_type={@file.tmdb_type}
              encoded_key={@encoded_key}
            />

            <div class="flex gap-2 pt-2">
              <button
                :if={@file.tmdb_id && !@tied}
                phx-click="approve"
                phx-value-key={@encoded_key}
                disabled={@processing}
                class="btn btn-success btn-sm"
              >
                {if @file_count > 1, do: "Approve All", else: "Approve"}
              </button>
              <button
                phx-click="open_search"
                phx-value-key={@encoded_key}
                disabled={@processing}
                class="btn btn-info btn-sm btn-outline"
              >
                Search
              </button>
              <button
                phx-click="dismiss"
                phx-value-key={@encoded_key}
                disabled={@processing}
                class="btn btn-ghost btn-sm"
              >
                {if @file_count > 1, do: "Dismiss All", else: "Dismiss"}
              </button>
              <button
                :if={@file_count > 1}
                phx-click="toggle_files"
                phx-value-key={@encoded_key}
                class="btn btn-ghost btn-sm ml-auto"
              >
                {if @expanded, do: "Hide files", else: "Show files"}
              </button>
            </div>
          </div>
        </div>

        <%!-- Collapsible file list for multi-file groups --%>
        <div :if={@file_count > 1 && @expanded} class="mt-3 border-t border-base-300 pt-3">
          <ul class="space-y-1">
            <li
              :for={file <- @group.files}
              class="font-mono text-xs text-base-content/70 truncate"
              title={file.file_path}
            >
              {relative_file_path(file)}
              <span
                :if={file.season_number && file.episode_number}
                class="text-base-content/50"
              >
                S{zero_pad(file.season_number)}E{zero_pad(file.episode_number)}
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
    <div class="mt-2 space-y-3">
      <p class="text-sm text-warning font-medium">
        Multiple TMDB results matched equally — choose the correct one:
      </p>
      <div class="space-y-3">
        <div
          :for={candidate <- @candidates}
          class="flex gap-3 p-3 rounded-lg border border-base-300 hover:border-primary transition-colors"
        >
          <div :if={candidate["poster_path"]} class="shrink-0">
            <img
              src={"https://image.tmdb.org/t/p/w92#{candidate["poster_path"]}"}
              alt="poster"
              class="w-16 rounded"
            />
          </div>
          <div
            :if={!candidate["poster_path"]}
            class="shrink-0 w-16 h-24 bg-base-200 rounded flex items-center justify-center"
          >
            <.icon name="hero-film" class="size-4 opacity-30" />
          </div>
          <div class="flex-1 min-w-0 space-y-1">
            <div class="flex items-baseline gap-2">
              <p class="text-sm font-medium">{candidate["title"]}</p>
              <span :if={candidate["year"]} class="text-xs text-base-content/60">
                ({candidate["year"]})
              </span>
            </div>
            <p :if={candidate["overview"]} class="text-xs text-base-content/60 line-clamp-2">
              {candidate["overview"]}
            </p>
            <a
              href={tmdb_url(@tmdb_type, candidate["tmdb_id"])}
              target="_blank"
              rel="noopener"
              class="text-xs text-info hover:underline inline-flex items-center gap-1"
            >
              TMDB #{candidate["tmdb_id"]}
              <.icon name="hero-arrow-top-right-on-square" class="size-3" />
            </a>
          </div>
          <div class="shrink-0 self-center">
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
    <div class="mt-4 border border-base-300 rounded-lg p-4 space-y-3">
      <p :if={@type == :tv} class="text-sm text-base-content/70">
        Match this episode to a TV series.
        <span :if={@file.season_number && @file.episode_number}>
          Season {@file.season_number}, Episode {@file.episode_number} already parsed from the filename.
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
        <button type="button" phx-click="close_search" class="btn btn-ghost btn-sm">
          Cancel
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
          class="flex items-center gap-3 p-2 rounded hover:bg-base-200"
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
            class="shrink-0 w-12 h-18 bg-base-200 rounded flex items-center justify-center"
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

  defp reason_label(:no_results), do: "No TMDB results"

  defp reason_label(:low_confidence), do: "Low confidence"

  defp reason_label(:tied), do: "Tied match"

  defp reason_badge_class(:no_results), do: "badge-error"
  defp reason_badge_class(:low_confidence), do: "badge-warning"
  defp reason_badge_class(:tied), do: "badge-info"

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

  defp confidence_badge_class(score) when score >= 0.8, do: "badge-success"
  defp confidence_badge_class(score) when score >= 0.5, do: "badge-warning"
  defp confidence_badge_class(_), do: "badge-error"

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
