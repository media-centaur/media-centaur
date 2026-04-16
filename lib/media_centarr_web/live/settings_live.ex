defmodule MediaCentarrWeb.SettingsLive do
  @moduledoc """
  Settings UI for editing the user's `media-centarr.toml` configuration.

  Renders editable rows for sensitive credentials (TMDB key, Prowlarr API
  key, qBittorrent login), service toggles (watchers, pipelines), and
  service start/stop actions. Persists changes by rewriting the TOML file
  on disk and broadcasting `Settings` updates.
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Admin, Config, Settings}
  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Watcher
  alias MediaCentarr.Pipeline
  alias MediaCentarr.ImagePipeline

  @sections [
    %{id: "services", label: "Services"},
    %{id: "preferences", label: "Preferences"},
    %{id: "tmdb", label: "TMDB"},
    %{id: "acquisition", label: "Acquisition"},
    %{id: "pipeline", label: "Pipeline"},
    %{id: "playback", label: "Playback"},
    %{id: "library", label: "Library"},
    %{id: "release_tracking", label: "Release Tracking"},
    %{id: "system", label: "System"},
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
       prowlarr_testing: false,
       download_client_test_status: nil,
       download_client_testing: false,
       download_client_detect_status: nil,
       download_client_detecting: false,
       detected_download_client: nil
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

    case MediaCentarr.Watcher.Supervisor.scan() do
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

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      Admin.clear_database()
      send(liveview, :database_cleared)
    end)

    {:noreply, assign(socket, clearing_database: true)}
  end

  def handle_event("refresh_image_cache", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
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

    {:noreply, assign(socket, image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?())}
  end

  def handle_event("toggle_spoiler_free", _params, socket) do
    enabled = !socket.assigns.spoiler_free

    Settings.find_or_create_entry!(%{
      key: "spoiler_free_mode",
      value: %{"enabled" => enabled}
    })

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.settings_updates(),
      {:setting_changed, "spoiler_free_mode", enabled}
    )

    {:noreply, assign(socket, spoiler_free: enabled)}
  end

  def handle_event("save_tmdb", params, socket) do
    if params["tmdb_api_key"] != "" do
      Config.update(:tmdb_api_key, params["tmdb_api_key"])
    end

    case Float.parse(params["auto_approve_threshold"] || "") do
      {threshold, _} -> Config.update(:auto_approve_threshold, threshold)
      :error -> :ok
    end

    {:noreply,
     socket
     |> assign(config: load_config())
     |> put_flash(:info, "TMDB settings saved")}
  end

  def handle_event("save_prowlarr", params, socket) do
    if params["prowlarr_url"] != "" do
      Config.update(:prowlarr_url, params["prowlarr_url"])
    end

    if params["prowlarr_api_key"] != "" do
      Config.update(:prowlarr_api_key, params["prowlarr_api_key"])
    end

    Prowlarr.invalidate_client()

    {:noreply,
     socket
     |> assign(config: load_config(), prowlarr_test_status: nil)
     |> put_flash(:info, "Acquisition settings saved")}
  end

  def handle_event("save_download_client", params, socket) do
    if params["download_client_type"] not in [nil, ""] do
      Config.update(:download_client_type, params["download_client_type"])
    end

    if params["download_client_url"] not in [nil, ""] do
      Config.update(:download_client_url, params["download_client_url"])
    end

    Config.update(:download_client_username, params["download_client_username"] || "")

    if params["download_client_password"] not in [nil, ""] do
      Config.update(:download_client_password, params["download_client_password"])
    end

    QBittorrent.invalidate_client()

    {:noreply,
     socket
     |> assign(
       config: load_config(),
       download_client_test_status: nil,
       download_client_detect_status: nil,
       detected_download_client: nil
     )
     |> put_flash(:info, "Download client settings saved")}
  end

  def handle_event("test_download_client", _params, socket) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      status =
        case Acquisition.test_download_client() do
          :ok -> :ok
          {:error, _} -> :error
        end

      send(parent, {:download_client_test_result, status})
    end)

    {:noreply, assign(socket, download_client_testing: true, download_client_test_status: nil)}
  end

  def handle_event("detect_download_client", _params, socket) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      result = Acquisition.discover_download_clients()
      send(parent, {:download_client_detect_result, result})
    end)

    {:noreply, assign(socket, download_client_detecting: true, download_client_detect_status: nil)}
  end

  def handle_event("save_pipeline", params, socket) do
    extras =
      (params["extras_dirs"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    skip =
      (params["skip_dirs"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Config.update(:extras_dirs, extras)
    Config.update(:skip_dirs, skip)

    {:noreply,
     socket
     |> assign(config: load_config())
     |> put_flash(:info, "Pipeline settings saved")}
  end

  def handle_event("save_playback", params, socket) do
    if params["mpv_path"] != "" do
      Config.update(:mpv_path, params["mpv_path"])
    end

    if params["mpv_socket_dir"] != "" do
      Config.update(:mpv_socket_dir, params["mpv_socket_dir"])
    end

    case Integer.parse(params["mpv_socket_timeout_ms"] || "") do
      {ms, _} -> Config.update(:mpv_socket_timeout_ms, ms)
      :error -> :ok
    end

    {:noreply,
     socket
     |> assign(config: load_config())
     |> put_flash(:info, "Playback settings saved")}
  end

  def handle_event("save_library", params, socket) do
    case Integer.parse(params["file_absence_ttl_days"] || "") do
      {days, _} -> Config.update(:file_absence_ttl_days, days)
      :error -> :ok
    end

    case Integer.parse(params["recent_changes_days"] || "") do
      {days, _} -> Config.update(:recent_changes_days, days)
      :error -> :ok
    end

    {:noreply,
     socket
     |> assign(config: load_config())
     |> put_flash(:info, "Library settings saved")}
  end

  def handle_event("save_release_tracking", params, socket) do
    case Integer.parse(params["refresh_interval_hours"] || "") do
      {hours, _} -> Config.update(:release_tracking_refresh_interval_hours, hours)
      :error -> :ok
    end

    {:noreply,
     socket
     |> assign(config: load_config())
     |> put_flash(:info, "Release tracking settings saved")}
  end

  @impl true
  def handle_event("test_prowlarr", _params, socket) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      status =
        case MediaCentarr.Acquisition.search("test", []) do
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

  def handle_info({:download_client_test_result, status}, socket) do
    {:noreply, assign(socket, download_client_testing: false, download_client_test_status: status)}
  end

  def handle_info({:download_client_detect_result, {:ok, [first | _rest] = clients}}, socket) do
    # Stash detected values as a suggestion — do NOT persist. The URL
    # Prowlarr returns is correct from Prowlarr's perspective but is
    # often a Docker service name unreachable from this host. The user
    # reviews the form and clicks Save to commit. See ADR-037.
    detected = %{
      type: first.type,
      url: first.url,
      username: first.username
    }

    extra =
      if length(clients) > 1,
        do: " (#{length(clients)} found, used the first)",
        else: ""

    {:noreply,
     socket
     |> assign(
       detected_download_client: detected,
       download_client_detecting: false,
       download_client_detect_status: :ok
     )
     |> put_flash(
       :info,
       "Pre-filled from Prowlarr#{extra} — review URL, enter password, then Save"
     )}
  end

  def handle_info({:download_client_detect_result, {:ok, []}}, socket) do
    {:noreply,
     socket
     |> assign(download_client_detecting: false, download_client_detect_status: :empty)
     |> put_flash(:error, "Prowlarr has no download clients configured")}
  end

  def handle_info({:download_client_detect_result, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(download_client_detecting: false, download_client_detect_status: :error)
     |> put_flash(:error, "Couldn't reach Prowlarr to discover download clients")}
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
            prowlarr_test_status={@prowlarr_test_status}
            prowlarr_testing={@prowlarr_testing}
            download_client_test_status={@download_client_test_status}
            download_client_testing={@download_client_testing}
            download_client_detect_status={@download_client_detect_status}
            download_client_detecting={@download_client_detecting}
            detected_download_client={@detected_download_client}
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

  defp section_content(%{active_section: "tmdb"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-5">
      <div>
        <h2 class="text-lg font-semibold">TMDB</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          The Movie Database API — required for metadata scraping and artwork.
        </p>
      </div>

      <form phx-submit="save_tmdb" class="space-y-4">
        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              API Key
              <span
                :if={@config[:tmdb_api_key_configured?]}
                class="ml-2 text-success normal-case font-normal"
              >
                ✓ configured
              </span>
              <span
                :if={!@config[:tmdb_api_key_configured?]}
                class="ml-2 text-warning normal-case font-normal"
              >
                not set
              </span>
            </label>
            <input
              type="password"
              name="tmdb_api_key"
              class="input input-bordered w-full font-mono text-sm"
              placeholder={
                if @config[:tmdb_api_key_configured?],
                  do: "Leave blank to keep current key",
                  else: "Enter your TMDB API key"
              }
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Auto-approve threshold
            </label>
            <input
              type="number"
              name="auto_approve_threshold"
              step="0.01"
              min="0"
              max="1"
              value={@config[:auto_approve_threshold]}
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Confidence score (0.0–1.0) above which matches are approved automatically.
            </p>
          </div>
        </div>

        <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
          Save
        </button>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "acquisition"} = assigns) do
    prowlarr_configured = Acquisition.available?()
    download_client_configured = Acquisition.download_client_available?()

    # Form values prefer a pending `detected_download_client` (pre-filled
    # by "Detect from Prowlarr", not yet saved) over the persisted config.
    # See ADR-037 — the user must review and click Save to commit.
    detected = assigns[:detected_download_client] || %{}
    config = assigns.config

    download_client_display = %{
      type: detected[:type] || config[:download_client_type],
      url: detected[:url] || config[:download_client_url],
      username: detected[:username] || config[:download_client_username]
    }

    assigns =
      assign(assigns,
        prowlarr_configured: prowlarr_configured,
        download_client_configured: download_client_configured,
        download_client_display: download_client_display
      )

    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-5">
      <div>
        <h2 class="text-lg font-semibold">Acquisition</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          Media search and automated download via Prowlarr.
        </p>
      </div>

      <form phx-submit="save_prowlarr" class="space-y-4">
        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Prowlarr URL
            </label>
            <input
              type="text"
              name="prowlarr_url"
              value={@config[:prowlarr_url]}
              class="input input-bordered w-full font-mono text-sm"
              placeholder="http://localhost:9696"
              data-nav-item
              tabindex="0"
            />
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              API Key
              <span
                :if={@config[:prowlarr_api_key_configured?]}
                class="ml-2 text-success normal-case font-normal"
              >
                ✓ configured
              </span>
            </label>
            <input
              type="password"
              name="prowlarr_api_key"
              class="input input-bordered w-full font-mono text-sm"
              placeholder={
                if @config[:prowlarr_api_key_configured?],
                  do: "Leave blank to keep current key",
                  else: "Enter your Prowlarr API key"
              }
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
          </div>
        </div>

        <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
          Save
        </button>
      </form>

      <div :if={@prowlarr_configured} class="pt-3 border-t border-base-content/10 space-y-3">
        <div class="glass-inset rounded-lg p-3 flex items-center gap-2">
          <span class={[
            "size-2 rounded-full shrink-0",
            @prowlarr_test_status == :ok && "bg-success",
            @prowlarr_test_status == :error && "bg-error",
            is_nil(@prowlarr_test_status) && "bg-warning"
          ]}>
          </span>
          <span class="text-sm">
            {cond do
              @prowlarr_test_status == :ok -> "Connected"
              @prowlarr_test_status == :error -> "Unreachable"
              true -> "Configured — not tested"
            end}
          </span>
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

      <div class="pt-3 border-t border-base-content/10 space-y-3">
        <div>
          <h3 class="text-sm font-semibold">Download Client</h3>
          <p class="text-xs text-base-content/50 mt-0.5">
            Where Prowlarr forwards grabs. Used to read active and completed
            download progress on the Download page.
          </p>
        </div>

        <form phx-submit="save_download_client" class="space-y-4">
          <div class="space-y-3">
            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Type
              </label>
              <select
                name="download_client_type"
                class="select select-bordered w-full font-mono text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="" selected={@download_client_display.type in [nil, ""]}>
                  Not configured
                </option>
                <option
                  value="qbittorrent"
                  selected={@download_client_display.type == "qbittorrent"}
                >
                  qBittorrent
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                URL
              </label>
              <input
                type="text"
                name="download_client_url"
                value={@download_client_display.url}
                class="input input-bordered w-full font-mono text-sm"
                placeholder="http://localhost:8080"
                data-nav-item
                tabindex="0"
              />
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Username
              </label>
              <input
                type="text"
                name="download_client_username"
                value={@download_client_display.username}
                class="input input-bordered w-full font-mono text-sm"
                placeholder="admin"
                autocomplete="off"
                data-nav-item
                tabindex="0"
              />
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Password
                <span
                  :if={@config[:download_client_password_configured?]}
                  class="ml-2 text-success normal-case font-normal"
                >
                  ✓ configured
                </span>
              </label>
              <input
                type="password"
                name="download_client_password"
                class="input input-bordered w-full font-mono text-sm"
                placeholder={
                  if @config[:download_client_password_configured?],
                    do: "Leave blank to keep current password",
                    else: "Enter download client password"
                }
                autocomplete="off"
                data-nav-item
                tabindex="0"
              />
            </div>
          </div>

          <div class="flex flex-wrap gap-2">
            <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
              Save
            </button>

            <button
              type="button"
              class="btn btn-soft btn-sm"
              phx-click="detect_download_client"
              disabled={@download_client_detecting || !@prowlarr_configured}
              data-nav-item
              tabindex="0"
            >
              <span :if={@download_client_detecting} class="loading loading-spinner loading-xs">
              </span>
              <.icon
                :if={!@download_client_detecting}
                name="hero-magnifying-glass-mini"
                class="size-4"
              /> Detect from Prowlarr
            </button>
          </div>
        </form>

        <div :if={@download_client_configured} class="space-y-3">
          <div class="glass-inset rounded-lg p-3 flex items-center gap-2">
            <span class={[
              "size-2 rounded-full shrink-0",
              @download_client_test_status == :ok && "bg-success",
              @download_client_test_status == :error && "bg-error",
              is_nil(@download_client_test_status) && "bg-warning"
            ]}>
            </span>
            <span class="text-sm">
              {cond do
                @download_client_test_status == :ok -> "Connected"
                @download_client_test_status == :error -> "Unreachable / auth failed"
                true -> "Configured — not tested"
              end}
            </span>
          </div>

          <button
            class="btn btn-soft btn-primary btn-sm"
            phx-click="test_download_client"
            disabled={@download_client_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@download_client_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@download_client_testing} name="hero-signal-mini" class="size-4" />
            Test connection
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "pipeline"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-5">
      <div>
        <h2 class="text-lg font-semibold">Pipeline</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          Controls how files are classified during ingestion.
        </p>
      </div>

      <form phx-submit="save_pipeline" class="space-y-4">
        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Extras directories
            </label>
            <input
              type="text"
              name="extras_dirs"
              value={Enum.join(@config[:extras_dirs] || [], ", ")}
              class="input input-bordered w-full text-sm"
              placeholder="Extras, Featurettes, Special Features"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Comma-separated directory names treated as bonus content.
            </p>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Skip directories
            </label>
            <input
              type="text"
              name="skip_dirs"
              value={Enum.join(@config[:skip_dirs] || [], ", ")}
              class="input input-bordered w-full text-sm"
              placeholder="Sample"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Comma-separated directory names to ignore silently.
            </p>
          </div>
        </div>

        <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
          Save
        </button>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "playback"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-5">
      <div>
        <h2 class="text-lg font-semibold">Playback</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          MPV player configuration.
        </p>
      </div>

      <form phx-submit="save_playback" class="space-y-4">
        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              MPV path
            </label>
            <input
              type="text"
              name="mpv_path"
              value={@config[:mpv_path]}
              class="input input-bordered w-full font-mono text-sm"
              placeholder="/usr/bin/mpv"
              data-nav-item
              tabindex="0"
            />
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              IPC socket directory
            </label>
            <input
              type="text"
              name="mpv_socket_dir"
              value={@config[:mpv_socket_dir]}
              class="input input-bordered w-full font-mono text-sm"
              placeholder="/tmp"
              data-nav-item
              tabindex="0"
            />
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Socket timeout (ms)
            </label>
            <input
              type="number"
              name="mpv_socket_timeout_ms"
              value={@config[:mpv_socket_timeout_ms]}
              min="100"
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
          </div>
        </div>

        <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
          Save
        </button>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "library"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-5">
      <div>
        <h2 class="text-lg font-semibold">Library</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          Library cleanup and status display settings.
        </p>
      </div>

      <form phx-submit="save_library" class="space-y-4">
        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              File absence TTL (days)
            </label>
            <input
              type="number"
              name="file_absence_ttl_days"
              value={@config[:file_absence_ttl_days]}
              min="1"
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Days before an absent file is removed from the library.
            </p>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Recent changes window (days)
            </label>
            <input
              type="number"
              name="recent_changes_days"
              value={@config[:recent_changes_days]}
              min="1"
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              How many days back to show on the Status page's recent changes list.
            </p>
          </div>
        </div>

        <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
          Save
        </button>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "release_tracking"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-5">
      <div>
        <h2 class="text-lg font-semibold">Release Tracking</h2>
        <p class="text-sm text-base-content/50 mt-0.5">
          How often to poll TMDB for upcoming release dates.
        </p>
      </div>

      <form phx-submit="save_release_tracking" class="space-y-4">
        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Refresh interval (hours)
          </label>
          <input
            type="number"
            name="refresh_interval_hours"
            value={@config[:release_tracking_refresh_interval_hours]}
            min="1"
            class="input input-bordered w-full font-mono text-sm"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            Changes take effect after the current refresh cycle completes.
          </p>
        </div>

        <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
          Save
        </button>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "system"} = assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface">
      <h2 class="text-lg font-semibold">System</h2>
      <p class="text-sm opacity-50 mt-0.5 mb-4">
        Structural settings that require editing
        <code class="font-mono text-xs">media-centarr.toml</code>
        and restarting.
      </p>

      <div :if={@config == %{}} class="text-base-content/60 py-4">Loading...</div>

      <div :if={@config != %{}} class="space-y-3 text-sm">
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
    # String keys avoid creating atoms at runtime — Phoenix accepts both.
    Map.new(map, fn {key, value} -> {"phx-value-#{key}", value} end)
  end

  defp load_config do
    cfg = Config

    %{
      # Sensitive values are NOT placed in LV assigns — only their
      # presence flags. The templates use *_configured? to decide whether
      # to show the "✓ configured" badge and the placeholder text.
      tmdb_api_key_configured?: MediaCentarr.Secret.present?(cfg.get(:tmdb_api_key)),
      auto_approve_threshold: cfg.get(:auto_approve_threshold),
      prowlarr_url: cfg.get(:prowlarr_url),
      prowlarr_api_key_configured?: MediaCentarr.Secret.present?(cfg.get(:prowlarr_api_key)),
      download_client_type: cfg.get(:download_client_type),
      download_client_url: cfg.get(:download_client_url),
      download_client_username: cfg.get(:download_client_username),
      download_client_password_configured?:
        MediaCentarr.Secret.present?(cfg.get(:download_client_password)),
      mpv_path: cfg.get(:mpv_path),
      mpv_socket_dir: cfg.get(:mpv_socket_dir),
      mpv_socket_timeout_ms: cfg.get(:mpv_socket_timeout_ms),
      file_absence_ttl_days: cfg.get(:file_absence_ttl_days),
      recent_changes_days: cfg.get(:recent_changes_days),
      release_tracking_refresh_interval_hours: cfg.get(:release_tracking_refresh_interval_hours),
      extras_dirs: cfg.get(:extras_dirs) || [],
      skip_dirs: cfg.get(:skip_dirs) || [],
      database_path: cfg.get(:database_path),
      watch_dirs: cfg.get(:watch_dirs) || []
    }
  end

  defp persist_service_flag(service, value) do
    env = Application.get_env(:media_centarr, :environment, :dev)

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
