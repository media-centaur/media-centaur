defmodule MediaCentaurWeb.SettingsLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Admin, Library, Log}
  alias MediaCentaur.Watcher
  alias MediaCentaur.Pipeline
  alias MediaCentaur.ImagePipeline

  @sections [
    %{id: "services", label: "Services"},
    %{id: "logging", label: "Logging"},
    %{id: "configuration", label: "Configuration"},
    %{id: "danger", label: "Danger Zone"}
  ]

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
        |> assign(watchers_running: Watcher.Supervisor.running?())
        |> assign(pipeline_running: Pipeline.Supervisor.pipeline_running?())
        |> assign(image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?())
      else
        socket
        |> assign(config: %{})
        |> assign(enabled_components: [])
        |> assign(all_components: [])
        |> assign(suppressed_frameworks: [])
        |> assign(watchers_running: false)
        |> assign(pipeline_running: false)
        |> assign(image_pipeline_running: false)
      end

    {:ok,
     assign(socket,
       sections: @sections,
       clearing_database: false,
       refreshing_images: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = params["section"] || "services"
    {:noreply, assign(socket, active_section: section)}
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

  def handle_event("toggle_watchers", _params, socket) do
    if socket.assigns.watchers_running do
      Watcher.Supervisor.stop_watchers()
      persist_service_flag(:start_watchers, false)
    else
      Watcher.Supervisor.start_watchers()
      persist_service_flag(:start_watchers, true)
    end

    {:noreply, assign(socket, watchers_running: Watcher.Supervisor.running?())}
  end

  def handle_event("toggle_pipeline", _params, socket) do
    if socket.assigns.pipeline_running do
      Pipeline.Supervisor.stop_pipeline()
      persist_service_flag(:start_pipeline, false)
    else
      Pipeline.Supervisor.start_pipeline()
      persist_service_flag(:start_pipeline, true)
    end

    {:noreply, assign(socket, pipeline_running: Pipeline.Supervisor.pipeline_running?())}
  end

  def handle_event("toggle_image_pipeline", _params, socket) do
    if socket.assigns.image_pipeline_running do
      ImagePipeline.Supervisor.stop_pipeline()
    else
      ImagePipeline.Supervisor.start_pipeline()
    end

    {:noreply,
     assign(socket, image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?())}
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
      <div
        data-page-behavior="settings"
        data-nav-default-zone="settings"
        class="settings-layout"
      >
        <nav data-nav-zone="sections" class="section-nav">
          <h1 class="text-xl font-bold mb-4">Settings</h1>
          <.link
            :for={section <- @sections}
            patch={~p"/settings?section=#{section.id}"}
            data-nav-item
            tabindex="0"
            class={["section-nav-item", @active_section == section.id && "menu-item-active"]}
          >
            {section.label}
          </.link>
        </nav>

        <div data-nav-zone="grid" class="settings-content">
          <.section_content
            active_section={@active_section}
            watchers_running={@watchers_running}
            pipeline_running={@pipeline_running}
            image_pipeline_running={@image_pipeline_running}
            enabled_components={@enabled_components}
            all_components={@all_components}
            suppressed_frameworks={@suppressed_frameworks}
            config={@config}
            clearing_database={@clearing_database}
            refreshing_images={@refreshing_images}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Section router ---

  defp section_content(%{active_section: "services"} = assigns) do
    ~H"""
    <div data-nav-grid class="settings-card glass-surface">
      <h2 class="settings-section-title">Services</h2>
      <p class="settings-section-desc">
        Start or stop background services. State is saved per environment.
      </p>

      <.settings_row
        label="Watchers"
        description="File system monitoring for media directories"
        checked={@watchers_running}
        event="toggle_watchers"
        color="info"
      />
      <.settings_row
        label="Pipeline"
        description="Metadata search and entity ingestion"
        checked={@pipeline_running}
        event="toggle_pipeline"
        color="info"
      />
      <.settings_row
        label="Image Pipeline"
        description="Artwork downloading and processing"
        checked={@image_pipeline_running}
        event="toggle_image_pipeline"
        color="info"
      />
    </div>
    """
  end

  defp section_content(%{active_section: "logging"} = assigns) do
    ~H"""
    <div data-nav-grid class="settings-card glass-surface">
      <div class="flex items-center justify-between">
        <h2 class="settings-section-title">Component Logs</h2>
        <div class="flex gap-2">
          <button
            phx-click="enable_all"
            data-nav-item
            tabindex="0"
            class="btn btn-xs btn-soft btn-success"
          >
            Enable all
          </button>
          <button
            phx-click="disable_all"
            data-nav-item
            tabindex="0"
            class="btn btn-xs btn-outline"
          >
            Disable all
          </button>
        </div>
      </div>
      <p class="settings-section-desc">
        Per-component decision logs. Enable to see thinking in the terminal.
      </p>

      <.settings_row
        :for={component <- @all_components}
        label={component}
        description={component_description(component)}
        checked={component in @enabled_components}
        event="toggle_component"
        event_value={%{component: component}}
        color="success"
      />

      <div class="mt-6">
        <h2 class="settings-section-title">Framework Logs</h2>
        <p class="settings-section-desc">
          Suppress noisy library output at runtime. Suppressed modules only emit warning and above.
        </p>

        <.settings_row
          :for={{key, _mod} <- Log.framework_modules()}
          label={framework_label(key)}
          description={framework_description(key)}
          checked={key in @suppressed_frameworks}
          event="toggle_framework"
          event_value={%{key: key}}
          color="warning"
        />
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "configuration"} = assigns) do
    ~H"""
    <div class="settings-card glass-surface">
      <h2 class="settings-section-title">Configuration</h2>
      <p class="settings-section-desc">
        Read-only view of the current configuration.
      </p>

      <div :if={@config == %{}} class="text-base-content/60 py-4">Loading...</div>

      <div :if={@config != %{}} class="space-y-3 text-sm mt-3">
        <div class="settings-config-row">
          <span class="text-base-content/60">Auto-approve threshold</span>
          <span class="font-mono">{@config[:auto_approve_threshold] || "—"}</span>
        </div>
        <div class="settings-config-row min-w-0">
          <span class="text-base-content/60 shrink-0">MPV path</span>
          <span class="font-mono truncate-left" title={@config[:mpv_path]}>
            {@config[:mpv_path] || "—"}
          </span>
        </div>
        <div class="settings-config-row min-w-0">
          <span class="text-base-content/60 shrink-0">Database path</span>
          <span class="font-mono text-xs truncate-left" title={@config[:database_path]}>
            {@config[:database_path] || "—"}
          </span>
        </div>
        <div class="settings-config-row">
          <span class="text-base-content/60">Watch directories</span>
          <span class="font-mono">{@config[:watch_dirs_count] || 0}</span>
        </div>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "danger"} = assigns) do
    ~H"""
    <div data-nav-grid class="settings-card glass-surface border border-error/20">
      <h2 class="settings-section-title text-error">Danger Zone</h2>
      <p class="settings-section-desc">
        Destructive actions that cannot be undone.
      </p>

      <div class="flex flex-wrap gap-3 mt-3">
        <button
          phx-click="clear_database"
          disabled={@clearing_database}
          data-confirm="This will permanently delete ALL entities, files, images, and progress. This cannot be undone. Continue?"
          data-nav-item
          tabindex="0"
          class="btn btn-soft btn-error btn-sm"
        >
          {if @clearing_database, do: "Clearing...", else: "Clear database"}
        </button>
        <button
          phx-click="refresh_image_cache"
          disabled={@refreshing_images}
          data-confirm="This will delete all cached artwork and re-download from TMDB. This may take a while. Continue?"
          data-nav-item
          tabindex="0"
          class="btn btn-soft btn-warning btn-sm"
        >
          {if @refreshing_images, do: "Refreshing...", else: "Clear & refresh image cache"}
        </button>
      </div>
    </div>
    """
  end

  defp section_content(assigns) do
    ~H"""
    <div class="settings-card glass-surface">
      <p class="text-base-content/60">Unknown section.</p>
    </div>
    """
  end

  # --- Shared components ---

  attr :label, :any, required: true
  attr :description, :string, required: true
  attr :checked, :boolean, required: true
  attr :event, :string, required: true
  attr :event_value, :map, default: %{}
  attr :color, :string, default: "info"

  defp settings_row(assigns) do
    ~H"""
    <div class="settings-row" data-nav-item tabindex="0" phx-click={@event} {phx_values(@event_value)}>
      <div>
        <span class="font-medium">{@label}</span>
        <p class="text-xs text-base-content/50 mt-0.5">{@description}</p>
      </div>
      <input
        type="checkbox"
        class={"toggle toggle-sm toggle-#{@color}"}
        checked={@checked}
        tabindex="-1"
      />
    </div>
    """
  end

  # --- Private helpers ---

  defp phx_values(map) when map_size(map) == 0, do: %{}

  defp phx_values(map) do
    Map.new(map, fn {key, value} -> {:"phx-value-#{key}", value} end)
  end

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

  defp persist_service_flag(service, value) do
    env = Application.get_env(:media_centaur, :environment, :dev)
    Library.upsert_setting!(%{key: "services:#{env}:#{service}", value: to_string(value)})
  end

  defp component_description(:watcher), do: "file events, size checks, detection"
  defp component_description(:pipeline), do: "processing steps, batch results"
  defp component_description(:tmdb), do: "API calls, rate limiting, confidence"
  defp component_description(:playback), do: "play/pause/stop, session lifecycle"
  defp component_description(:library), do: "entity resolver, browser, admin"

  defp framework_label(:ecto), do: "Ecto SQL queries"
  defp framework_label(:phoenix), do: "Phoenix requests"
  defp framework_label(:live_view), do: "LiveView events"

  defp framework_description(:ecto), do: "full SQL dumped on every query"
  defp framework_description(:phoenix), do: "HTTP request logs for every interaction"
  defp framework_description(:live_view), do: "mount, handle_event, handle_params logs"
end
