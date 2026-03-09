defmodule MediaCentaurWeb.LibraryLive do
  use MediaCentaurWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/library">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Library</h1>

        <section id="continue-watching">
          <h2 class="text-lg font-semibold mb-2">Continue Watching</h2>
          <p class="text-base-content/50 text-sm">Coming soon.</p>
        </section>

        <div class="divider" />

        <section id="browse">
          <h2 class="text-lg font-semibold mb-2">Browse</h2>
          <p class="text-base-content/50 text-sm">Coming soon.</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
