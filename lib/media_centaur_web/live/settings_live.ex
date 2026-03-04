defmodule MediaCentaurWeb.SettingsLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Admin, Log}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "logging:updates")

        {enabled, all} = Log.status()

        socket
        |> assign(config: load_config())
        |> assign(enabled_components: enabled)
        |> assign(all_components: all)
        |> assign(suppressed_frameworks: Log.suppressed_frameworks())
      else
        socket
        |> assign(config: %{})
        |> assign(enabled_components: [])
        |> assign(all_components: [])
        |> assign(suppressed_frameworks: [])
      end

    {:ok,
     assign(socket,
       clearing_database: false,
       refreshing_images: false
     )}
  end

  # --- Events ---

  @impl true
  def handle_event("clear_database", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      Admin.clear_database()
      send(liveview, :database_cleared)
    end)

    {:noreply, assign(socket, clearing_database: true)}
  end

  def handle_event("refresh_image_cache", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      {:ok, count} = Admin.refresh_image_cache()
      send(liveview, {:image_cache_refreshed, count})
    end)

    {:noreply, assign(socket, refreshing_images: true)}
  end

  def handle_event("toggle_component", %{"component" => component}, socket) do
    component = String.to_existing_atom(component)

    if component in socket.assigns.enabled_components do
      Log.disable(component)
    else
      Log.enable(component)
    end

    {:noreply, assign_log_state(socket)}
  end

  def handle_event("enable_all", _params, socket) do
    Log.all()
    {:noreply, assign_log_state(socket)}
  end

  def handle_event("disable_all", _params, socket) do
    Log.none()
    {:noreply, assign_log_state(socket)}
  end

  def handle_event("toggle_framework", %{"key" => key}, socket) do
    key = String.to_existing_atom(key)

    if key in socket.assigns.suppressed_frameworks do
      Log.unsuppress_framework(key)
    else
      Log.suppress_framework(key)
    end

    {:noreply, assign_log_state(socket)}
  end

  # --- Info handlers ---

  @impl true
  def handle_info(:database_cleared, socket) do
    {:noreply,
     socket
     |> assign(clearing_database: false)
     |> put_flash(:info, "Database cleared successfully")}
  end

  def handle_info({:image_cache_refreshed, count}, socket) do
    {:noreply,
     socket
     |> assign(refreshing_images: false)
     |> put_flash(:info, "Image cache refreshed — re-downloaded images for #{count} entities")}
  end

  def handle_info(:log_settings_changed, socket) do
    {:noreply, assign_log_state(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <h1 class="text-2xl font-bold sm:col-span-2">Settings</h1>

        <div class="sm:col-span-2">
          <.logging_card
            enabled={@enabled_components}
            all={@all_components}
            suppressed={@suppressed_frameworks}
          />
        </div>

        <.config_overview config={@config} />
        <.danger_zone
          clearing_database={@clearing_database}
          refreshing_images={@refreshing_images}
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp logging_card(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <%!-- Thinking Logs section --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Component Logs</h2>
          <div class="flex gap-2">
            <button phx-click="enable_all" class="btn btn-xs btn-outline btn-success">
              Enable all
            </button>
            <button phx-click="disable_all" class="btn btn-xs btn-outline">
              Disable all
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-2">
          <div
            :for={component <- @all}
            class="flex items-center justify-between p-3 rounded-lg glass-inset"
          >
            <div>
              <span class="font-medium">{component}</span>
              <p class="text-xs text-base-content/50">{component_description(component)}</p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-success"
              checked={component in @enabled}
              phx-click="toggle_component"
              phx-value-component={component}
            />
          </div>
        </div>

        <div class="divider my-2"></div>

        <%!-- Framework Logs section --%>
        <h3 class="text-base font-semibold">Framework Logs</h3>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-2">
          <div
            :for={{key, _mod} <- Log.framework_modules()}
            class="flex items-center justify-between p-3 rounded-lg glass-inset"
          >
            <div>
              <span class="font-medium">{framework_label(key)}</span>
              <p class="text-xs text-base-content/50">{framework_description(key)}</p>
            </div>
            <label class="flex items-center gap-2 cursor-pointer">
              <span class={[
                "text-xs",
                if(key in @suppressed, do: "text-warning", else: "text-success")
              ]}>
                {if key in @suppressed, do: "suppressed", else: "active"}
              </span>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-warning"
                checked={key in @suppressed}
                phx-click="toggle_framework"
                phx-value-key={key}
              />
            </label>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp config_overview(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Configuration</h2>

        <div :if={@config == %{}} class="text-base-content/60">Loading...</div>

        <div :if={@config != %{}} class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-2 text-sm">
          <div class="flex justify-between gap-4">
            <span class="text-base-content/60 shrink-0">Auto-approve threshold</span>
            <span class="font-mono">{@config[:auto_approve_threshold] || "—"}</span>
          </div>
          <div class="flex justify-between gap-4 min-w-0">
            <span class="text-base-content/60 shrink-0">MPV path</span>
            <span class="font-mono truncate-left" title={@config[:mpv_path]}>
              {@config[:mpv_path] || "—"}
            </span>
          </div>
          <div class="flex justify-between gap-4 min-w-0">
            <span class="text-base-content/60 shrink-0">Database path</span>
            <span class="font-mono text-xs truncate-left" title={@config[:database_path]}>
              {@config[:database_path] || "—"}
            </span>
          </div>
          <div class="flex justify-between gap-4">
            <span class="text-base-content/60 shrink-0">Watch directories</span>
            <span class="font-mono">{@config[:watch_dirs_count] || 0}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp danger_zone(assigns) do
    ~H"""
    <div class="card glass-surface border border-error/20">
      <div class="card-body">
        <h2 class="card-title text-lg text-error">Danger Zone</h2>
        <div class="flex flex-wrap gap-3">
          <button
            phx-click="clear_database"
            disabled={@clearing_database}
            data-confirm="This will permanently delete ALL entities, files, images, and progress. This cannot be undone. Continue?"
            class="btn btn-error btn-sm btn-outline"
          >
            {if @clearing_database, do: "Clearing...", else: "Clear database"}
          </button>
          <button
            phx-click="refresh_image_cache"
            disabled={@refreshing_images}
            data-confirm="This will delete all cached artwork and re-download from TMDB. This may take a while. Continue?"
            class="btn btn-warning btn-sm btn-outline"
          >
            {if @refreshing_images, do: "Refreshing...", else: "Clear & refresh image cache"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Private helpers ---

  defp assign_log_state(socket) do
    {enabled, all} = Log.status()

    socket
    |> assign(enabled_components: enabled)
    |> assign(all_components: all)
    |> assign(suppressed_frameworks: Log.suppressed_frameworks())
  end

  defp load_config do
    config = MediaCentaur.Config

    %{
      tmdb_configured: config.get(:tmdb_api_key) not in [nil, ""],
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

  defp component_description(:watcher), do: "file events, size checks, detection"
  defp component_description(:pipeline), do: "processing steps, batch results"
  defp component_description(:tmdb), do: "API calls, rate limiting, confidence"
  defp component_description(:playback), do: "play/pause/stop, session lifecycle"
  defp component_description(:channel), do: "library sync, entity pushes"
  defp component_description(:library), do: "entity resolver, browser, admin"

  defp framework_label(:ecto), do: "Ecto SQL queries"
  defp framework_label(:phoenix), do: "Phoenix requests"
  defp framework_label(:live_view), do: "LiveView events"

  defp framework_description(:ecto), do: "full SQL dumped on every query"
  defp framework_description(:phoenix), do: "HTTP request logs for every interaction"
  defp framework_description(:live_view), do: "mount, handle_event, handle_params logs"
end
