defmodule MediaCentaurWeb.SettingsLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Admin, Settings}
  alias MediaCentaur.Watcher
  alias MediaCentaur.Pipeline
  alias MediaCentaur.ImagePipeline

  @sections [
    %{id: "services", label: "Services"},
    %{id: "preferences", label: "Preferences"},
    %{id: "acquisition", label: "Acquisition"},
    %{id: "configuration", label: "Configuration"},
    %{id: "danger", label: "Danger Zone"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Settings.subscribe()
        Watcher.Supervisor.subscribe()

        socket
        |> assign(config: load_config())
        |> assign(watchers_running: Watcher.Supervisor.running?())
        |> assign(pipeline_running: Pipeline.Supervisor.pipeline_running?())
        |> assign(image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?())
      else
        socket
        |> assign(config: %{})
        |> assign(watchers_running: false)
        |> assign(pipeline_running: false)
        |> assign(image_pipeline_running: false)
      end

    spoiler_free = load_spoiler_free_setting()

    {:ok,
     assign(socket,
       sections: @sections,
       scanning: false,
       clearing_database: false,
       refreshing_images: false,
       spoiler_free: spoiler_free,
       prowlarr_test_status: nil,
       prowlarr_testing: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = params["section"] || "services"
    {:noreply, assign(socket, active_section: section)}
  end

  # --- Events ---

  @impl true
  def handle_event("scan", _params, socket) do
    socket = assign(socket, scanning: true)

    case MediaCentaur.Watcher.Supervisor.scan() do
      {:ok, count} ->
        message =
          case count do
            0 -> "Scan complete — no new files found"
            1 -> "Scan complete — 1 new file detected"
            n -> "Scan complete — #{n} new files detected"
          end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(scanning: false)}
    end
  end

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
      Watcher.Supervisor.start_image_dir_monitors()
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

  def handle_event("toggle_spoiler_free", _params, socket) do
    enabled = !socket.assigns.spoiler_free

    Settings.find_or_create_entry!(%{
      key: "spoiler_free_mode",
      value: %{"enabled" => enabled}
    })

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.settings_updates(),
      {:setting_changed, "spoiler_free_mode", enabled}
    )

    {:noreply, assign(socket, spoiler_free: enabled)}
  end

  @impl true
  def handle_event("test_prowlarr", _params, socket) do
    parent = self()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      status =
        case MediaCentaur.Acquisition.search("test", []) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end

      send(parent, {:prowlarr_test_result, status})
    end)

    {:noreply, assign(socket, prowlarr_testing: true, prowlarr_test_status: nil)}
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

  # Cross-tab sync — another tab toggled spoiler_free
  def handle_info({:setting_changed, "spoiler_free_mode", enabled}, socket) do
    {:noreply, assign(socket, spoiler_free: enabled)}
  end

  # Watcher/pipeline state change — refresh service toggle states
  def handle_info({:dir_state_changed, _dir, _role, _state}, socket) do
    {:noreply,
     socket
     |> assign(watchers_running: Watcher.Supervisor.running?())
     |> assign(pipeline_running: Pipeline.Supervisor.pipeline_running?())
     |> assign(image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?())}
  end

  def handle_info({:prowlarr_test_result, status}, socket) do
    {:noreply, assign(socket, prowlarr_testing: false, prowlarr_test_status: status)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/settings">
      <div
        data-page-behavior="settings"
        data-nav-default-zone="settings"
        class="flex gap-8 max-w-[960px]"
      >
        <nav
          data-nav-zone="sections"
          class="w-40 shrink-0 sticky top-6 self-start flex flex-col gap-0.5"
        >
          <h1 class="text-xl font-bold mb-4">Settings</h1>
          <.link
            :for={section <- @sections}
            patch={~p"/settings?section=#{section.id}"}
            data-nav-item
            tabindex="0"
            class={[
              "block py-2 px-3 rounded-lg text-sm text-base-content/70 transition-[opacity,background-color] duration-150 hover:opacity-100 hover:bg-base-content/6",
              @active_section == section.id &&
                "!opacity-100 text-primary bg-primary/10 font-medium"
            ]}
          >
            {section.label}
          </.link>
        </nav>

        <div data-nav-zone="grid" class="flex-1 min-w-0">
          <.section_content
            active_section={@active_section}
            watchers_running={@watchers_running}
            pipeline_running={@pipeline_running}
            image_pipeline_running={@image_pipeline_running}
            scanning={@scanning}
            config={@config}
            clearing_database={@clearing_database}
            refreshing_images={@refreshing_images}
            spoiler_free={@spoiler_free}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Section router ---

  defp section_content(%{active_section: "services"} = assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface">
      <h2 class="text-lg font-semibold">Services</h2>
      <p class="text-sm opacity-50 mt-0.5 mb-2">
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

      <div class="mt-4 pt-4 border-t border-base-content/10">
        <button
          phx-click="scan"
          disabled={@scanning}
          data-nav-item
          tabindex="0"
          class="btn btn-soft btn-info btn-sm"
        >
          {if @scanning, do: "Scanning…", else: "Scan directories"}
        </button>
        <p class="text-xs text-base-content/50 mt-1">
          Manually scan all watch directories for new media files.
        </p>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "preferences"} = assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface">
      <h2 class="text-lg font-semibold">Preferences</h2>
      <p class="text-sm opacity-50 mt-0.5 mb-2">
        Customize your browsing experience.
      </p>

      <.settings_row
        label="Spoiler Free Mode"
        description="Blur episode descriptions until you hover over them"
        checked={@spoiler_free}
        event="toggle_spoiler_free"
        color="info"
      />
    </div>
    """
  end

  defp section_content(%{active_section: "configuration"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface">
      <h2 class="text-lg font-semibold">Configuration</h2>
      <p class="text-sm opacity-50 mt-0.5 mb-2">
        Read-only view of the current configuration.
      </p>

      <div :if={@config == %{}} class="text-base-content/60 py-4">Loading...</div>

      <div :if={@config != %{}} class="space-y-3 text-sm mt-3">
        <div class="flex justify-between items-baseline gap-4">
          <span class="text-base-content/60">Auto-approve threshold</span>
          <span class="font-mono">{@config[:auto_approve_threshold] || "—"}</span>
        </div>
        <div class="flex justify-between items-baseline gap-4 min-w-0">
          <span class="text-base-content/60 shrink-0">MPV path</span>
          <span class="font-mono truncate-left" title={@config[:mpv_path]}>
            <bdo dir="ltr">{@config[:mpv_path] || "—"}</bdo>
          </span>
        </div>
        <div class="flex justify-between items-baseline gap-4 min-w-0">
          <span class="text-base-content/60 shrink-0">Database path</span>
          <span class="font-mono text-xs min-w-0 truncate-left" title={@config[:database_path]}>
            <bdo dir="ltr">{@config[:database_path] || "—"}</bdo>
          </span>
        </div>
        <div
          :for={dir <- @config[:watch_dirs]}
          class="flex justify-between items-baseline gap-4 min-w-0"
        >
          <span :if={dir == List.first(@config[:watch_dirs])} class="text-base-content/60 shrink-0">
            Watch directories
          </span>
          <span :if={dir != List.first(@config[:watch_dirs])} class="shrink-0"></span>
          <span class="font-mono text-xs min-w-0 truncate-left" title={dir}>
            <bdo dir="ltr">{dir}</bdo>
          </span>
        </div>
        <div :if={@config[:watch_dirs] == []} class="flex justify-between items-baseline gap-4">
          <span class="text-base-content/60">Watch directories</span>
          <span class="text-base-content/40 italic">None configured</span>
        </div>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "danger"} = assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface border border-error/20">
      <h2 class="text-lg font-semibold text-error">Danger Zone</h2>
      <p class="text-sm opacity-50 mt-0.5 mb-2">
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

  defp section_content(%{active_section: "acquisition"} = assigns) do
    prowlarr_configured = MediaCentaur.Acquisition.available?()

    assigns =
      assign(assigns,
        prowlarr_configured: prowlarr_configured,
        prowlarr_url: MediaCentaur.Acquisition.Config.url()
      )

    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-4">
      <div>
        <h2 class="text-lg font-semibold">Acquisition</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          Media search and automated download via Prowlarr.
        </p>
      </div>

      <%!-- Not configured --%>
      <div :if={!@prowlarr_configured} class="glass-inset rounded-lg p-4 space-y-3">
        <div class="flex items-center gap-2">
          <span class="size-2 rounded-full bg-base-content/20 shrink-0"></span>
          <span class="text-sm text-base-content/60">Prowlarr not configured</span>
        </div>
        <p class="text-sm text-base-content/50">
          Add your Prowlarr URL and API key to <code class="font-mono text-xs">backend.toml</code>
          to enable media search and automated acquisition.
        </p>
        <div class="text-xs font-mono glass-inset rounded p-3 text-base-content/70">
          [prowlarr]<br /> url = "http://localhost:9696"<br /> api_key = "your-api-key-here"
        </div>
        <p class="text-xs text-base-content/40">
          See <code class="font-mono">docs/acquisition/prowlarr-setup.md</code>
          for full setup instructions.
        </p>
      </div>

      <%!-- Configured --%>
      <div :if={@prowlarr_configured} class="space-y-4">
        <div class="glass-inset rounded-lg p-4 space-y-2">
          <div class="flex items-center gap-2">
            <span class={[
              "size-2 rounded-full shrink-0",
              @prowlarr_test_status == :ok && "bg-success",
              @prowlarr_test_status == :error && "bg-error",
              is_nil(@prowlarr_test_status) && "bg-warning"
            ]}>
            </span>
            <span class="text-sm font-medium">
              {cond do
                @prowlarr_test_status == :ok -> "Connected"
                @prowlarr_test_status == :error -> "Unreachable"
                true -> "Configured — not tested"
              end}
            </span>
          </div>
          <div class="flex items-baseline justify-between gap-4">
            <span class="text-xs text-base-content/50">URL</span>
            <span class="font-mono text-xs text-base-content/70">{@prowlarr_url}</span>
          </div>
        </div>

        <button
          class="btn btn-soft btn-primary btn-sm"
          phx-click="test_prowlarr"
          disabled={@prowlarr_testing}
          data-nav-item
          tabindex="0"
        >
          <span :if={@prowlarr_testing} class="loading loading-spinner loading-xs"></span>
          <.icon :if={!@prowlarr_testing} name="hero-signal-mini" class="size-4" /> Test connection
        </button>
      </div>
    </div>
    """
  end

  defp section_content(assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface">
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
    <div
      class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg transition-colors duration-150 cursor-pointer hover:bg-base-content/[0.04]"
      data-nav-item
      tabindex="0"
      phx-click={@event}
      {phx_values(@event_value)}
    >
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

  defp load_config do
    config = MediaCentaur.Config

    %{
      tmdb_configured: config.get(:tmdb_api_key) not in [nil, ""],
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      watch_dirs: config.get(:watch_dirs) || []
    }
  end

  defp persist_service_flag(service, value) do
    env = Application.get_env(:media_centaur, :environment, :dev)

    Settings.find_or_create_entry!(%{
      key: "services:#{env}:#{service}",
      value: %{"enabled" => value}
    })
  end

  defp load_spoiler_free_setting do
    case Settings.get_by_key("spoiler_free_mode") do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end
end
