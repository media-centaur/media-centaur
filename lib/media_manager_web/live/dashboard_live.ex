defmodule MediaManagerWeb.DashboardLive do
  use MediaManagerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
        assign(socket, watcher_state: MediaManager.Watcher.state())
      else
        assign(socket, watcher_state: :initializing)
      end

    {:ok, assign(socket, recent_files: [])}
  end

  @impl true
  def handle_info({:watcher_state_changed, new_state}, socket) do
    {:noreply, assign(socket, watcher_state: new_state)}
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
        <%= if @watcher_state == :media_dir_unavailable do %>
          <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
            Media directory not accessible — removal events suppressed
          </div>
        <% end %>
        <h1 class="text-2xl font-bold mb-4">Media Manager</h1>
        <p>Watcher state: <strong>{@watcher_state}</strong></p>
      </div>
    </Layouts.app>
    """
  end
end
