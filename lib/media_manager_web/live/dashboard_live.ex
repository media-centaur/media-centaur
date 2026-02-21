defmodule MediaManagerWeb.DashboardLive do
  use MediaManagerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
        assign(socket, watcher_statuses: MediaManager.Watcher.Supervisor.statuses())
      else
        assign(socket, watcher_statuses: [])
      end

    {:ok, assign(socket, recent_files: [], scanning: false)}
  end

  @impl true
  def handle_event("scan", _params, socket) do
    socket = assign(socket, scanning: true)

    case MediaManager.Watcher.Supervisor.scan() do
      {:ok, count} ->
        message =
          case count do
            0 -> "Scan complete — no new files found"
            1 -> "Scan complete — 1 new file detected"
            n -> "Scan complete — #{n} new files detected"
          end

        {:noreply, socket |> put_flash(:info, message) |> assign(scanning: false)}
    end
  end

  @impl true
  def handle_info({:watcher_state_changed, _dir, _new_state}, socket) do
    {:noreply, assign(socket, watcher_statuses: MediaManager.Watcher.Supervisor.statuses())}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Media Manager</h1>
          <button
            phx-click="scan"
            disabled={@scanning}
            class="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white font-medium py-2 px-4 rounded transition-colors"
          >
            {if @scanning, do: "Scanning…", else: "Scan directories"}
          </button>
        </div>

        <h2 class="text-lg font-semibold mb-3">Watch directories</h2>

        <%= if @watcher_statuses == [] do %>
          <p class="text-gray-500">No watch directories configured.</p>
        <% else %>
          <ul class="space-y-2">
            <li :for={status <- @watcher_statuses} class="flex items-center gap-3">
              <span class={[
                "inline-block w-2.5 h-2.5 rounded-full",
                status_color(status.state)
              ]}>
              </span>
              <code class="text-sm">{status.dir}</code>
              <span class="text-sm text-gray-500">({status.state})</span>
            </li>
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp status_color(:watching), do: "bg-green-500"
  defp status_color(:initializing), do: "bg-yellow-500"
  defp status_color(_), do: "bg-red-500"
end
