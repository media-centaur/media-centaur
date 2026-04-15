defmodule MediaCentaurWeb.SearchLive do
  @moduledoc """
  Media search and acquisition page.

  Searches Prowlarr for releases matching a query and lets the user grab a
  result directly from the UI. Only rendered when Prowlarr is configured;
  unauthenticated requests are redirected to the library.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.Quality

  @impl true
  def mount(_params, _session, socket) do
    unless Acquisition.available?() do
      {:ok, push_navigate(socket, to: "/")}
    else
      if connected?(socket), do: Acquisition.subscribe()

      {:ok,
       assign(socket,
         query: "",
         results: [],
         searching: false,
         grabbing_guid: nil,
         grab_message: nil
       )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/search">
      <div class="max-w-4xl mx-auto space-y-6 py-6">
        <h1 class="text-2xl font-bold">Search</h1>

        <%!-- Search form --%>
        <div class="glass-surface rounded-xl p-4">
          <form phx-submit="search" class="flex gap-3 items-end">
            <div class="flex-1">
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Title
              </label>
              <input
                type="text"
                name="query"
                value={@query}
                class="input input-bordered w-full"
                placeholder="Search for a movie or TV show…"
                autofocus
                data-nav-item
                tabindex="0"
              />
            </div>
            <button
              type="submit"
              class="btn btn-soft btn-primary"
              disabled={@searching}
              data-nav-item
              tabindex="0"
            >
              <span :if={@searching} class="loading loading-spinner loading-sm"></span>
              <.icon :if={!@searching} name="hero-magnifying-glass" class="size-4" /> Search
            </button>
          </form>
        </div>

        <%!-- Grab feedback --%>
        <div
          :if={@grab_message}
          class={[
            "glass-inset rounded-lg px-4 py-3 text-sm flex items-center gap-2",
            match?({:ok, _}, @grab_message) && "text-success",
            match?({:error, _}, @grab_message) && "text-error"
          ]}
        >
          <.icon
            :if={match?({:ok, _}, @grab_message)}
            name="hero-check-circle-mini"
            class="size-4 shrink-0"
          />
          <.icon
            :if={match?({:error, _}, @grab_message)}
            name="hero-x-circle-mini"
            class="size-4 shrink-0"
          />
          {grab_message_text(@grab_message)}
        </div>

        <%!-- Empty state --%>
        <p
          :if={@results == [] && !@searching && @query != ""}
          class="text-center text-base-content/40 py-16"
        >
          No results found for "{@query}".
        </p>

        <%!-- Results --%>
        <div :if={@results != []} class="glass-inset rounded-xl overflow-hidden">
          <div class="px-4 py-2 border-b border-base-content/5">
            <span class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              {length(@results)} result{if length(@results) == 1, do: "", else: "s"} for "{@query}"
            </span>
          </div>

          <div
            :for={result <- @results}
            class="flex items-center gap-3 px-4 py-3 border-b border-base-content/5 last:border-0 hover:bg-base-content/5"
          >
            <%!-- Quality badge --%>
            <span class={["text-xs font-bold w-10 shrink-0", quality_color(result.quality)]}>
              {Quality.label(result.quality)}
            </span>

            <%!-- Title --%>
            <span class="flex-1 min-w-0 text-sm truncate" title={result.title}>
              {result.title}
            </span>

            <%!-- Metadata --%>
            <div class="flex items-center gap-4 shrink-0 text-xs text-base-content/50">
              <span :if={result.size_bytes} class="tabular-nums">
                {format_bytes(result.size_bytes)}
              </span>
              <span :if={result.seeders} class={["tabular-nums", seeder_color(result.seeders)]}>
                {result.seeders}S
              </span>
              <span class="max-w-24 truncate">{result.indexer_name}</span>
            </div>

            <%!-- Grab button --%>
            <button
              class="btn btn-soft btn-success btn-sm shrink-0"
              phx-click="grab"
              phx-value-guid={result.guid}
              phx-value-indexer-id={result.indexer_id}
              disabled={@grabbing_guid != nil}
              data-nav-item
              tabindex="0"
            >
              <span
                :if={@grabbing_guid == result.guid}
                class="loading loading-spinner loading-xs"
              >
              </span>
              <.icon
                :if={@grabbing_guid != result.guid}
                name="hero-arrow-down-tray-mini"
                class="size-4"
              /> Grab
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply, assign(socket, results: [], query: query)}
    else
      socket = assign(socket, searching: true, query: query, results: [], grab_message: nil)
      send(self(), {:do_search, query})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "grab",
        %{"guid" => guid},
        socket
      ) do
    result = Enum.find(socket.assigns.results, &(&1.guid == guid))

    if result do
      socket = assign(socket, grabbing_guid: guid, grab_message: nil)
      send(self(), {:do_grab, result})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:do_search, query}, socket) do
    case Acquisition.search(query) do
      {:ok, results} ->
        sorted = Enum.sort_by(results, &Quality.rank(&1.quality), :desc)
        {:noreply, assign(socket, results: sorted, searching: false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(results: [], searching: false)
         |> put_flash(:error, "Search failed — check Prowlarr connection in Settings")}
    end
  end

  @impl true
  def handle_info({:do_grab, result}, socket) do
    message =
      case Acquisition.grab(result) do
        :ok -> {:ok, result.title}
        {:error, reason} -> {:error, reason}
      end

    {:noreply, assign(socket, grabbing_guid: nil, grab_message: message)}
  end

  @impl true
  def handle_info({:grab_submitted, _grab}, socket), do: {:noreply, socket}
  def handle_info({:search_retry_scheduled, _grab}, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Pure helpers ---

  defp grab_message_text({:ok, title}), do: "Grab submitted — #{title}"
  defp grab_message_text({:error, _}), do: "Grab failed — check Prowlarr and your download client"

  defp quality_color(:uhd_4k), do: "text-success"
  defp quality_color(:hd_1080p), do: "text-info"
  defp quality_color(nil), do: "text-base-content/40"

  defp seeder_color(n) when n >= 10, do: "text-success"
  defp seeder_color(n) when n >= 3, do: "text-warning"
  defp seeder_color(_), do: "text-error"

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    gb = Float.round(bytes / 1_073_741_824, 1)
    "#{gb} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    mb = round(bytes / 1_048_576)
    "#{mb} MB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"
end
