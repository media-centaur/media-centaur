defmodule MediaManagerWeb.ReviewLive do
  use MediaManagerWeb, :live_view

  alias MediaManager.Review

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "review:updates")

        socket
        |> assign(files: Review.fetch_pending_files())
      else
        socket
        |> assign(files: [])
      end

    {:ok,
     socket
     |> assign(processing: MapSet.new())
     |> assign(search_open: nil)
     |> assign(search_query: "")
     |> assign(search_type: :movie)
     |> assign(search_results: [])
     |> assign(searching: false)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    file = Enum.find(socket.assigns.files, &(&1.id == id))

    if file do
      Review.approve_and_process(file)
      {:noreply, assign(socket, processing: MapSet.put(socket.assigns.processing, id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    file = Enum.find(socket.assigns.files, &(&1.id == id))

    if file do
      socket = assign(socket, processing: MapSet.put(socket.assigns.processing, id))
      Review.dismiss(file)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_search", %{"id" => id}, socket) do
    file = Enum.find(socket.assigns.files, &(&1.id == id))

    search_type =
      case file && file.parsed_type do
        :tv -> :tv
        _ -> :movie
      end

    {:noreply,
     socket
     |> assign(search_open: id)
     |> assign(search_query: (file && file.parsed_title) || "")
     |> assign(search_type: search_type)
     |> assign(search_results: [])
     |> assign(searching: false)}
  end

  def handle_event("close_search", _params, socket) do
    {:noreply,
     socket
     |> assign(search_open: nil)
     |> assign(search_query: "")
     |> assign(search_results: [])
     |> assign(searching: false)}
  end

  def handle_event("search", %{"query" => query, "type" => type}, socket) do
    type = String.to_existing_atom(type)
    socket = assign(socket, searching: true, search_query: query, search_type: type)

    case Review.search_tmdb(query, type) do
      {:ok, results} ->
        {:noreply, assign(socket, search_results: results, searching: false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(search_results: [], searching: false)
         |> put_flash(:error, "TMDB search failed")}
    end
  end

  def handle_event(
        "select_match",
        %{"file-id" => file_id, "tmdb-id" => tmdb_id, "title" => title} = params,
        socket
      ) do
    file = Enum.find(socket.assigns.files, &(&1.id == file_id))

    if file do
      match = %{
        tmdb_id: tmdb_id,
        title: title,
        year: params["year"],
        poster_path: params["poster-path"]
      }

      case Review.set_tmdb_match(file, match) do
        {:ok, updated_file} ->
          files =
            Enum.map(socket.assigns.files, fn f ->
              if f.id == file_id, do: updated_file, else: f
            end)

          {:noreply,
           socket
           |> assign(files: files)
           |> assign(search_open: nil)
           |> assign(search_results: [])}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to set match")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:file_reviewed, file_id}, socket) do
    {:noreply,
     socket
     |> assign(files: Enum.reject(socket.assigns.files, &(&1.id == file_id)))
     |> assign(processing: MapSet.delete(socket.assigns.processing, file_id))}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/review">
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Review</h1>
          <span class="badge badge-warning">{length(@files)} pending</span>
        </div>

        <p :if={@files == []} class="text-base-content/60">
          No files awaiting review.
        </p>

        <div class="space-y-4">
          <.file_card
            :for={file <- sort_files(@files)}
            file={file}
            processing={MapSet.member?(@processing, file.id)}
            search_open={@search_open == file.id}
            search_query={@search_query}
            search_type={@search_type}
            search_results={@search_results}
            searching={@searching}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Private Function Components ---

  defp file_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm relative">
      <div
        :if={@processing}
        class="absolute inset-0 bg-base-100/80 z-10 flex items-center justify-center rounded-2xl"
      >
        <span class="loading loading-spinner loading-lg"></span>
      </div>

      <div class="card-body p-4">
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
            <p class="font-mono text-xs text-base-content/70 truncate" title={@file.file_path}>
              {@file.file_path}
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
            </p>

            <p :if={@file.tmdb_id} class="text-sm">
              <span class="font-medium">Match:</span>
              {@file.match_title || "TMDB ##{@file.tmdb_id}"}
              <span :if={@file.match_year} class="text-base-content/60">
                ({@file.match_year})
              </span>
              <span class="text-base-content/50">TMDB #{@file.tmdb_id}</span>
              <span
                :if={@file.confidence_score}
                class={["badge badge-sm ml-1", confidence_badge_class(@file.confidence_score)]}
              >
                {Float.round(@file.confidence_score, 2)}
              </span>
            </p>

            <p :if={!@file.tmdb_id} class="text-sm text-base-content/50">
              <span class="font-medium">Match:</span> No TMDB results
            </p>

            <div class="flex gap-2 pt-2">
              <button
                :if={@file.tmdb_id}
                phx-click="approve"
                phx-value-id={@file.id}
                disabled={@processing}
                class="btn btn-success btn-sm"
              >
                Approve
              </button>
              <button
                phx-click="open_search"
                phx-value-id={@file.id}
                disabled={@processing}
                class="btn btn-info btn-sm btn-outline"
              >
                Search
              </button>
              <button
                phx-click="dismiss"
                phx-value-id={@file.id}
                disabled={@processing}
                class="btn btn-ghost btn-sm"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>

        <.search_panel
          :if={@search_open}
          file={@file}
          query={@search_query}
          type={@search_type}
          results={@search_results}
          searching={@searching}
        />
      </div>
    </div>
    """
  end

  defp search_panel(assigns) do
    ~H"""
    <div class="mt-4 border border-base-300 rounded-lg p-4 space-y-3">
      <form phx-submit="search" class="flex gap-2 items-end">
        <div class="form-control flex-1">
          <label class="label py-0"><span class="label-text text-xs">Search</span></label>
          <input
            type="text"
            name="query"
            value={@query}
            class="input input-bordered input-sm w-full"
            placeholder="Title..."
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
            phx-value-file-id={@file.id}
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

  defp sort_files(files) do
    Enum.sort_by(files, fn file ->
      {if(file.tmdb_id, do: 1, else: 0), file.confidence_score || 0}
    end)
  end

  defp format_type(:movie), do: "Movie"
  defp format_type(:tv), do: "TV"
  defp format_type(:extra), do: "Extra"
  defp format_type(:unknown), do: "Unknown"
  defp format_type(nil), do: "Unknown"
  defp format_type(type), do: type |> to_string() |> String.capitalize()

  defp confidence_badge_class(score) when score >= 0.8, do: "badge-success"
  defp confidence_badge_class(score) when score >= 0.5, do: "badge-warning"
  defp confidence_badge_class(_), do: "badge-error"
end
