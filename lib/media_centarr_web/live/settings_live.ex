defmodule MediaCentarrWeb.SettingsLive do
  @moduledoc """
  Settings UI for editing the user's `media-centarr.toml` configuration.

  Renders editable rows for sensitive credentials (TMDB key, Prowlarr API
  key, qBittorrent login), service toggles (watchers, pipelines), and
  service start/stop actions. Persists changes by rewriting the TOML file
  on disk and broadcasting `Settings` updates.
  """
  use MediaCentarrWeb, :live_view

  alias MediaCentarr.{Capabilities, Config, SelfUpdate, Settings, Version}
  alias MediaCentarr.SelfUpdate.UpdateChecker

  alias MediaCentarrWeb.Live.SettingsLive.{
    ConnectionTest,
    Overview,
    PathCheck,
    ReleaseNotes,
    SystemSection
  }

  alias MediaCentarr.Maintenance
  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.Prowlarr
  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Watcher
  alias MediaCentarr.Pipeline
  alias MediaCentarr.Pipeline.Image, as: ImagePipeline
  alias MediaCentarrWeb.SettingsLive.WatchDirsLogic
  alias MediaCentarr.Controls
  alias MediaCentarrWeb.SettingsLive.Controls, as: ControlsSection

  # Sections are grouped for sidebar display — a thin divider renders between
  # adjacent items whose :group differs. Order within a group is by frequency
  # of user interaction: things you touch daily come first.
  @sections [
    # System is its own group so it sits alone above everything else.
    %{id: "system", label: "System", group: :system},
    # General — start-of-session setup
    %{id: "services", label: "Services", group: :general},
    %{id: "preferences", label: "Preferences", group: :general},
    %{id: "controls", label: "Controls", group: :general},
    # Media workflow — the arr stack
    %{id: "library", label: "Library", group: :media},
    %{id: "tmdb", label: "TMDB", group: :media},
    %{id: "acquisition", label: "Acquisition", group: :media},
    %{id: "pipeline", label: "Pipeline", group: :media},
    %{id: "playback", label: "Playback", group: :media},
    %{id: "release_tracking", label: "Release Tracking", group: :media},
    # Infrastructure — rare-touch admin
    %{id: "danger", label: "Danger Zone", group: :infra}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Settings.subscribe()
        Watcher.Supervisor.subscribe()
        SelfUpdate.subscribe()
        SelfUpdate.subscribe_progress()
        Config.subscribe()
        Controls.subscribe()

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
       watch_dirs: MediaCentarr.Config.watch_dirs_entries(),
       exclude_dirs: MediaCentarr.Config.get(:exclude_dirs) || [],
       exclude_dir_input: "",
       exclude_dir_error: nil,
       watch_dir_dialog: nil,
       watch_dir_delete_confirm: nil,
       scanning: false,
       scan_task: nil,
       clearing_database: false,
       refreshing_images: false,
       repairing_images: false,
       repair_last_result: nil,
       missing_images_summary: Maintenance.missing_images_summary(),
       spoiler_free: spoiler_free,
       tmdb_test: load_test_result(:tmdb),
       tmdb_testing: false,
       prowlarr_test: load_test_result(:prowlarr),
       prowlarr_testing: false,
       download_client_test: load_test_result(:download_client),
       download_client_testing: false,
       download_client_detect_status: nil,
       download_client_detecting: false,
       detected_download_client: nil,
       app_version: Version.current_version(),
       build_info: Version.build_info(),
       update_status: :idle,
       latest_release: nil,
       apply_phase: nil,
       apply_progress: nil,
       apply_error: nil,
       apply_failed_at: nil,
       tmdb_missing: SystemSection.tmdb_key_missing?(Config.get(:tmdb_api_key)),
       service_state: SelfUpdate.service_state(),
       service_action_confirm: nil,
       service_action_pending: nil,
       service_status_visible: false,
       service_status_output: nil,
       bindings: Controls.get(),
       glyph_style: Controls.glyph_style(),
       listening: nil
     )}
  end

  @impl true
  def handle_params(%{"add_watch_dir" => "1"} = params, _uri, socket) do
    section = params["section"] || "library"

    socket =
      socket
      |> assign(active_section: section)
      |> maybe_auto_check_updates(section)
      |> open_watch_dir_dialog(WatchDirsLogic.new_entry())

    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    section =
      case params["section"] do
        nil -> "system"
        # Legacy redirect — older bookmarks pointed at ?section=overview.
        "overview" -> "system"
        other -> other
      end

    socket =
      socket
      |> assign(active_section: section)
      |> maybe_auto_check_updates(section)

    {:noreply, socket}
  end

  defp maybe_auto_check_updates(socket, "system") do
    if connected?(socket) do
      case UpdateChecker.cached_latest_release() do
        {:fresh, {:ok, release}} ->
          status = UpdateChecker.compare(release, socket.assigns.app_version)
          assign(socket, update_status: status, latest_release: release)

        {:fresh, {:error, reason}} ->
          # Preserve any hydrated `latest_release` so the card can keep
          # showing the last-known release alongside the error status.
          assign(socket, update_status: {:error, reason})

        :stale ->
          start_update_check(socket)
      end
    else
      socket
    end
  end

  defp maybe_auto_check_updates(socket, _section), do: socket

  defp start_update_check(socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      # Dual-write via SelfUpdate so Settings.Entry stays in sync with
      # the in-memory cache. Without this, a manual check would refresh
      # only the 5-min hot-path cache; on next boot the stale persisted
      # row would hydrate back and the UI would regress to the old value.
      result = UpdateChecker.latest_release()
      _ = SelfUpdate.record_check_result(result)
      send(liveview, {:update_check_result, result})
    end)

    # Keep `latest_release` (hydrated from Storage or a previous fetch)
    # visible while the new check runs — no "blanking" flash.
    assign(socket, update_status: :checking)
  end

  # --- Events ---

  @impl true
  def handle_event("check_updates", _params, socket) do
    {:noreply, start_update_check(socket)}
  end

  def handle_event("apply_update", _params, socket) do
    case SelfUpdate.apply_pending() do
      :ok ->
        {:noreply,
         assign(socket,
           apply_phase: :preparing,
           apply_progress: nil,
           apply_error: nil,
           apply_failed_at: nil
         )}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :info, "An update is already in progress.")}

      {:error, :no_update_pending} ->
        {:noreply, put_flash(socket, :error, "No update is pending right now.")}

      {:error, :invalid_tag} ->
        {:noreply, put_flash(socket, :error, "The release tag failed safety validation.")}
    end
  end

  def handle_event("cancel_update", _params, socket) do
    case SelfUpdate.cancel_apply() do
      :ok ->
        {:noreply, socket}

      {:error, :not_running} ->
        {:noreply,
         assign(socket, apply_phase: nil, apply_progress: nil, apply_error: nil, apply_failed_at: nil)}

      {:error, :past_point_of_no_return} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Too late to cancel — the update is finalising. The service will restart shortly."
         )}
    end
  end

  # --- Service controls ---

  def handle_event("service_confirm", %{"action" => action}, socket)
      when action in ["restart", "stop"] do
    {:noreply, assign(socket, service_action_confirm: action)}
  end

  def handle_event("service_cancel", _params, socket) do
    {:noreply, assign(socket, service_action_confirm: nil)}
  end

  def handle_event("service_execute", %{"action" => "restart"}, socket) do
    case SelfUpdate.service_restart() do
      :ok ->
        {:noreply,
         socket
         |> assign(service_action_confirm: nil, service_action_pending: :restarting)
         |> put_flash(
           :info,
           "Restarting the service. The page will reconnect automatically when it's back."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(service_action_confirm: nil)
         |> put_flash(:error, "Restart failed: #{inspect(reason)}")}
    end
  end

  def handle_event("service_execute", %{"action" => "stop"}, socket) do
    case SelfUpdate.service_stop() do
      :ok ->
        {:noreply,
         socket
         |> assign(service_action_confirm: nil, service_action_pending: :stopping)
         |> put_flash(
           :info,
           "Stopping the service. You'll need to start it manually to bring it back."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(service_action_confirm: nil)
         |> put_flash(:error, "Stop failed: #{inspect(reason)}")}
    end
  end

  def handle_event("service_toggle_status", _params, socket) do
    visible = not socket.assigns.service_status_visible

    output =
      if visible and is_nil(socket.assigns.service_status_output) do
        case SelfUpdate.service_status_output() do
          {:ok, text} -> text
          {:error, reason} -> "Failed to read systemctl status: #{inspect(reason)}"
        end
      else
        socket.assigns.service_status_output
      end

    {:noreply, assign(socket, service_status_visible: visible, service_status_output: output)}
  end

  def handle_event("dismiss_apply_modal", _params, socket) do
    {:noreply,
     assign(socket,
       apply_phase: nil,
       apply_progress: nil,
       apply_error: nil,
       apply_failed_at: nil
     )}
  end

  # --- Watch-dir card events ---

  def handle_event("watch_dir:open_add", _, socket) do
    {:noreply, open_watch_dir_dialog(socket, WatchDirsLogic.new_entry())}
  end

  def handle_event("watch_dir:open_edit", %{"id" => id}, socket) do
    entry = Enum.find(socket.assigns.watch_dirs, &(&1["id"] == id)) || WatchDirsLogic.new_entry()
    {:noreply, open_watch_dir_dialog(socket, entry)}
  end

  def handle_event("watch_dir:close", _, socket) do
    {:noreply, close_watch_dir_dialog(socket)}
  end

  def handle_event("watch_dir:validate", %{"entry" => params}, socket) do
    {:noreply, schedule_watch_dir_validation(socket, params)}
  end

  def handle_event("watch_dir:save", _, socket) do
    %{entry: entry, validation: validation} = socket.assigns.watch_dir_dialog

    if WatchDirsLogic.saveable?(validation) do
      entries = WatchDirsLogic.upsert(socket.assigns.watch_dirs, entry)
      :ok = MediaCentarr.Config.put_watch_dirs(entries)
      {:noreply, close_watch_dir_dialog(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("watch_dir:delete_confirm", %{"id" => id}, socket) do
    {:noreply, assign(socket, :watch_dir_delete_confirm, id)}
  end

  def handle_event("watch_dir:delete_cancel", _, socket) do
    {:noreply, assign(socket, :watch_dir_delete_confirm, nil)}
  end

  def handle_event("watch_dir:delete", %{"id" => id}, socket) do
    entries = WatchDirsLogic.remove(socket.assigns.watch_dirs, id)
    :ok = MediaCentarr.Config.put_watch_dirs(entries)
    {:noreply, assign(socket, :watch_dir_delete_confirm, nil)}
  end

  # --- Exclude-dir card events ---

  def handle_event("exclude_dir:validate", %{"path" => path}, socket) do
    error = validate_exclude_dir_error(path, socket.assigns.exclude_dirs)

    socket =
      socket
      |> assign(:exclude_dir_input, path)
      |> assign(:exclude_dir_error, error)

    {:noreply, socket}
  end

  def handle_event("exclude_dir:add", %{"path" => path}, socket) do
    case validate_exclude_dir(path, socket.assigns.exclude_dirs) do
      {:ok, trimmed} ->
        new_list = [trimmed | socket.assigns.exclude_dirs]
        :ok = MediaCentarr.Config.update(:exclude_dirs, new_list)

        socket =
          socket
          |> assign(:exclude_dirs, new_list)
          |> assign(:exclude_dir_input, "")
          |> assign(:exclude_dir_error, nil)

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("exclude_dir:delete", %{"path" => path}, socket) do
    new_list = Enum.reject(socket.assigns.exclude_dirs, &(&1 == path))
    :ok = MediaCentarr.Config.update(:exclude_dirs, new_list)
    {:noreply, assign(socket, :exclude_dirs, new_list)}
  end

  def handle_event("scan", _params, socket) do
    # Spawn the scan on a supervised Task so the LiveView stays responsive
    # and we can surface a Cancel button backed by Task.shutdown/2. A
    # synchronous call here would block the socket process — no render
    # could fire during the scan, so the "Scanning…" label would never
    # become visible.
    task =
      Task.Supervisor.async_nolink(MediaCentarr.TaskSupervisor, fn ->
        MediaCentarr.Watcher.Supervisor.scan()
      end)

    {:noreply, assign(socket, scanning: true, scan_task: task)}
  end

  def handle_event("cancel_scan", _params, socket) do
    case socket.assigns[:scan_task] do
      %Task{} = task ->
        _ = Task.shutdown(task, :brutal_kill)

        {:noreply,
         socket
         |> assign(scanning: false, scan_task: nil)
         |> put_flash(:info, "Scan cancelled.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_database", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      Maintenance.clear_database()
      send(liveview, :database_cleared)
    end)

    {:noreply, assign(socket, clearing_database: true)}
  end

  def handle_event("refresh_image_cache", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      {:ok, count} = Maintenance.refresh_image_cache()
      send(liveview, {:image_cache_refreshed, count})
    end)

    {:noreply, assign(socket, refreshing_images: true)}
  end

  def handle_event("repair_missing_images", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      {:ok, result} = Maintenance.repair_missing_images()
      send(liveview, {:image_repair_complete, result})
    end)

    {:noreply, assign(socket, repairing_images: true)}
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

  # Save + Test share one form-submit handler per service. The Save and
  # Test buttons are both `type=submit` on the same form with
  # `name=_action value=save|test`. This means: every test starts by
  # persisting whatever the user typed in. If the test then fails, the
  # form re-renders against `@config` — which now matches the typed-in
  # values, so the user sees their input preserved instead of clobbered.
  # See `test/media_centarr_web/live/settings_live_acquisition_test.exs`.

  def handle_event("save_tmdb", params, socket) do
    if params["tmdb_api_key"] != "" do
      Config.update(:tmdb_api_key, params["tmdb_api_key"])
      MediaCentarr.TMDB.Client.invalidate_client()
      clear_test_result(:tmdb)
    end

    case Float.parse(params["auto_approve_threshold"] || "") do
      {threshold, _} -> Config.update(:auto_approve_threshold, threshold)
      :error -> :ok
    end

    socket = assign(socket, config: load_config(), tmdb_test: load_test_result(:tmdb))

    case params["_action"] do
      "test" ->
        spawn_test_task(:tmdb_test_result, fn ->
          case MediaCentarr.TMDB.Client.configuration() do
            {:ok, _} -> :ok
            {:error, _} -> :error
          end
        end)

        {:noreply, assign(socket, tmdb_testing: true)}

      _ ->
        {:noreply, put_flash(socket, :info, "TMDB settings saved")}
    end
  end

  def handle_event("save_prowlarr", params, socket) do
    if params["prowlarr_url"] != "" do
      Config.update(:prowlarr_url, params["prowlarr_url"])
    end

    if params["prowlarr_api_key"] != "" do
      Config.update(:prowlarr_api_key, params["prowlarr_api_key"])
    end

    Prowlarr.invalidate_client()
    clear_test_result(:prowlarr)

    socket = assign(socket, config: load_config(), prowlarr_test: nil)

    case params["_action"] do
      "test" ->
        spawn_test_task(:prowlarr_test_result, fn ->
          case MediaCentarr.Acquisition.test_prowlarr() do
            :ok -> :ok
            {:error, _} -> :error
          end
        end)

        {:noreply, assign(socket, prowlarr_testing: true)}

      _ ->
        {:noreply, put_flash(socket, :info, "Acquisition settings saved")}
    end
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
    clear_test_result(:download_client)

    socket =
      assign(socket,
        config: load_config(),
        download_client_test: nil,
        download_client_detect_status: nil,
        detected_download_client: nil
      )

    case params["_action"] do
      "test" ->
        spawn_test_task(:download_client_test_result, fn ->
          case Acquisition.test_download_client() do
            :ok -> :ok
            {:error, _} -> :error
          end
        end)

        {:noreply, assign(socket, download_client_testing: true)}

      _ ->
        {:noreply, put_flash(socket, :info, "Download client settings saved")}
    end
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

  def handle_event("save_data_dir", %{"data_dir" => raw}, socket) do
    value = raw |> to_string() |> String.trim() |> Path.expand()

    Config.update(:data_dir, value)

    {:noreply,
     socket
     |> assign(config: load_config())
     |> put_flash(:info, "Data directory saved")}
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

  def handle_event("save_auto_grab_defaults", %{"auto_grab" => params}, socket) do
    # Server-side gate double-check — UI hides the form, but a stale page
    # could still POST after the user revoked Prowlarr config.
    if MediaCentarr.Capabilities.prowlarr_ready?() do
      persist_auto_grab_defaults(params)
      {:noreply, put_flash(socket, :info, "Auto-acquisition defaults saved")}
    else
      {:noreply, put_flash(socket, :error, "Prowlarr is not ready — connect it first")}
    end
  end

  # --- Controls events ---

  def handle_event("controls:listen", %{"id" => id, "kind" => kind}, socket) do
    {:noreply,
     socket
     |> assign(listening: {String.to_existing_atom(kind), String.to_existing_atom(id)})
     |> push_event("controls:listen", %{kind: kind})}
  end

  def handle_event("controls:cancel", _params, socket) do
    {:noreply, assign(socket, listening: nil)}
  end

  def handle_event("controls:bind", %{"id" => id, "kind" => kind, "value" => value}, socket) do
    id_atom = String.to_existing_atom(id)
    kind_atom = String.to_existing_atom(kind)
    normalized = normalize_bind_value(kind_atom, value)

    case Controls.put(id_atom, kind_atom, normalized) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to bind key")}
    end
  end

  def handle_event("controls:clear", %{"id" => id, "kind" => kind}, socket) do
    :ok = Controls.clear(String.to_existing_atom(id), String.to_existing_atom(kind))
    {:noreply, socket}
  end

  def handle_event("controls:reset_all", _params, socket) do
    :ok = Controls.reset_all()
    {:noreply, socket}
  end

  def handle_event("controls:reset_category", %{"category" => category}, socket) do
    :ok = Controls.reset_category(String.to_existing_atom(category))
    {:noreply, socket}
  end

  def handle_event("controls:set_glyph", %{"style" => style}, socket) do
    :ok = Controls.set_glyph_style(style)
    {:noreply, socket}
  end

  # --- Info handlers ---

  @impl true
  def handle_info(:database_cleared, socket) do
    {:noreply,
     socket
     |> assign(clearing_database: false)
     |> put_flash(:info, "Database cleared successfully")}
  end

  # async_nolink delivers the scan result here as {ref, result} when the
  # Task succeeds. We match on the stored task's ref to avoid confusing it
  # with any other Task.async_nolink result flowing through this socket.
  def handle_info({ref, {:ok, count}}, %{assigns: %{scan_task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])

    message =
      case count do
        0 -> "Scan complete — no new files found"
        1 -> "Scan complete — 1 new file detected"
        n -> "Scan complete — #{n} new files detected"
      end

    {:noreply,
     socket
     |> assign(scanning: false, scan_task: nil)
     |> put_flash(:info, message)}
  end

  # Task exited normally after we already reaped its result above, or
  # exited from Task.shutdown in cancel_scan. Either way nothing to do.
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{scan_task: %Task{ref: ref}}} = socket
      ) do
    {:noreply, assign(socket, scan_task: nil)}
  end

  def handle_info({:image_cache_refreshed, count}, socket) do
    {:noreply,
     socket
     |> assign(refreshing_images: false)
     |> put_flash(
       :info,
       "Image cache cleared — #{count} #{if count == 1, do: "entity", else: "entities"} queued for re-download. New artwork will appear as the pipeline catches up."
     )}
  end

  def handle_info({:image_repair_complete, result}, socket) do
    %{enqueued: enqueued, queue_reused: reused, queue_rebuilt: rebuilt, skipped: skipped} =
      result

    msg =
      cond do
        enqueued == 0 and skipped == 0 ->
          "No missing images — nothing to repair."

        enqueued == 0 ->
          "No images could be repaired (#{skipped} skipped)."

        true ->
          "Queued #{enqueued} image#{if enqueued == 1, do: "", else: "s"} for re-download " <>
            "(#{reused} reused, #{rebuilt} rebuilt via TMDB" <>
            if(skipped > 0, do: ", #{skipped} skipped", else: "") <> ")."
      end

    {:noreply,
     socket
     |> assign(
       repairing_images: false,
       repair_last_result: result,
       missing_images_summary: Maintenance.missing_images_summary()
     )
     |> put_flash(:info, msg)}
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
    info = save_test_result(:prowlarr, status)
    {:noreply, assign(socket, prowlarr_testing: false, prowlarr_test: info)}
  end

  def handle_info({:tmdb_test_result, status}, socket) do
    info = save_test_result(:tmdb, status)
    {:noreply, assign(socket, tmdb_testing: false, tmdb_test: info)}
  end

  def handle_info({:download_client_test_result, status}, socket) do
    info = save_test_result(:download_client, status)
    {:noreply, assign(socket, download_client_testing: false, download_client_test: info)}
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

  def handle_info({:update_check_result, {:ok, release}}, socket) do
    status = UpdateChecker.compare(release, socket.assigns.app_version)
    {:noreply, assign(socket, update_status: status, latest_release: release)}
  end

  def handle_info({:update_check_result, {:error, reason}}, socket) do
    # Don't nil out latest_release — keep the last-known release
    # visible on the card so the user sees meaningful info during a
    # transient outage (rate limit, network blip, etc.). The error
    # surfaces via update_status; the card's rendering handles the
    # "have release + error status" state gracefully.
    {:noreply, assign(socket, update_status: {:error, reason})}
  end

  def handle_info({:progress, :done, pct}, socket) do
    # A normal restart cycle — BEAM dies, systemd starts the new release,
    # LiveView reconnects — completes in 2-3 seconds. If the BEAM hasn't
    # died within 6s, the handoff didn't actually trigger a restart.
    # Surface a diagnostic panel instead of sitting on "Restarting the
    # service…" indefinitely.
    Process.send_after(self(), :apply_done_stuck, 6_000)
    {:noreply, assign(socket, apply_phase: :done, apply_progress: pct)}
  end

  def handle_info({:progress, phase, pct}, socket) do
    {:noreply, assign(socket, apply_phase: phase, apply_progress: pct)}
  end

  def handle_info({:apply_failed, reason}, socket) do
    # Preserve whatever phase was active when the failure arrived so
    # the phase-row timeline in the modal can mark the right step as
    # failed (rather than all of them being grey/pending).
    {:noreply,
     assign(socket,
       apply_phase: :failed,
       apply_failed_at: socket.assigns.apply_phase,
       apply_error: reason
     )}
  end

  def handle_info({:apply_cancelled}, socket) do
    {:noreply,
     socket
     |> assign(
       apply_phase: nil,
       apply_progress: nil,
       apply_error: nil,
       apply_failed_at: nil
     )
     |> put_flash(:info, "Update cancelled.")}
  end

  def handle_info(:apply_done_stuck, socket) do
    if socket.assigns.apply_phase == :done do
      {:noreply, assign(socket, apply_phase: :done_stuck)}
    else
      {:noreply, socket}
    end
  end

  # Scheduled CheckerJob broadcast — refresh the visible card.
  def handle_info({:check_complete, {classification, release}}, socket)
      when classification in [:update_available, :up_to_date, :ahead_of_release] do
    {:noreply, assign(socket, update_status: classification, latest_release: release)}
  end

  def handle_info({:check_complete, {:error, reason}}, socket) do
    {:noreply, assign(socket, update_status: {:error, reason}, latest_release: nil)}
  end

  def handle_info({:check_started}, socket), do: {:noreply, socket}

  def handle_info({:config_updated, :watch_dirs, entries}, socket) do
    {:noreply, assign(socket, :watch_dirs, entries)}
  end

  def handle_info({:watch_dir_validate, params}, socket) do
    case socket.assigns.watch_dir_dialog do
      %{} = dialog ->
        entry = merge_entry(dialog.entry, params)

        validation =
          MediaCentarr.Watcher.validate_dir(
            entry,
            other_entries(socket.assigns.watch_dirs, entry)
          )

        new_dialog = %{dialog | entry: entry, validation: validation, debounce_timer: nil}
        {:noreply, assign(socket, :watch_dir_dialog, new_dialog)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:controls_changed, map}, socket) do
    {:noreply,
     socket
     |> assign(bindings: map)
     |> assign(glyph_style: Controls.glyph_style())
     |> assign(listening: nil)
     |> push_event("controls:updated", %{
       keyboard: keyboard_for_client(map),
       gamepad: gamepad_for_client(map)
     })}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp normalize_bind_value(:keyboard, value) when is_binary(value), do: value
  defp normalize_bind_value(:gamepad, value) when is_integer(value), do: value
  defp normalize_bind_value(:gamepad, value) when is_binary(value), do: String.to_integer(value)

  defp keyboard_for_client(map) do
    map
    |> Enum.flat_map(fn {id, %{key: key}} -> if key, do: [{key, id}], else: [] end)
    |> Map.new()
  end

  defp gamepad_for_client(map) do
    map
    |> Enum.flat_map(fn {id, %{button: button}} -> if button, do: [{button, id}], else: [] end)
    |> Map.new()
  end

  # Live validation for the Excluded Directories add-row input.
  # Called on every keystroke via phx-change. The checks are cheap
  # (string ops + one File.stat) so no debounce is needed.
  defp validate_exclude_dir(path, existing_list) do
    trimmed = String.trim(path || "")

    cond do
      trimmed == "" -> {:error, :empty}
      Path.type(trimmed) != :absolute -> {:error, :relative}
      trimmed in existing_list -> {:error, :duplicate}
      not File.dir?(trimmed) -> {:error, :not_a_directory}
      not path_readable?(trimmed) -> {:error, :not_readable}
      true -> {:ok, trimmed}
    end
  end

  defp validate_exclude_dir_error(path, existing_list) do
    case validate_exclude_dir(path, existing_list) do
      {:ok, _} -> nil
      {:error, :empty} -> nil
      {:error, :relative} -> "Must be an absolute path (starts with /)."
      {:error, :duplicate} -> "Already in the list."
      {:error, :not_a_directory} -> "Path does not exist or is not a directory."
      {:error, :not_readable} -> "Path exists but isn't readable by the app."
    end
  end

  defp path_readable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{access: access}} when access in [:read, :read_write] -> true
      _ -> false
    end
  end

  defp exclude_dir_add_disabled?(path, error) do
    String.trim(path || "") == "" or is_binary(error)
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
          <div :for={{group, index} <- Enum.with_index(Enum.chunk_by(@sections, & &1.group))}>
            <div :if={index > 0} class="my-2 mx-3 h-px bg-base-content/10"></div>
            <.link
              :for={section <- group}
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
          </div>
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
            repairing_images={@repairing_images}
            missing_images_summary={@missing_images_summary}
            spoiler_free={@spoiler_free}
            tmdb_test={@tmdb_test}
            tmdb_testing={@tmdb_testing}
            prowlarr_test={@prowlarr_test}
            prowlarr_testing={@prowlarr_testing}
            download_client_test={@download_client_test}
            download_client_testing={@download_client_testing}
            download_client_detect_status={@download_client_detect_status}
            download_client_detecting={@download_client_detecting}
            detected_download_client={@detected_download_client}
            app_version={@app_version}
            build_info={@build_info}
            update_status={@update_status}
            latest_release={@latest_release}
            apply_phase={@apply_phase}
            tmdb_missing={@tmdb_missing}
            service_state={@service_state}
            service_status_visible={@service_status_visible}
            service_status_output={@service_status_output}
            service_action_pending={@service_action_pending}
            watch_dirs={@watch_dirs}
            watch_dir_delete_confirm={@watch_dir_delete_confirm}
            exclude_dirs={@exclude_dirs}
            exclude_dir_input={@exclude_dir_input}
            exclude_dir_error={@exclude_dir_error}
            bindings={@bindings}
            glyph_style={@glyph_style}
            listening={@listening}
          />
        </div>
      </div>

      <%!--
        Apply-progress modal is a LAYOUT-LEVEL overlay, not a content
        row. Keeping it here — a sibling of the page's content root —
        matches the pattern used elsewhere in the app (see
        `modal_shell` in library_live) so its `position: fixed`
        containing block is the viewport, not some content wrapper.
      --%>
      <.apply_progress_modal
        apply_phase={@apply_phase}
        apply_progress={@apply_progress}
        apply_error={@apply_error}
        apply_failed_at={@apply_failed_at}
        latest_release={@latest_release}
      />

      <.service_action_modal action={@service_action_confirm} />

      <%!--
        Watch-dir dialog — always in DOM so backdrop-filter compositing
        layer is kept warm (same pattern as apply_progress_modal above).
      --%>
      <.watch_dir_dialog watch_dir_dialog={@watch_dir_dialog} watch_dirs={@watch_dirs} />
    </Layouts.app>
    """
  end

  # --- Section router ---

  defp section_content(%{active_section: "system"} = assigns) do
    groups =
      if assigns.config == %{} do
        []
      else
        Overview.build(%{
          watchers_running: assigns.watchers_running,
          pipeline_running: assigns.pipeline_running,
          image_pipeline_running: assigns.image_pipeline_running,
          prowlarr_test: assigns.prowlarr_test,
          download_client_test: assigns.download_client_test,
          config: assigns.config
        })
      end

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:issue_count, Overview.issue_count(groups))

    ~H"""
    <div class="space-y-5">
      <div class="p-6 rounded-lg glass-surface flex items-center gap-6">
        <img
          src={~p"/images/centaur-logo.png"}
          alt="Media Centarr"
          width="96"
          height="96"
          class="h-24 w-24 shrink-0 object-contain centaur-logo"
        />
        <div class="min-w-0 space-y-1.5">
          <h2 class="text-xl font-semibold tracking-tight">Media Centarr</h2>
          <p class="text-xs text-base-content/50">
            MIT License &middot; &copy; 2026 Shawn McCool
          </p>
          <div class="flex flex-wrap gap-x-4 gap-y-1 pt-2 text-xs font-mono text-base-content/60">
            <span>v{@app_version}</span>
            <span class="text-base-content/30">&middot;</span>
            <span>{SystemSection.built_label(@build_info)}</span>
          </div>
        </div>
      </div>

      <div :if={SelfUpdate.enabled?()} class="p-5 rounded-lg glass-surface">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Updates</h2>
            <p class="text-sm opacity-50 mt-0.5">
              Check GitHub for a newer release.
            </p>
          </div>
          <button
            type="button"
            phx-click="check_updates"
            disabled={@update_status == :checking}
            data-nav-item
            tabindex="0"
            class="btn btn-soft btn-primary btn-sm shrink-0"
          >
            {if @update_status == :checking, do: "Checking…", else: "Check for updates"}
          </button>
        </div>

        <div :if={@update_status != :idle} class="mt-4 pt-4 border-t border-base-content/10">
          <p class={"text-sm #{update_tone_class(SystemSection.update_status_tone(@update_status))}"}>
            {SystemSection.update_status_label(@update_status, @latest_release)}
          </p>
          <div
            :if={@update_status == :update_available and @latest_release}
            class="flex items-center gap-3 mt-2"
          >
            <button
              type="button"
              phx-click="apply_update"
              disabled={@apply_phase != nil}
              data-nav-item
              tabindex="0"
              class="btn btn-primary btn-sm"
            >
              Update now
            </button>
            <a
              href={@latest_release.html_url}
              target="_blank"
              rel="noopener noreferrer"
              class="link link-primary text-sm"
              data-nav-item
              tabindex="0"
            >
              View on GitHub →
            </a>
          </div>

          <details
            :if={@latest_release && SystemSection.show_release_notes?(@update_status)}
            class="release-notes-disclosure mt-3 pt-3 border-t border-base-content/10"
          >
            <summary class="cursor-pointer text-sm text-base-content/70 hover:text-base-content transition-colors inline-flex items-center gap-1.5 select-none">
              <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
              <span>See what's new in {@latest_release.tag}</span>
            </summary>
            <div class="mt-3 space-y-2">
              <div class="glass-inset rounded-md p-4 max-h-80 overflow-y-auto thin-scrollbar text-xs">
                <ReleaseNotes.release_notes body={Map.get(@latest_release, :body, "")} />
              </div>
              <a
                :if={@latest_release.html_url != ""}
                href={@latest_release.html_url}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-block text-xs link link-primary"
                data-nav-item
                tabindex="0"
              >
                Read full notes on GitHub →
              </a>
            </div>
          </details>

          <details class="release-notes-disclosure mt-2">
            <summary class="cursor-pointer text-xs text-base-content/50 hover:text-base-content/80 transition-colors inline-flex items-center gap-1.5 select-none">
              <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
              <span>Prefer the terminal?</span>
            </summary>
            <div class="mt-3 ml-5 pl-4 border-l border-base-content/10 space-y-3 text-sm">
              <div class="space-y-1">
                <p class="text-xs text-base-content/70">
                  Standard update (same as the button):
                </p>
                <div class="glass-inset rounded-md p-2 flex items-center gap-2">
                  <code class="font-mono text-[11px] text-base-content/80 flex-1 truncate">
                    {SystemSection.terminal_recovery_command()}
                  </code>
                  <button
                    id="copy-terminal-update"
                    type="button"
                    phx-hook="CopyButton"
                    data-copy-text={SystemSection.terminal_recovery_command()}
                    class="btn btn-xs btn-ghost shrink-0"
                    data-nav-item
                    tabindex="0"
                  >
                    Copy
                  </button>
                </div>
              </div>

              <div class="space-y-1">
                <p class="text-xs text-base-content/70">
                  Force a reinstall (if a previous apply got stuck):
                </p>
                <div class="glass-inset rounded-md p-2 flex items-center gap-2">
                  <code class="font-mono text-[11px] text-base-content/80 flex-1 truncate">
                    {SystemSection.force_recovery_command()}
                  </code>
                  <button
                    id="copy-terminal-force"
                    type="button"
                    phx-hook="CopyButton"
                    data-copy-text={SystemSection.force_recovery_command()}
                    class="btn btn-xs btn-ghost shrink-0"
                    data-nav-item
                    tabindex="0"
                  >
                    Copy
                  </button>
                </div>
              </div>

              <div class="space-y-1">
                <p class="text-xs text-base-content/70">
                  Or reinstall from scratch:
                </p>
                <div class="glass-inset rounded-md p-2 flex items-center gap-2">
                  <code class="font-mono text-[11px] text-base-content/80 flex-1 truncate">
                    {SystemSection.bootstrap_install_command()}
                  </code>
                  <button
                    id="copy-terminal-bootstrap"
                    type="button"
                    phx-hook="CopyButton"
                    data-copy-text={SystemSection.bootstrap_install_command()}
                    class="btn btn-xs btn-ghost shrink-0"
                    data-nav-item
                    tabindex="0"
                  >
                    Copy
                  </button>
                </div>
              </div>
            </div>
          </details>
        </div>
      </div>

      <.service_card
        service_state={@service_state}
        service_status_visible={@service_status_visible}
        service_status_output={@service_status_output}
        service_action_pending={@service_action_pending}
      />

      <div
        :if={@tmdb_missing}
        class="p-4 rounded-lg border border-info/30 bg-info/10 text-sm flex items-start justify-between gap-4"
      >
        <div>
          <p class="font-medium">No TMDB API key configured</p>
          <p class="text-base-content/70 mt-0.5">
            Add one to fetch posters, backdrops, and metadata for your library.
          </p>
        </div>
        <.link
          navigate={~p"/settings?section=tmdb"}
          class="btn btn-sm btn-primary shrink-0"
          data-nav-item
        >
          Add key
        </.link>
      </div>

      <div class="p-5 rounded-lg glass-surface">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Health Check</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              {overview_summary(@issue_count)}
            </p>
          </div>
          <div
            :if={@issue_count > 0}
            class="shrink-0 flex items-center gap-2 text-xs font-medium px-2.5 py-1 rounded-full bg-warning/10 text-warning"
          >
            <.icon name="hero-exclamation-triangle-mini" class="size-3.5" />
            {@issue_count} {if @issue_count == 1, do: "issue", else: "issues"}
          </div>
          <div
            :if={@issue_count == 0 and @config != %{}}
            class="shrink-0 flex items-center gap-2 text-xs font-medium px-2.5 py-1 rounded-full bg-success/10 text-success"
          >
            <.icon name="hero-check-circle-mini" class="size-3.5" /> All good
          </div>
        </div>
      </div>

      <div :if={@config == %{}} class="p-5 rounded-lg glass-surface text-base-content/60">
        Loading configuration…
      </div>

      <div :for={group <- @groups} class="p-5 rounded-lg glass-surface space-y-2">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {group.label}
        </h3>

        <ul class="divide-y divide-base-content/5">
          <li :for={item <- group.items}>
            <.link
              patch={item.link}
              data-nav-item
              tabindex="0"
              class="flex items-center gap-3 py-2.5 -mx-2 px-2 rounded-lg transition-colors duration-150 hover:bg-base-content/5 focus:bg-base-content/5"
            >
              <.overview_status_icon status={item.status} />

              <div class="min-w-0 flex-1">
                <div class="text-sm font-medium">{item.label}</div>
                <div class={[
                  "text-xs truncate",
                  overview_detail_class(item.status)
                ]}>
                  {item.detail}
                </div>
              </div>

              <.icon
                name="hero-chevron-right-mini"
                class="size-4 text-base-content/30 shrink-0"
              />
            </.link>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "services"} = assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Services</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Start or stop background services. State persists across restarts.
          </p>
        </div>
      </div>

      <div class="mt-4 space-y-0.5">
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

      <div class="mt-4 pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
        <p class="text-xs text-base-content/50 min-w-0">
          Manually scan all watch directories for new media files.
        </p>
        <div class="flex items-center gap-2 shrink-0">
          <button
            :if={@scanning}
            phx-click="cancel_scan"
            data-nav-item
            tabindex="0"
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </button>
          <button
            phx-click="scan"
            disabled={@scanning}
            data-nav-item
            tabindex="0"
            class="btn btn-soft btn-success btn-sm"
          >
            <span :if={@scanning} class="loading loading-spinner loading-xs"></span>
            {if @scanning, do: "Scanning…", else: "Scan now"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "preferences"} = assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Preferences</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Personal browsing settings — applied only to your session.
          </p>
        </div>
      </div>

      <div class="mt-4 space-y-0.5">
        <.settings_row
          label="Spoiler-free mode"
          description="Blur episode descriptions until hovered"
          checked={@spoiler_free}
          event="toggle_spoiler_free"
          color="info"
        />
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "controls"} = assigns) do
    ~H"""
    <ControlsSection.render bindings={@bindings} glyph_style={@glyph_style} listening={@listening} />
    """
  end

  defp section_content(%{active_section: "tmdb"} = assigns) do
    ~H"""
    <form id="settings-tmdb" phx-submit="save_tmdb" class="p-5 rounded-lg glass-surface space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            TMDB <.status_dot configured={@config[:tmdb_api_key_configured?]} />
          </h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            The Movie Database API — required for metadata scraping and artwork.
          </p>
        </div>
        <button
          type="submit"
          class="btn btn-soft btn-primary btn-sm shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </button>
      </div>

      <div class="space-y-3">
        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            API Key
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
          <p class="text-xs text-base-content/40 mt-1">
            Don't have one yet? Request a free key at <a
              href="https://www.themoviedb.org/settings/api"
              target="_blank"
              rel="noopener noreferrer"
              class="link link-primary"
            >themoviedb.org/settings/api</a>.
          </p>
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

      <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
        <.connection_status
          test={@tmdb_test}
          ok_label="Connected"
          error_label="Unreachable"
        />
        <button
          type="submit"
          name="_action"
          value="test"
          class="btn btn-soft btn-sm shrink-0"
          disabled={@tmdb_testing}
          data-nav-item
          tabindex="0"
        >
          <span :if={@tmdb_testing} class="loading loading-spinner loading-xs"></span>
          <.icon :if={!@tmdb_testing} name="hero-signal-mini" class="size-4" />
          {if @tmdb_testing, do: "Testing…", else: "Test connection"}
        </button>
      </div>
    </form>
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
    <div class="space-y-5">
      <form
        id="settings-prowlarr"
        phx-submit="save_prowlarr"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              Prowlarr <.status_dot configured={@config[:prowlarr_api_key_configured?]} />
            </h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Indexer proxy that searches for media and forwards grabs.
            </p>
          </div>
          <button
            type="submit"
            class="btn btn-soft btn-primary btn-sm shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </button>
        </div>

        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              URL
            </label>
            <input
              type="text"
              name="prowlarr_url"
              value={@config[:prowlarr_url]}
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              API Key
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

        <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <.connection_status
            test={@prowlarr_test}
            ok_label="Connected"
            error_label="Unreachable"
          />
          <button
            type="submit"
            name="_action"
            value="test"
            class="btn btn-soft btn-sm shrink-0"
            disabled={@prowlarr_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@prowlarr_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@prowlarr_testing} name="hero-signal-mini" class="size-4" />
            {if @prowlarr_testing, do: "Testing…", else: "Test connection"}
          </button>
        </div>
      </form>

      <form
        id="settings-download-client"
        phx-submit="save_download_client"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              Download Client
              <.status_dot configured={@config[:download_client_password_configured?]} />
            </h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Where Prowlarr forwards grabs. Powers the Downloads page progress.
            </p>
          </div>
          <div class="flex flex-wrap gap-2 shrink-0">
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
              />
              {if @download_client_detecting, do: "Detecting…", else: "Detect"}
            </button>
            <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
              Save
            </button>
          </div>
        </div>

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
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Must be reachable from <em>this</em>
              machine. If you used <span class="font-mono">Detect from Prowlarr</span>, verify the URL —
              Prowlarr often returns Docker-internal hostnames (<span class="font-mono">qbittorrent:8080</span>)
              that only resolve inside the container network.
            </p>
          </div>

          <div class="grid grid-cols-2 gap-3">
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
              </label>
              <input
                type="password"
                name="download_client_password"
                class="input input-bordered w-full font-mono text-sm"
                placeholder={
                  if @config[:download_client_password_configured?],
                    do: "Leave blank to keep current",
                    else: "Enter password"
                }
                autocomplete="off"
                data-nav-item
                tabindex="0"
              />
            </div>
          </div>
        </div>

        <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <.connection_status
            test={@download_client_test}
            ok_label="Connected"
            error_label="Unreachable / auth failed"
          />
          <button
            type="submit"
            name="_action"
            value="test"
            class="btn btn-soft btn-sm shrink-0"
            disabled={@download_client_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@download_client_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@download_client_testing} name="hero-signal-mini" class="size-4" />
            {if @download_client_testing, do: "Testing…", else: "Test connection"}
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "pipeline"} = assigns) do
    ~H"""
    <form phx-submit="save_pipeline" class="p-5 rounded-lg glass-surface space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Pipeline</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Controls how files are classified during ingestion.
          </p>
        </div>
        <button
          type="submit"
          class="btn btn-soft btn-primary btn-sm shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </button>
      </div>

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
    </form>
    """
  end

  defp section_content(%{active_section: "playback"} = assigns) do
    ~H"""
    <form phx-submit="save_playback" class="p-5 rounded-lg glass-surface space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Playback</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            MPV player configuration.
          </p>
        </div>
        <button
          type="submit"
          class="btn btn-soft btn-primary btn-sm shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </button>
      </div>

      <div class="space-y-3">
        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 flex items-center gap-1.5 mb-1.5">
            <span>MPV path</span>
            <.path_status :if={@config[:mpv_path]} path={@config[:mpv_path]} kind={:executable} />
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

        <div class="grid grid-cols-[1fr_auto] gap-3">
          <div class="min-w-0">
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 flex items-center gap-1.5 mb-1.5">
              <span>IPC socket directory</span>
              <.path_status
                :if={@config[:mpv_socket_dir]}
                path={@config[:mpv_socket_dir]}
                kind={:directory}
              />
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

          <div class="w-36">
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Timeout (ms)
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
      </div>
    </form>
    """
  end

  defp section_content(%{active_section: "library"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <form
        phx-submit="save_data_dir"
        class="glass-surface rounded-xl p-4 space-y-3"
      >
        <div class="flex items-baseline justify-between">
          <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
            Data directory
          </h3>
          <button type="submit" class="btn btn-soft btn-primary btn-sm" data-nav-item tabindex="0">
            Save
          </button>
        </div>

        <p class="text-xs text-base-content/50">
          Where Media Centarr stores its caches outside the watch directories —
          currently tracking-item poster and backdrop images. Defaults to the
          parent directory of the SQLite database.
        </p>

        <input
          type="text"
          name="data_dir"
          value={@config[:data_dir]}
          placeholder={Path.dirname(@config[:database_path] || "")}
          class="input input-bordered w-full font-mono text-sm"
          data-nav-item
          tabindex="0"
        />

        <p class="text-xs text-base-content/40">
          Images already on disk under the previous location are still served
          (legacy `./data/` fallback) so changes don't strand existing files.
        </p>
      </form>

      <div class="glass-surface rounded-xl p-4 space-y-3">
        <div class="flex items-baseline justify-between">
          <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
            Watch Directories
          </h3>
          <button
            class="btn btn-soft btn-success btn-sm"
            phx-click="watch_dir:open_add"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-plus" class="size-4" /> Add
          </button>
        </div>

        <div :if={@watch_dirs == []} class="text-base-content/60 py-4">
          No watch directories configured — your library is empty. Add one to get started.
        </div>

        <ul :if={@watch_dirs != []} class="space-y-2">
          <li
            :for={entry <- @watch_dirs}
            class="glass-inset rounded-lg p-3 flex items-start justify-between gap-3"
          >
            <div class="min-w-0 flex-1 space-y-0.5">
              <%= if entry["name"] && entry["name"] != "" do %>
                <div class="font-medium truncate">{entry["name"]}</div>
                <div class="text-sm text-base-content/60 truncate" title={entry["dir"]}>
                  {entry["dir"]}
                </div>
              <% else %>
                <div class="font-medium truncate" title={entry["dir"]}>{entry["dir"]}</div>
              <% end %>
              <div
                :if={WatchDirsLogic.show_images_dir?(entry)}
                class="text-xs text-base-content/50 truncate"
                title={entry["images_dir"]}
              >
                Images cached at {entry["images_dir"]}
              </div>
            </div>

            <div class="flex gap-1 shrink-0">
              <button
                class="btn btn-ghost btn-sm"
                phx-click="watch_dir:open_edit"
                phx-value-id={entry["id"]}
                aria-label="Edit watch directory"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>
              <%= if @watch_dir_delete_confirm == entry["id"] do %>
                <button
                  class="btn btn-soft btn-error btn-sm"
                  phx-click="watch_dir:delete"
                  phx-value-id={entry["id"]}
                  data-nav-item
                  tabindex="0"
                >
                  Confirm
                </button>
                <button
                  class="btn btn-ghost btn-sm"
                  phx-click="watch_dir:delete_cancel"
                  data-nav-item
                  tabindex="0"
                >
                  Cancel
                </button>
              <% else %>
                <button
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="watch_dir:delete_confirm"
                  phx-value-id={entry["id"]}
                  aria-label="Remove watch directory"
                  data-nav-item
                  tabindex="0"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              <% end %>
            </div>
          </li>
        </ul>
      </div>

      <div class="glass-surface rounded-xl p-4 space-y-3">
        <div>
          <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
            Excluded Directories
          </h3>
          <p class="text-xs text-base-content/60 mt-1">
            Paths inside your watch directories that should be ignored — handy for
            downloads-cache folders, trash bins, anything with transient files you
            don't want indexed.
          </p>
        </div>

        <ul :if={@exclude_dirs != []} class="space-y-2">
          <li
            :for={path <- @exclude_dirs}
            class="glass-inset rounded-lg p-3 flex items-center gap-3"
          >
            <span class="flex-1 min-w-0 text-sm truncate" title={path}>{path}</span>
            <button
              class="btn btn-ghost btn-sm text-error shrink-0"
              phx-click="exclude_dir:delete"
              phx-value-path={path}
              data-confirm={"Remove #{path} from excluded directories?"}
              aria-label="Remove excluded directory"
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </li>
        </ul>

        <div :if={@exclude_dirs == []} class="text-xs text-base-content/50 py-2">
          No excluded directories.
        </div>

        <form
          phx-change="exclude_dir:validate"
          phx-submit="exclude_dir:add"
          class="space-y-1.5 pt-1"
        >
          <div class="flex gap-2">
            <input
              type="text"
              name="path"
              value={@exclude_dir_input}
              placeholder="/absolute/path/to/exclude"
              class="library-filter flex-1"
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
            <button
              type="submit"
              class="btn btn-soft btn-success btn-sm shrink-0"
              disabled={exclude_dir_add_disabled?(@exclude_dir_input, @exclude_dir_error)}
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-plus" class="size-4" /> Add
            </button>
          </div>
          <p :if={is_binary(@exclude_dir_error)} class="text-error text-xs">
            {@exclude_dir_error}
          </p>
        </form>
      </div>

      <form
        id="settings-library"
        phx-submit="save_library"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Library</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Cleanup and status display tuning.
            </p>
          </div>
          <button
            type="submit"
            class="btn btn-soft btn-primary btn-sm shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </button>
        </div>

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
              Grace period for a file that disappears from its watch directory — useful
              when media lives on an external drive or network share that isn't always
              mounted. Only after this many days of continuous absence will the library
              entry be removed.
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
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "release_tracking"} = assigns) do
    auto_grab = MediaCentarr.Acquisition.AutoGrabSettings.load()
    prowlarr_ready = MediaCentarr.Capabilities.prowlarr_ready?()

    assigns = assign(assigns, auto_grab: auto_grab, prowlarr_ready: prowlarr_ready)

    ~H"""
    <div class="space-y-5">
      <form phx-submit="save_release_tracking" class="p-5 rounded-lg glass-surface space-y-5">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Release Tracking</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              How often to poll TMDB for upcoming release dates.
            </p>
          </div>
          <button
            type="submit"
            class="btn btn-soft btn-primary btn-sm shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </button>
        </div>

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
      </form>

      <form
        :if={@prowlarr_ready}
        phx-submit="save_auto_grab_defaults"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Auto-acquisition defaults</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Applied when a tracked release becomes available. Per-item
              overrides on individual tracking entries take precedence.
            </p>
          </div>
          <button
            type="submit"
            class="btn btn-soft btn-primary btn-sm shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Default mode
            </label>
            <select
              name="auto_grab[default_mode]"
              class="select select-bordered w-full"
              data-nav-item
              tabindex="0"
            >
              <option value="all_releases" selected={@auto_grab.default_mode == "all_releases"}>
                Auto-grab all releases
              </option>
              <option value="off" selected={@auto_grab.default_mode == "off"}>
                Off (notify only)
              </option>
            </select>
            <p class="text-xs text-base-content/40 mt-1">
              Applies to newly-tracked items. Existing items keep their per-item override.
            </p>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              4K patience (hours)
            </label>
            <input
              type="number"
              name="auto_grab[4k_patience_hours]"
              value={@auto_grab.patience_hours}
              min="0"
              max="720"
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Wait this long for a 4K release before falling back to 1080p. Set to 0 to grab immediately.
            </p>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Minimum quality (final fallback)
            </label>
            <select
              name="auto_grab[default_min_quality]"
              class="select select-bordered w-full"
              data-nav-item
              tabindex="0"
            >
              <option value="hd_1080p" selected={@auto_grab.default_min_quality == "hd_1080p"}>
                1080p
              </option>
              <option value="uhd_4k" selected={@auto_grab.default_min_quality == "uhd_4k"}>
                4K only
              </option>
            </select>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Maximum quality
            </label>
            <select
              name="auto_grab[default_max_quality]"
              class="select select-bordered w-full"
              data-nav-item
              tabindex="0"
            >
              <option value="uhd_4k" selected={@auto_grab.default_max_quality == "uhd_4k"}>
                4K
              </option>
              <option value="hd_1080p" selected={@auto_grab.default_max_quality == "hd_1080p"}>
                1080p (no 4K)
              </option>
            </select>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Maximum search attempts
            </label>
            <input
              type="number"
              name="auto_grab[max_attempts]"
              value={@auto_grab.max_attempts}
              min="1"
              max="50"
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              How many failed search cycles before giving up on a release.
            </p>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp section_content(%{active_section: "danger"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div data-nav-grid class="p-5 rounded-lg glass-surface space-y-4">
        <div class="flex items-start gap-3">
          <.icon name="hero-wrench-screwdriver" class="size-6 text-base-content/70 shrink-0 mt-0.5" />
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Library maintenance</h2>
            <p class="text-sm text-base-content/60 mt-0.5">
              Non-destructive housekeeping — detect and heal gaps in the library's cached artwork.
            </p>
          </div>
        </div>

        <div class="divide-y divide-base-content/10">
          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">
                Repair missing images
                <span
                  :if={@missing_images_summary.missing > 0}
                  class="ml-2 badge badge-sm badge-warning"
                >
                  {@missing_images_summary.missing} missing
                </span>
              </p>
              <p class="text-xs text-base-content/50 mt-0.5">
                <%= if @missing_images_summary.missing > 0 do %>
                  Finds {@missing_images_summary.missing} image file{if @missing_images_summary.missing ==
                                                                          1,
                                                                        do: "",
                                                                        else: "s"} referenced in the database but absent on disk, and re-queues each one for download from TMDB. Reuses stored source URLs where available; re-queries TMDB when the queue entry is missing.
                <% else %>
                  All image files are present on disk. Nothing to repair.
                <% end %>
              </p>
            </div>
            <button
              phx-click="repair_missing_images"
              disabled={@repairing_images or @missing_images_summary.missing == 0}
              data-nav-item
              tabindex="0"
              class="btn btn-soft btn-sm shrink-0"
            >
              {if @repairing_images, do: "Repairing…", else: "Repair"}
            </button>
          </div>
        </div>
      </div>

      <div data-nav-grid class="p-5 rounded-lg glass-surface border border-error/20 space-y-4">
        <div class="flex items-start gap-3">
          <.icon name="hero-exclamation-triangle" class="size-6 text-error shrink-0 mt-0.5" />
          <div class="min-w-0">
            <h2 class="text-lg font-semibold text-error">Danger Zone</h2>
            <p class="text-sm text-base-content/60 mt-0.5">
              Destructive actions that cannot be undone. Read the prompt carefully before confirming.
            </p>
          </div>
        </div>

        <div class="divide-y divide-base-content/10">
          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">Clear database</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Permanently deletes all entities, files, images, and progress.
              </p>
            </div>
            <button
              phx-click="clear_database"
              disabled={@clearing_database}
              data-confirm="This will permanently delete ALL entities, files, images, and progress. This cannot be undone. Continue?"
              data-nav-item
              tabindex="0"
              class="btn btn-soft btn-error btn-sm shrink-0"
            >
              {if @clearing_database, do: "Clearing…", else: "Clear"}
            </button>
          </div>

          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">Refresh image cache</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Deletes all cached artwork and re-downloads from TMDB. May take a while.
              </p>
            </div>
            <button
              phx-click="refresh_image_cache"
              disabled={@refreshing_images}
              data-confirm={
                if @refreshing_images,
                  do: nil,
                  else:
                    "This will delete all cached artwork and re-download from TMDB. This may take a while. Continue?"
              }
              data-nav-item
              tabindex="0"
              class="btn btn-soft btn-warning btn-sm shrink-0"
            >
              {if @refreshing_images, do: "Refreshing…", else: "Refresh"}
            </button>
          </div>
        </div>
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

  defp update_tone_class(:neutral), do: "text-base-content/60"
  defp update_tone_class(:success), do: "text-success"
  defp update_tone_class(:info), do: "text-info"
  defp update_tone_class(:warning), do: "text-warning"
  defp update_tone_class(:error), do: "text-error"

  # One row in the apply-progress modal's phase list. Renders an icon
  # reflecting the phase's state (pending / active / done / failed), a
  # label, and — for the downloading phase specifically — an inline
  # progress bar that animates as `@progress` changes.
  attr :phase, :atom, required: true
  attr :current, :atom, required: true
  attr :failed_at, :atom, default: nil
  attr :progress, :any, default: nil

  defp apply_phase_row(assigns) do
    state = SystemSection.phase_state(assigns.phase, assigns.current, assigns.failed_at)
    assigns = assign(assigns, :state, state)

    # Icons sized for text-sm labels (14px): size-4 (16px) keeps the
    # glyph proportional to its label. `-mini` variants are the lighter
    # heroicons family intended for inline-adjacent use — they match
    # the visual weight of surrounding text far better than `-solid`.
    ~H"""
    <li class="flex items-start gap-3">
      <%!--
        Icon wrapper matches the label's line-height (1.25rem, i.e. h-5)
        so the icon's visual center sits on the first line of the label,
        same vertical rhythm as the text itself.
      --%>
      <div class="shrink-0 w-5 h-5 flex items-center justify-center">
        <div :if={@state == :pending} class="w-2.5 h-2.5 rounded-full border border-base-content/30">
        </div>
        <.icon
          :if={@state == :active}
          name="hero-arrow-path-mini"
          class="size-4 animate-spin text-primary"
        />
        <.icon :if={@state == :done} name="hero-check-circle-mini" class="size-4 text-success" />
        <.icon :if={@state == :failed} name="hero-x-circle-mini" class="size-4 text-error" />
      </div>
      <div class="flex-1 min-w-0">
        <p class={phase_text_class(@state)}>
          {SystemSection.apply_phase_label(@phase)}
        </p>
        <div
          :if={@state == :active and @phase == :downloading}
          class="h-1.5 mt-2 rounded bg-base-content/10 overflow-hidden"
        >
          <div
            class="h-full bg-primary rounded transition-[width] duration-150 ease-out"
            style={"width: #{@progress || 0}%"}
          >
          </div>
        </div>
      </div>
    </li>
    """
  end

  defp phase_text_class(:pending), do: "text-sm text-base-content/40"
  defp phase_text_class(:active), do: "text-sm text-base-content font-medium"
  defp phase_text_class(:done), do: "text-sm text-base-content/70"
  defp phase_text_class(:failed), do: "text-sm text-error"

  # Modal rendered at the `Layouts.app` slot root so its `position:
  # fixed` containing block is the viewport, not some nested content
  # wrapper. Same placement pattern as `ModalShell.modal_shell` in
  # library_live — proven to render over the full viewport.
  attr :apply_phase, :atom, default: nil
  attr :apply_progress, :any, default: nil
  attr :apply_error, :any, default: nil
  attr :apply_failed_at, :atom, default: nil
  attr :latest_release, :map, default: nil

  defp apply_progress_modal(assigns) do
    ~H"""
    <div
      class="modal-backdrop"
      data-state={if SystemSection.apply_visible?(@apply_phase), do: "open", else: "closed"}
      role="dialog"
      aria-modal="true"
      aria-labelledby="apply-modal-title"
    >
      <div class="modal-panel modal-panel-sm p-6 space-y-5">
        <div class="space-y-1">
          <h3 id="apply-modal-title" class="text-lg font-semibold">
            Updating
            <span :if={@latest_release} class="font-mono text-sm text-base-content/60 ml-1">
              {@latest_release.tag}
            </span>
          </h3>
          <p class="text-sm text-base-content/60">
            This usually takes under a minute. The app will restart when it finishes.
          </p>
        </div>

        <ol class="space-y-3">
          <.apply_phase_row
            :for={phase <- SystemSection.visible_phases()}
            phase={phase}
            current={@apply_phase}
            failed_at={@apply_failed_at}
            progress={@apply_progress}
          />
        </ol>

        <div
          :if={SystemSection.apply_cancelable?(@apply_phase)}
          class="flex justify-end pt-2"
        >
          <button
            type="button"
            phx-click="cancel_update"
            data-nav-item
            tabindex="0"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-x-mark-mini" class="size-4" /> Cancel update
          </button>
        </div>

        <div
          :if={@apply_phase == :failed}
          class="pt-4 border-t border-base-content/10 space-y-3"
        >
          <div class="space-y-1">
            <p class="text-sm text-error">
              {SystemSection.apply_error_label(@apply_error)}
            </p>
            <p class="text-xs text-base-content/50">
              The running install is untouched.
            </p>
          </div>

          <div class="space-y-1">
            <p class="text-xs font-medium text-base-content/70">
              If it keeps failing, update from a terminal:
            </p>
            <div class="glass-inset rounded-md p-2 flex items-center gap-2">
              <code class="font-mono text-[11px] text-base-content/80 flex-1 truncate">
                {SystemSection.terminal_recovery_command()}
              </code>
              <button
                id="copy-terminal-recovery"
                type="button"
                phx-hook="CopyButton"
                data-copy-text={SystemSection.terminal_recovery_command()}
                class="btn btn-xs btn-ghost shrink-0"
                data-nav-item
                tabindex="0"
              >
                Copy
              </button>
            </div>
          </div>
        </div>

        <div
          :if={@apply_phase == :done_stuck}
          class="pt-4 border-t border-base-content/10 space-y-3"
        >
          <div class="space-y-1">
            <p class="text-sm text-warning">
              The service didn't restart on its own.
            </p>
            <p class="text-xs text-base-content/60">
              The new release was staged successfully. Restart the service manually to finish:
            </p>
          </div>

          <div class="glass-inset rounded-md p-2 flex items-center gap-2">
            <code class="font-mono text-[11px] text-base-content/80 flex-1 truncate">
              systemctl --user restart media-centarr
            </code>
            <button
              id="copy-stuck-restart"
              type="button"
              phx-hook="CopyButton"
              data-copy-text="systemctl --user restart media-centarr"
              class="btn btn-xs btn-ghost shrink-0"
              data-nav-item
              tabindex="0"
            >
              Copy
            </button>
          </div>
        </div>

        <div
          :if={@apply_phase in [:failed, :done_stuck]}
          class="flex justify-end gap-2 pt-2"
        >
          <button
            type="button"
            phx-click="dismiss_apply_modal"
            data-nav-item
            tabindex="0"
            class="btn btn-ghost btn-sm"
          >
            Close
          </button>
          <button
            :if={@apply_phase == :failed}
            type="button"
            phx-click="apply_update"
            data-nav-item
            tabindex="0"
            class="btn btn-primary btn-sm"
          >
            Retry
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Service action confirmation modal. Always in DOM; opens when
  # `@action` is set to "restart" or "stop". Destructive actions get an
  # amber soft button; restart (recoverable) gets primary.
  attr :action, :any, default: nil

  defp service_action_modal(assigns) do
    ~H"""
    <div
      class="modal-backdrop"
      data-state={if @action, do: "open", else: "closed"}
      role="dialog"
      aria-modal="true"
      aria-labelledby="service-confirm-title"
      phx-click-away={@action && JS.push("service_cancel")}
      phx-window-keydown={@action && JS.push("service_cancel")}
      phx-key="Escape"
    >
      <div class="modal-panel modal-panel-sm p-6 space-y-4">
        <div class="space-y-1">
          <h3 id="service-confirm-title" class="text-lg font-semibold">
            {service_confirm_title(@action)}
          </h3>
          <p class="text-sm text-base-content/70">
            {service_confirm_body(@action)}
          </p>
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <button
            type="button"
            phx-click="service_cancel"
            data-nav-item
            tabindex="0"
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="service_execute"
            phx-value-action={@action || ""}
            data-nav-item
            tabindex="0"
            class={service_confirm_button_class(@action)}
          >
            {service_confirm_cta(@action)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :watch_dir_dialog, :any, default: nil
  attr :watch_dirs, :list, default: []

  defp watch_dir_dialog(assigns) do
    ~H"""
    <div
      class="modal-backdrop"
      data-state={if @watch_dir_dialog, do: "open", else: "closed"}
      role="dialog"
      aria-modal="true"
      aria-labelledby="watch-dir-dialog-title"
      phx-window-keydown={@watch_dir_dialog && "watch_dir:close"}
      phx-key="Escape"
    >
      <div
        class="modal-panel modal-panel-sm p-6"
        phx-click-away={@watch_dir_dialog && "watch_dir:close"}
      >
        <button
          phx-click="watch_dir:close"
          class="absolute top-3 right-3 z-10 btn btn-ghost btn-circle btn-sm"
          aria-label="Close"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </button>

        <h3 id="watch-dir-dialog-title" class="text-lg font-semibold mb-4">
          {if @watch_dir_dialog &&
                Enum.any?(@watch_dirs, &(&1["id"] == @watch_dir_dialog.entry["id"])),
              do: "Edit watch directory",
              else: "Add watch directory"}
        </h3>

        <form
          :if={@watch_dir_dialog}
          phx-change="watch_dir:validate"
          phx-submit="watch_dir:save"
          class="space-y-3"
        >
          <div>
            <label class="text-sm font-medium">Directory</label>
            <input
              type="text"
              name="entry[dir]"
              value={@watch_dir_dialog.entry["dir"]}
              class="library-filter w-full"
            />
            <.watch_dir_errors errors={@watch_dir_dialog.validation.errors} field={:dir} />
          </div>

          <div>
            <label class="text-sm font-medium">
              Name <span class="text-base-content/50">(optional)</span>
            </label>
            <input
              type="text"
              name="entry[name]"
              value={@watch_dir_dialog.entry["name"]}
              class="library-filter w-full"
            />
            <.watch_dir_errors errors={@watch_dir_dialog.validation.errors} field={:name} />
          </div>

          <details>
            <summary class="cursor-pointer text-sm text-base-content/60">
              Advanced — images directory
            </summary>
            <div class="mt-2 space-y-1">
              <input
                type="text"
                name="entry[images_dir]"
                value={@watch_dir_dialog.entry["images_dir"]}
                class="library-filter w-full"
                placeholder="Leave blank to use the default"
              />
              <p class="text-xs text-base-content/50">
                If blank, artwork is cached at
                <code class="font-mono">
                  {WatchDirsLogic.default_images_dir_hint(@watch_dir_dialog.entry["dir"])}
                </code>
                and automatically skipped by the file watcher.
              </p>
              <.watch_dir_errors
                errors={@watch_dir_dialog.validation.errors}
                field={:images_dir}
              />
            </div>
          </details>

          <div
            :if={@watch_dir_dialog.validation.preview}
            class="glass-inset rounded-lg p-3 text-sm text-base-content/70"
          >
            Found {@watch_dir_dialog.validation.preview.video_count} video files, {@watch_dir_dialog.validation.preview.subdir_count} subdirectories.
          </div>

          <div
            :for={warning <- @watch_dir_dialog.validation.warnings}
            class="text-warning text-sm"
          >
            {WatchDirsLogic.error_message(warning)}
          </div>

          <div class="flex justify-end gap-2 pt-2">
            <button type="button" class="btn btn-ghost" phx-click="watch_dir:close">
              Cancel
            </button>
            <button
              type="submit"
              class="btn btn-primary"
              disabled={not WatchDirsLogic.saveable?(@watch_dir_dialog.validation)}
            >
              Save
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp service_confirm_title("restart"), do: "Restart the service?"
  defp service_confirm_title("stop"), do: "Stop the service?"
  defp service_confirm_title(_), do: ""

  defp service_confirm_body("restart"),
    do:
      "The app will briefly go offline while systemd restarts it. Your browser will reconnect automatically."

  defp service_confirm_body("stop"),
    do:
      "The app will stop. You'll need to start it again manually (systemctl --user start media-centarr) to bring it back."

  defp service_confirm_body(_), do: ""

  defp service_confirm_cta("restart"), do: "Restart"
  defp service_confirm_cta("stop"), do: "Stop"
  defp service_confirm_cta(_), do: ""

  defp service_confirm_button_class("restart"), do: "btn btn-primary btn-sm"
  defp service_confirm_button_class("stop"), do: "btn btn-soft btn-warning btn-sm"
  defp service_confirm_button_class(_), do: "btn btn-sm"

  # Inline Service card — rendered inside the overview section.
  attr :service_state, :map, required: true
  attr :service_status_visible, :boolean, default: false
  attr :service_status_output, :any, default: nil
  attr :service_action_pending, :atom, default: nil

  defp service_card(assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Service</h2>
          <p class="text-sm opacity-50 mt-0.5">
            {service_card_subtitle(@service_state)}
          </p>
        </div>

        <div class={service_state_badge_class(@service_state)}>
          <.icon name={service_state_badge_icon(@service_state)} class="size-3.5" />
          {service_state_badge_text(@service_state)}
        </div>
      </div>

      <div
        :if={@service_action_pending}
        class="flex items-center gap-2 text-sm text-info rounded-md glass-inset px-3 py-2"
        role="status"
        aria-live="polite"
      >
        <.icon name="hero-arrow-path-mini" class="size-4 animate-spin" />
        <span>{service_action_pending_label(@service_action_pending)}</span>
      </div>

      <div
        :if={
          @service_state.under_systemd and @service_state.systemd_available and
            @service_state.unit_installed
        }
        class="space-y-3"
      >
        <div class="flex flex-wrap gap-2">
          <button
            :if={@service_state.active}
            type="button"
            phx-click="service_confirm"
            phx-value-action="restart"
            data-nav-item
            tabindex="0"
            disabled={@service_action_pending != nil}
            class="btn btn-soft btn-primary btn-sm"
          >
            <.icon name="hero-arrow-path-mini" class="size-4" /> Restart
          </button>
          <button
            :if={@service_state.active}
            type="button"
            phx-click="service_confirm"
            phx-value-action="stop"
            data-nav-item
            tabindex="0"
            disabled={@service_action_pending != nil}
            class="btn btn-soft btn-warning btn-sm"
          >
            <.icon name="hero-stop-mini" class="size-4" /> Stop
          </button>
        </div>

        <details class="release-notes-disclosure" open={@service_status_visible}>
          <summary
            phx-click="service_toggle_status"
            class="cursor-pointer text-xs text-base-content/50 hover:text-base-content/80 transition-colors inline-flex items-center gap-1.5 select-none"
          >
            <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
            <span>Show service details</span>
          </summary>
          <div class="mt-3">
            <pre
              :if={@service_status_output}
              class="glass-inset rounded-md p-3 text-[11px] font-mono text-base-content/80 overflow-x-auto thin-scrollbar max-h-80 overflow-y-auto whitespace-pre"
            ><%= @service_status_output %></pre>
            <p :if={!@service_status_output} class="text-xs text-base-content/40 italic">
              Loading…
            </p>
          </div>
        </details>
      </div>

      <p
        :if={
          @service_state.under_systemd and @service_state.systemd_available and
            not @service_state.unit_installed
        }
        class="text-sm text-base-content/60"
      >
        Running under systemd, but
        <code class="font-mono text-xs">{service_card_unit_name(@service_state)}</code>
        isn't listed by <code class="font-mono text-xs">systemctl --user list-unit-files</code>. That usually means the unit file was renamed or removed after this process started — try reinstalling with <code class="font-mono text-xs">
          ~/.local/lib/media-centarr/current/bin/media-centarr-install service install
        </code>.
      </p>

      <p
        :if={not @service_state.under_systemd and @service_state.systemd_available}
        class="text-sm text-base-content/60"
      >
        This BEAM wasn't started by systemd — start/stop/restart buttons aren't available here. Your user systemd session is reachable, so you can still manage a unit from a terminal: <code class="font-mono text-xs">systemctl --user status media-centarr.service</code>.
      </p>

      <p
        :if={not @service_state.under_systemd and not @service_state.systemd_available}
        class="text-sm text-base-content/60"
      >
        This install isn't running under a systemd user session — start/stop/restart buttons aren't available here. Use the terminal you started the app from, or a process manager of your choice.
      </p>
    </div>
    """
  end

  defp service_card_subtitle(%{under_systemd: true, unit_name: unit, active: true, enabled: true})
       when is_binary(unit), do: "Managed by systemd (#{unit}). Running and set to start on login."

  defp service_card_subtitle(%{under_systemd: true, unit_name: unit, active: true, enabled: false})
       when is_binary(unit), do: "Managed by systemd (#{unit}). Running, but not set to start on login."

  defp service_card_subtitle(%{under_systemd: true, unit_name: unit, active: false})
       when is_binary(unit), do: "Managed by systemd (#{unit}). Not running."

  defp service_card_subtitle(%{under_systemd: true, active: true, enabled: true}),
    do: "Managed by systemd. Running and set to start on login."

  defp service_card_subtitle(%{under_systemd: true, active: true, enabled: false}),
    do: "Managed by systemd. Running, but not set to start on login."

  defp service_card_subtitle(%{under_systemd: true, active: false}),
    do: "Managed by systemd. Not running."

  defp service_card_subtitle(%{systemd_available: false}), do: "Not running under systemd."

  defp service_card_subtitle(%{unit_installed: false}),
    do: "Started by hand — systemd user session is reachable but no matching unit is installed."

  defp service_card_subtitle(_),
    do: "Started by hand — systemd user session is reachable but this process isn't managed."

  defp service_card_unit_name(%{unit_name: unit}) when is_binary(unit), do: unit
  defp service_card_unit_name(_), do: "media-centarr.service"

  defp service_action_pending_label(:restarting),
    do: "Restarting — the page will disconnect for a moment and reconnect automatically."

  defp service_action_pending_label(:stopping),
    do: "Stopping — the page will disconnect once the service is down."

  defp service_state_badge_class(%{under_systemd: true, active: true}),
    do:
      "shrink-0 flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-success/10 text-success"

  defp service_state_badge_class(%{under_systemd: true, active: false}),
    do:
      "shrink-0 flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-warning/10 text-warning"

  defp service_state_badge_class(_),
    do:
      "shrink-0 flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-base-content/10 text-base-content/60"

  defp service_state_badge_icon(%{under_systemd: true, active: true}), do: "hero-check-circle-mini"
  defp service_state_badge_icon(%{under_systemd: true, active: false}), do: "hero-pause-circle-mini"
  defp service_state_badge_icon(_), do: "hero-minus-circle-mini"

  defp service_state_badge_text(%{under_systemd: true, active: true}), do: "Running"
  defp service_state_badge_text(%{under_systemd: true, active: false}), do: "Stopped"
  defp service_state_badge_text(_), do: "Unmanaged"

  defp overview_summary(0), do: "Configuration looks healthy."

  defp overview_summary(n), do: "#{n} #{if n == 1, do: "item needs", else: "items need"} your attention."

  defp overview_detail_class(:ok), do: "text-base-content/50"
  defp overview_detail_class(:neutral), do: "text-base-content/50"
  defp overview_detail_class(:warning), do: "text-warning"
  defp overview_detail_class(:error), do: "text-error"

  attr :status, :atom, required: true

  defp overview_status_icon(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center justify-center size-5 rounded-full shrink-0",
      @status == :ok && "bg-success/15 text-success",
      @status == :warning && "bg-warning/15 text-warning",
      @status == :error && "bg-error/15 text-error",
      @status == :neutral && "bg-base-content/10 text-base-content/60"
    ]}>
      <.icon :if={@status == :ok} name="hero-check-mini" class="size-3.5" />
      <.icon
        :if={@status in [:warning, :error]}
        name="hero-exclamation-triangle-mini"
        class="size-3.5"
      />
      <span :if={@status == :neutral} class="size-1.5 rounded-full bg-current"></span>
    </span>
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

  # --- Status indicators ---

  attr :configured, :boolean, required: true

  defp status_dot(assigns) do
    ~H"""
    <span
      class={[
        "size-2 rounded-full shrink-0",
        if(@configured, do: "bg-success", else: "bg-base-content/20")
      ]}
      aria-label={if @configured, do: "Configured", else: "Not configured"}
      title={if @configured, do: "Configured", else: "Not configured"}
    >
    </span>
    """
  end

  attr :path, :any, required: true
  attr :kind, :atom, required: true, values: [:file, :directory, :executable]

  defp path_status(assigns) do
    assigns = assign(assigns, :result, PathCheck.check(assigns.path, assigns.kind))

    # `-mini` variants at `size-3.5` match inline-badge convention used
    # elsewhere in the app (see the "All good" pill on the Health Check
    # card). Pairing a larger `-solid` glyph with `text-xs` mono made
    # the icon look stacked above the baseline.
    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center size-3.5 shrink-0 relative top-px",
        PathCheck.ok?(@result) && "text-success",
        !PathCheck.ok?(@result) && "text-warning"
      ]}
      title={if PathCheck.ok?(@result), do: "Found at #{@path}", else: PathCheck.label(@result)}
      aria-label={PathCheck.label(@result)}
    >
      <.icon
        :if={PathCheck.ok?(@result)}
        name="hero-check-circle-mini"
        class="size-3.5"
      />
      <.icon
        :if={!PathCheck.ok?(@result)}
        name="hero-exclamation-triangle-mini"
        class="size-3.5"
      />
    </span>
    """
  end

  attr :test, :any, required: true
  attr :ok_label, :string, required: true
  attr :error_label, :string, required: true

  defp connection_status(assigns) do
    status = if is_map(assigns.test), do: assigns.test.status

    age =
      if is_map(assigns.test),
        do: ConnectionTest.relative_age(assigns.test.tested_at)

    assigns = assign(assigns, status: status, age: age)

    ~H"""
    <div class="flex items-center gap-2 min-w-0 text-sm">
      <span class={[
        "size-2 rounded-full shrink-0",
        @status == :ok && "bg-success",
        @status == :error && "bg-error",
        is_nil(@status) && "bg-base-content/30"
      ]}>
      </span>
      <span class="min-w-0 truncate">
        <span class="text-base-content/70">
          {cond do
            @status == :ok -> @ok_label
            @status == :error -> @error_label
            true -> "Not tested"
          end}
        </span>
        <span :if={@age} class="text-base-content/40 text-xs">· {@age}</span>
      </span>
    </div>
    """
  end

  # --- Private helpers ---

  # Spawns a connection-test under TaskSupervisor and forwards the
  # `:ok | :error` result to the LiveView's mailbox under
  # `result_message`. Each save_* handler dispatches here when the form
  # was submitted with `_action=test`. The test runs against the values
  # the save handler just persisted, so a failing test never displaces
  # the user's typed-in input.
  defp spawn_test_task(result_message, fun) when is_atom(result_message) and is_function(fun, 0) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      send(parent, {result_message, fun.()})
    end)

    :ok
  end

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
      data_dir: cfg.get(:data_dir),
      watch_dirs: cfg.get(:watch_dirs) || []
    }
  end

  # Connection-test persistence is owned by `MediaCentarr.Capabilities`,
  # which also broadcasts to `Topics.capabilities_updates/0` so LiveViews
  # that gate UI on integration health can re-render. These local
  # wrappers exist so callsites in this module stay readable.

  defp load_test_result(subject), do: Capabilities.load_test_result(subject)
  defp save_test_result(subject, status), do: Capabilities.save_test_result(subject, status)
  defp clear_test_result(subject), do: Capabilities.clear_test_result(subject)

  defp persist_service_flag(service, value) do
    env = Application.get_env(:media_centarr, :environment, :dev)

    Settings.find_or_create_entry!(%{
      key: "services:#{env}:#{service}",
      value: %{"enabled" => value}
    })
  end

  # --- Watch-dir private helpers ---

  defp open_watch_dir_dialog(socket, entry) do
    assign(socket, :watch_dir_dialog, %{
      entry: entry,
      validation: %{errors: [], warnings: [], preview: nil},
      debounce_timer: nil
    })
  end

  defp close_watch_dir_dialog(socket) do
    assign(socket, :watch_dir_dialog, nil)
  end

  defp schedule_watch_dir_validation(socket, params) do
    case socket.assigns.watch_dir_dialog do
      %{debounce_timer: timer} = dialog ->
        if timer, do: Process.cancel_timer(timer)
        new_timer = Process.send_after(self(), {:watch_dir_validate, params}, 500)
        assign(socket, :watch_dir_dialog, %{dialog | debounce_timer: new_timer})

      _ ->
        socket
    end
  end

  defp merge_entry(old, params) do
    %{
      "id" => old["id"],
      "dir" => params["dir"] || old["dir"],
      "images_dir" => nilify(params["images_dir"]),
      "name" => nilify(params["name"])
    }
  end

  defp nilify(""), do: nil
  defp nilify(value), do: value

  defp other_entries(list, entry) do
    Enum.reject(list, &(&1["id"] == entry["id"]))
  end

  defp load_spoiler_free_setting do
    case Settings.get_by_key("spoiler_free_mode") do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end

  # --- Watch-dir function components ---

  attr :errors, :list, required: true
  attr :field, :atom, required: true

  defp watch_dir_errors(assigns) do
    ~H"""
    <div
      :for={
        err <-
          Enum.filter(@errors, fn
            {f, _} -> f == @field
            {f, _, _} -> f == @field
          end)
      }
      class="text-error text-sm"
    >
      {WatchDirsLogic.error_message(err)}
    </div>
    """
  end

  # --- Auto-grab defaults persistence ---

  defp persist_auto_grab_defaults(params) do
    Enum.each(
      [
        {"auto_grab.default_mode", params["default_mode"], :string},
        {"auto_grab.default_min_quality", params["default_min_quality"], :string},
        {"auto_grab.default_max_quality", params["default_max_quality"], :string},
        {"auto_grab.4k_patience_hours", params["4k_patience_hours"], :integer},
        {"auto_grab.max_attempts", params["max_attempts"], :integer}
      ],
      fn {key, raw, type} ->
        with value when value != nil <- coerce(raw, type) do
          MediaCentarr.Settings.find_or_create_entry!(%{key: key, value: %{"value" => value}})
        end
      end
    )
  end

  defp coerce(nil, _), do: nil
  defp coerce("", _), do: nil
  defp coerce(value, :string), do: value

  defp coerce(value, :integer) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end
end
