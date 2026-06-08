defmodule MediaCentaurWeb.SettingsLive do
  @moduledoc """
  Settings UI for editing the user's `media-centaur.toml` configuration.

  Renders editable rows for sensitive credentials (TMDB key, Prowlarr API
  key, qBittorrent login), service toggles (watchers, pipelines), and
  service start/stop actions. Persists changes by rewriting the TOML file
  on disk and broadcasting `Settings` updates.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LibraryCardInfoAware

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Capabilities, Config, SelfUpdate, Settings, Version}

  alias MediaCentaurWeb.Live.SettingsLive.{
    ConnectionTest,
    Overview,
    PathCheck,
    ReleaseNotes,
    SystemSection
  }

  alias MediaCentaur.Maintenance
  alias MediaCentaur.Acquisition
  alias MediaCentaur.Search.Prowlarr
  alias MediaCentaur.Downloads.DownloadClient.QBittorrent
  alias MediaCentaur.Watcher
  alias MediaCentaur.Pipeline
  alias MediaCentaur.Pipeline.Image, as: ImagePipeline
  alias MediaCentaurWeb.SettingsLive.WatchDirsLogic
  alias MediaCentaur.Controls
  alias MediaCentaur.Playback.{Iso639, LanguagePolicy}
  alias MediaCentaurWeb.SettingsLive.Controls, as: ControlsSection
  alias MediaCentaurWeb.SettingsLive.LanguageLogic

  # Sections are grouped for sidebar display — a thin divider renders between
  # adjacent items whose :group differs. Order within a group is by frequency
  # of user interaction: things you touch daily come first.
  @sections [
    # System is its own group so it sits alone above everything else.
    %{id: "system", label: "System", group: :system},
    %{id: "updates", label: "Updates", group: :system},
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
    %{id: "language", label: "Language", group: :media},
    %{id: "release_tracking", label: "Release Tracking", group: :media},
    # Infrastructure — rare-touch admin
    %{id: "danger", label: "Danger Zone", group: :infra}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # `Settings.subscribe()` is auto-wired by SpoilerFreeAware. The single
    # subscription delivers every `:setting_changed` message — the trait
    # handles the spoiler_free key via attach_hook, and this LiveView's
    # own handle_info/2 clauses handle the other keys.
    if connected?(socket) do
      Watcher.Supervisor.subscribe()
      SelfUpdate.subscribe()
      SelfUpdate.subscribe_progress()
      Config.subscribe()
      Controls.subscribe()
      # Coarse heartbeat so the "next check" estimate on the Updates card stays
      # roughly current without behaving like a per-second countdown. The
      # labels are hour-grained, so a 60s recompute is almost always a no-op
      # for morphdom.
      Process.send_after(self(), :refresh_update_schedule, 60_000)
    end

    {:ok,
     socket
     |> assign(loaded?: false)
     |> assign(setup_banner_dismissed?: false)
     |> assign(show_setup_banner?: false)
     |> assign(critical_failures: [])
     |> assign(config: %{})
     |> assign(watchers_running: false)
     |> assign(pipeline_running: false)
     |> assign(image_pipeline_running: false)
     |> assign(acquisition_running: false)
     |> assign(watch_dirs: [])
     |> assign(exclude_dirs: [])
     |> assign(missing_images_summary: %{total: 0, missing: 0, by_role: %{}})
     |> assign(tmdb_test: nil)
     |> assign(prowlarr_test: nil)
     |> assign(download_client_test: nil)
     |> assign(tmdb_missing: false)
     |> assign(
       service_state: %{
         under_systemd: false,
         unit_name: nil,
         systemd_available: false,
         unit_installed: false,
         active: false,
         enabled: false
       }
     )
     |> assign(bindings: %{})
     |> assign(glyph_style: nil)
     |> assign(
       sections: @sections,
       exclude_dir_input: "",
       exclude_dir_error: nil,
       watch_dir_dialog: nil,
       watch_dir_delete_confirm: nil,
       scanning: false,
       scan_task: nil,
       clearing_database: false,
       refreshing_images: false,
       repairing_images: false,
       refreshing_credits: false,
       refreshing_series_credits: false,
       refreshing_movie_subtitles: false,
       repair_last_result: nil,
       tmdb_testing: false,
       prowlarr_testing: false,
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
       service_action_confirm: nil,
       service_action_pending: nil,
       service_status_visible: false,
       service_status_output: nil,
       listening: nil
     )
     |> put_language_assigns()
     |> put_update_automation_assigns()}
  end

  # Seeds (and re-syncs) the update-automation controls: whether background
  # checking is on, the configured poll interval (clamped to the rate-limit
  # floor), whether auto-install is on, and the relative "last checked" label.
  defp put_update_automation_assigns(socket) do
    enabled = Config.get(:update_check_enabled)
    interval = Config.update_check_interval_minutes()
    last_check_at = SelfUpdate.last_check_at()
    now = DateTime.utc_now()

    assign(socket,
      update_check_enabled: enabled,
      auto_update_enabled: Config.get(:auto_update_enabled),
      update_check_interval_minutes: interval,
      update_check_interval_floor: Config.update_check_interval_floor_minutes(),
      last_checked_label: SystemSection.last_checked_label(last_check_at, now),
      update_schedule_label: SystemSection.update_schedule_label(enabled, interval, last_check_at, now)
    )
  end

  # Loads the saved language policy and seeds the picker's working state:
  # the draft list of understood-language codes (mutated live by the
  # add/remove/reorder events, persisted on save) and the selectable
  # language options. Re-called after a save to re-sync the draft.
  defp put_language_assigns(socket) do
    policy = LanguagePolicy.load()

    assign(socket,
      language_policy: policy,
      language_draft: policy.understood_languages,
      language_options: LanguageLogic.options()
    )
  end

  # The understood-languages picker is a live tag editor: each add /
  # remove / reorder persists immediately (no Save button), keeping the
  # saved policy and the draft assign in lock-step. The audio/subtitle
  # enums keep their own explicit Save.
  defp update_languages(socket, draft) do
    policy = %{socket.assigns.language_policy | understood_languages: draft}
    LanguagePolicy.save(policy)
    assign(socket, language_policy: policy, language_draft: draft)
  end

  @impl true
  def handle_params(%{"add_watch_dir" => "1"} = params, _uri, socket) do
    section = params["section"] || "library"

    socket =
      socket
      |> ensure_loaded()
      |> assign(active_section: section)
      |> assign_update_snapshot(section)
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
      |> ensure_loaded()
      |> assign(active_section: section)
      |> assign_update_snapshot(section)

    {:noreply, socket}
  end

  # First-render data load — runs on BOTH the disconnected (static) and
  # connected renders so the first paint already carries the settings state,
  # never an empty-state flash. Desktop first-paint correctness (see
  # AGENTS.md → LiveView callbacks): the ~15 reads (config, four `running?/0`
  # GenServer calls, image-health summary, systemd service-state probe,
  # connection-test reads, setup-banner probes) are all local, so there is
  # no traffic-scaling reason to defer them. Do not re-add a `connected?`
  # gate. No networked update-check runs on landing at all — the scheduled
  # `CheckerJob` is the single poller; the page only reads the cached
  # snapshot via `SelfUpdate.view_status/0` (a pure, side-effect-free read).
  defp ensure_loaded(socket) do
    if socket.assigns.loaded? do
      socket
    else
      socket
      |> load_settings()
      |> assign(loaded?: true)
    end
  end

  # Synchronous first-render load. Builds the full settings assign set from
  # local reads. The four `running?/0` probes are independent GenServer
  # calls (microseconds each); running them sequentially inline is cheap.
  defp load_settings(socket) do
    config = load_config()

    {critical_failures, show_setup_banner?} =
      compute_setup_banner_state(config, socket.assigns.setup_banner_dismissed?)

    assign(socket,
      config: config,
      watchers_running: Watcher.Supervisor.running?(),
      pipeline_running: Pipeline.Supervisor.pipeline_running?(),
      image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?(),
      acquisition_running: Acquisition.auto_grab_running?(),
      watch_dirs: MediaCentaur.Config.watch_dirs_entries(),
      exclude_dirs: MediaCentaur.Config.get(:exclude_dirs) || [],
      missing_images_summary: Maintenance.missing_images_summary(),
      tmdb_test: load_test_result(:tmdb),
      prowlarr_test: load_test_result(:prowlarr),
      download_client_test: load_test_result(:download_client),
      tmdb_missing: SystemSection.tmdb_key_missing?(Config.get(:tmdb_api_key)),
      service_state: SelfUpdate.service_state(),
      bindings: Controls.get(),
      glyph_style: Controls.glyph_style(),
      critical_failures: critical_failures,
      show_setup_banner?: show_setup_banner?
    )
  end

  # Renders the last-known update snapshot only — arriving on the page never
  # kicks a network poll. The scheduled `CheckerJob` is the single poller
  # (every 15 min, runtime-tunable); duplicating that on every landing was
  # redundant traffic. A fresh check is still one click away via the
  # "check_updates" event. `view_status/0` is a pure cache read.
  defp assign_update_snapshot(socket, "system") do
    if connected?(socket) do
      {status, release} = SelfUpdate.view_status()
      assign(socket, update_status: status, latest_release: release)
    else
      socket
    end
  end

  defp assign_update_snapshot(socket, _section), do: socket

  # Runs a check in a LiveView-owned task so the UI is *guaranteed* to resolve
  # via `handle_async/3`, independent of the `{:check_complete, …}` broadcast
  # that feeds AutoApply and other views. A worker→view PubSub gap previously
  # left the card stuck on "Checking…" with the check having silently succeeded.
  #
  # `:manual` is load-bearing: a user-pressed check must never auto-install,
  # even with auto-update on. It surfaces the available update here; the user
  # then presses Update deliberately. AutoApply ignores any non-`:scheduled`
  # source.
  defp start_update_check(socket) do
    socket
    |> start_async(:update_check, fn -> SelfUpdate.run_check(:manual) end)
    |> assign(update_status: :checking)
  end

  # --- Events ---

  @impl true
  def handle_event("check_updates", _params, socket) do
    {:noreply, start_update_check(socket)}
  end

  def handle_event("apply_update", _params, socket) do
    case SelfUpdate.apply_pending() do
      :ok ->
        # Flag the client eagerly — the instant apply starts, before any
        # progress frame. A fast apply (already-downloaded release) can restart
        # the BEAM before the first `{:progress, ...}` push_event reaches the
        # browser, which would leave the disconnect showing the red "Not
        # connected" toast instead of the calm "Applying update" one. Setting
        # the `<html>` flag here (it persists across live-navs until reconnect)
        # closes that race. The abort paths still clear it.
        {:noreply,
         socket
         |> assign(
           apply_phase: :preparing,
           apply_progress: nil,
           apply_error: nil,
           apply_failed_at: nil
         )
         |> flag_update_applying()}

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

  def handle_event("setup:dismiss_banner", _params, socket) do
    {:noreply,
     socket
     |> assign(setup_banner_dismissed?: true)
     |> assign_setup_banner_state()}
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
      :ok = MediaCentaur.Config.put_watch_dirs(entries)
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
    :ok = MediaCentaur.Config.put_watch_dirs(entries)
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
        :ok = MediaCentaur.Config.update(:exclude_dirs, new_list)

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
    :ok = MediaCentaur.Config.update(:exclude_dirs, new_list)
    {:noreply, assign(socket, :exclude_dirs, new_list)}
  end

  def handle_event("scan", _params, socket) do
    # Spawn the scan on a supervised Task so the LiveView stays responsive
    # and we can surface a Cancel button backed by Task.shutdown/2. A
    # synchronous call here would block the socket process — no render
    # could fire during the scan, so the "Scanning…" label would never
    # become visible.
    task =
      Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn ->
        MediaCentaur.Watcher.Supervisor.scan()
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
    Maintenance.clear_database_async(self())
    {:noreply, assign(socket, clearing_database: true)}
  end

  def handle_event("refresh_image_cache", _params, socket) do
    Maintenance.refresh_image_cache_async(self())
    {:noreply, assign(socket, refreshing_images: true)}
  end

  def handle_event("refresh_movie_credits", _params, socket) do
    Maintenance.refresh_movie_credits_async(self())
    {:noreply, assign(socket, refreshing_credits: true)}
  end

  def handle_event("refresh_series_credits", _params, socket) do
    Maintenance.refresh_series_credits_async(self())
    {:noreply, assign(socket, refreshing_series_credits: true)}
  end

  def handle_event("refresh_movie_subtitles", _params, socket) do
    Maintenance.refresh_movie_subtitles_async(self())
    {:noreply, assign(socket, refreshing_movie_subtitles: true)}
  end

  def handle_event("repair_missing_images", _params, socket) do
    Maintenance.repair_missing_images_async(self())
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

  def handle_event("toggle_acquisition", _params, socket) do
    if socket.assigns.acquisition_running do
      Acquisition.pause_auto_grab()
    else
      Acquisition.resume_auto_grab()
    end

    {:noreply, assign(socket, acquisition_running: Acquisition.auto_grab_running?())}
  end

  def handle_event("toggle_spoiler_free", _params, socket) do
    enabled = !socket.assigns.spoiler_free

    Settings.find_or_create_entry!(%{
      key: "spoiler_free_mode",
      value: %{"enabled" => enabled}
    })

    {:noreply, assign(socket, spoiler_free: enabled)}
  end

  def handle_event("toggle_show_card_info", _params, socket) do
    enabled = !socket.assigns.show_card_info

    Settings.find_or_create_entry!(%{
      key: MediaCentaur.LibraryCardInfo.setting_key(),
      value: %{"enabled" => enabled}
    })

    {:noreply, assign(socket, show_card_info: enabled)}
  end

  def handle_event("toggle_update_check", _params, socket) do
    Config.update(:update_check_enabled, !socket.assigns.update_check_enabled)
    {:noreply, put_update_automation_assigns(socket)}
  end

  def handle_event("toggle_auto_update", _params, socket) do
    Config.update(:auto_update_enabled, !socket.assigns.auto_update_enabled)
    {:noreply, put_update_automation_assigns(socket)}
  end

  def handle_event("save_update_interval", params, socket) do
    minutes =
      SystemSection.normalize_interval_minutes(
        params["interval_minutes"],
        socket.assigns.update_check_interval_floor,
        socket.assigns.update_check_interval_minutes
      )

    Config.update(:update_check_interval_minutes, minutes)

    {:noreply,
     socket
     |> put_update_automation_assigns()
     |> put_flash(:info, "Update check interval saved")}
  end

  # Save + Test share one form-submit handler per service. The Save and
  # Test buttons are both `type=submit` on the same form with
  # `name=_action value=save|test`. This means: every test starts by
  # persisting whatever the user typed in. If the test then fails, the
  # form re-renders against `@config` — which now matches the typed-in
  # values, so the user sees their input preserved instead of clobbered.
  # See `test/media_centaur_web/live/settings_live_acquisition_test.exs`.

  def handle_event("save_tmdb", params, socket) do
    if params["tmdb_api_key"] != "" do
      Config.update(:tmdb_api_key, params["tmdb_api_key"])
      MediaCentaur.TMDB.Client.invalidate_client()
      clear_test_result(:tmdb)

      # Recovery hook: a fresh key may unblock files that were stranded
      # by an earlier TMDB auth failure. Re-emit `:file_detected` for
      # any present watcher_files row with no library link so the
      # pipeline gets another chance.
      MediaCentaur.Watcher.Supervisor.rescan_unlinked_async()
    end

    case Float.parse(params["auto_approve_threshold"] || "") do
      {threshold, _} -> Config.update(:auto_approve_threshold, threshold)
      :error -> :ok
    end

    socket = assign(socket, config: load_config(), tmdb_test: load_test_result(:tmdb))

    case params["_action"] do
      "test" ->
        socket =
          start_async_test(socket, :tmdb_test_result, fn ->
            case MediaCentaur.TMDB.Client.configuration() do
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
        socket =
          start_async_test(socket, :prowlarr_test_result, fn ->
            case MediaCentaur.Acquisition.test_prowlarr() do
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
        socket =
          start_async_test(socket, :download_client_test_result, fn ->
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
    Acquisition.discover_download_clients_async(self())
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

  def handle_event("save_language_policy", params, socket) do
    # The understood-languages list is the live draft (the chip picker),
    # not a form field; the audio/subtitle enums come from the form.
    policy = %{
      LanguagePolicy.from_form(params)
      | understood_languages: socket.assigns.language_draft
    }

    case LanguagePolicy.save(policy) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_language_assigns()
         |> put_flash(:info, "Language & subtitle preferences saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't save language preferences")}
    end
  end

  def handle_event("add_language", %{"lang" => input}, socket) do
    {:noreply, update_languages(socket, LanguageLogic.add(socket.assigns.language_draft, input))}
  end

  def handle_event("remove_language", %{"code" => code}, socket) do
    {:noreply, update_languages(socket, LanguageLogic.remove(socket.assigns.language_draft, code))}
  end

  def handle_event("move_language_up", %{"code" => code}, socket) do
    {:noreply, update_languages(socket, LanguageLogic.move_up(socket.assigns.language_draft, code))}
  end

  def handle_event("move_language_down", %{"code" => code}, socket) do
    {:noreply, update_languages(socket, LanguageLogic.move_down(socket.assigns.language_draft, code))}
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
    if MediaCentaur.Capabilities.prowlarr_ready?() do
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

  def handle_info(
        {:movie_credits_refreshed, %{updated: updated, skipped: skipped, failed: failed}},
        socket
      ) do
    msg =
      cond do
        updated == 0 and failed == 0 ->
          "Movie credits already up to date — nothing to refresh."

        failed > 0 ->
          "Refreshed credits for #{updated} movie#{if updated == 1, do: "", else: "s"} " <>
            "(#{skipped} skipped, #{failed} failed)."

        true ->
          "Refreshed credits for #{updated} movie#{if updated == 1, do: "", else: "s"}" <>
            if(skipped > 0, do: " (#{skipped} already had credits).", else: ".")
      end

    {:noreply,
     socket
     |> assign(refreshing_credits: false)
     |> put_flash(:info, msg)}
  end

  def handle_info(
        {:series_credits_refreshed, %{updated: updated, skipped: skipped, failed: failed}},
        socket
      ) do
    msg =
      cond do
        updated == 0 and failed == 0 ->
          "Series credits already up to date — nothing to refresh."

        failed > 0 ->
          "Refreshed credits for #{updated} series " <>
            "(#{skipped} skipped, #{failed} failed)."

        true ->
          "Refreshed credits for #{updated} series" <>
            if(skipped > 0, do: " (#{skipped} already had credits).", else: ".")
      end

    {:noreply,
     socket
     |> assign(refreshing_series_credits: false)
     |> put_flash(:info, msg)}
  end

  def handle_info({:movie_subtitles_refreshed, %{updated: updated, skipped: skipped}}, socket) do
    msg =
      if updated == 0 do
        "No new subtitles detected — every movie file already had its tracks " <>
          "(or none were available)."
      else
        "Detected subtitles on #{updated} movie file#{if updated == 1, do: "", else: "s"}" <>
          if(skipped > 0, do: " (#{skipped} skipped).", else: ".")
      end

    {:noreply,
     socket
     |> assign(refreshing_movie_subtitles: false)
     |> put_flash(:info, msg)}
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

  # Watcher/pipeline state change — refresh service toggle states
  def handle_info({:dir_state_changed, _dir, _role, _state}, socket) do
    {:noreply,
     socket
     |> assign(watchers_running: Watcher.Supervisor.running?())
     |> assign(pipeline_running: Pipeline.Supervisor.pipeline_running?())
     |> assign(image_pipeline_running: ImagePipeline.Supervisor.pipeline_running?())}
  end

  def handle_info({:progress, :done, pct}, socket) do
    # A normal restart cycle — BEAM dies, systemd starts the new release,
    # LiveView reconnects — completes in 2-3 seconds. If the BEAM hasn't
    # died within 6s, the handoff didn't actually trigger a restart.
    # Surface a diagnostic panel instead of sitting on "Restarting the
    # service…" indefinitely.
    Process.send_after(self(), :apply_done_stuck, 6_000)

    {:noreply,
     socket
     |> assign(apply_phase: :done, apply_progress: pct)
     |> flag_update_applying()}
  end

  def handle_info({:progress, phase, pct}, socket) do
    {:noreply,
     socket
     |> assign(apply_phase: phase, apply_progress: pct)
     |> flag_update_applying()}
  end

  def handle_info({:apply_failed, reason}, socket) do
    # Preserve whatever phase was active when the failure arrived so
    # the phase-row timeline in the modal can mark the right step as
    # failed (rather than all of them being grey/pending).
    {:noreply,
     socket
     |> assign(
       apply_phase: :failed,
       apply_failed_at: socket.assigns.apply_phase,
       apply_error: reason
     )
     |> flag_update_aborted()}
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
     |> flag_update_aborted()
     |> put_flash(:info, "Update cancelled.")}
  end

  def handle_info(:apply_done_stuck, socket) do
    if socket.assigns.apply_phase == :done do
      {:noreply,
       socket
       |> assign(apply_phase: :done_stuck)
       |> flag_update_aborted()}
    else
      {:noreply, socket}
    end
  end

  # A check completed (scheduled or manual) — refresh the visible card. The card
  # only *displays* status here; the source matters to AutoApply, not the UI.
  def handle_info({:check_complete, {classification, release}, _source}, socket)
      when classification in [:update_available, :up_to_date, :ahead_of_release] do
    {:noreply,
     socket
     |> assign(update_status: classification, latest_release: release)
     |> put_update_automation_assigns()}
  end

  def handle_info({:check_complete, {:error, reason}, _source}, socket) do
    {:noreply, assign(socket, update_status: {:error, reason}, latest_release: nil)}
  end

  def handle_info({:check_started}, socket), do: {:noreply, socket}

  def handle_info(:refresh_update_schedule, socket) do
    Process.send_after(self(), :refresh_update_schedule, 60_000)
    {:noreply, put_update_automation_assigns(socket)}
  end

  def handle_info({:config_updated, :watch_dirs, entries}, socket) do
    {:noreply, assign(socket, :watch_dirs, entries)}
  end

  def handle_info({:watch_dir_validate, params}, socket) do
    case socket.assigns.watch_dir_dialog do
      %{} = dialog ->
        entry = merge_entry(dialog.entry, params)

        validation =
          MediaCentaur.Watcher.validate_dir(
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

  # Async result from `start_async_settings_load/1`. The task did all
  # the config / capability / probe work off the LV process; the only
  # cost on this process is the single `assign/2` call.
  def handle_info({:download_client_detect_result, {:ok, [first | _rest] = clients}}, socket) do
    # Stash detected values as a suggestion — do NOT persist. The URL
    # Prowlarr returns is correct from Prowlarr's perspective but is
    # often a Docker service name unreachable from this host. The user
    # reviews the form and clicks Save to commit. See ADR-037.
    detected = %{type: first.type, url: first.url, username: first.username}

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

  # --- Async results (owned via start_async/3, ADR-049) ---

  # Update check — guaranteed UI resolution. `{:error, reason}` must precede the
  # `{classification, release}` clause: the 2-tuple `{:error, reason}` would
  # otherwise bind as `classification = :error, release = reason`.
  @impl true
  def handle_async(:update_check, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(update_status: {:error, reason}, latest_release: nil)
     |> put_update_automation_assigns()}
  end

  def handle_async(:update_check, {:ok, {classification, release}}, socket) do
    {:noreply,
     socket
     |> assign(update_status: classification, latest_release: release)
     |> put_update_automation_assigns()}
  end

  def handle_async(:update_check, {:exit, reason}, socket) do
    Log.warning(:settings, "update check task exited — #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(update_status: {:error, :check_crashed})
     |> put_update_automation_assigns()}
  end

  def handle_async(:tmdb_test_result, {:ok, status}, socket) do
    info = save_test_result(:tmdb, status)
    {:noreply, assign(socket, tmdb_testing: false, tmdb_test: info)}
  end

  def handle_async(:prowlarr_test_result, {:ok, status}, socket) do
    info = save_test_result(:prowlarr, status)
    {:noreply, assign(socket, prowlarr_testing: false, prowlarr_test: info)}
  end

  def handle_async(:download_client_test_result, {:ok, status}, socket) do
    info = save_test_result(:download_client, status)
    {:noreply, assign(socket, download_client_testing: false, download_client_test: info)}
  end

  def handle_async(name, {:exit, reason}, socket) do
    Log.warning(:settings, "settings async #{inspect(name)} failed — #{inspect(reason)}")
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
    <Layouts.app
      flash={@flash}
      current_path="/settings"
      acquisition_ready={@acquisition_ready}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
    >
      <:overlays>
        <%!--
          Layout-level overlays. Rendered outside the page's spacing container
          so `space-y-4`'s margins don't fold into the fixed-position height
          calc and clip the backdrop. See `Layouts.app`'s `:overlays` doc.
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
          layer is kept warm.
        --%>
        <.watch_dir_dialog watch_dir_dialog={@watch_dir_dialog} watch_dirs={@watch_dirs} />
      </:overlays>
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
            language_policy={@language_policy}
            language_draft={@language_draft}
            language_options={@language_options}
            watchers_running={@watchers_running}
            pipeline_running={@pipeline_running}
            image_pipeline_running={@image_pipeline_running}
            acquisition_running={@acquisition_running}
            scanning={@scanning}
            config={@config}
            clearing_database={@clearing_database}
            refreshing_images={@refreshing_images}
            repairing_images={@repairing_images}
            refreshing_credits={@refreshing_credits}
            refreshing_series_credits={@refreshing_series_credits}
            refreshing_movie_subtitles={@refreshing_movie_subtitles}
            missing_images_summary={@missing_images_summary}
            spoiler_free={@spoiler_free}
            show_card_info={@show_card_info}
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
            update_check_enabled={@update_check_enabled}
            auto_update_enabled={@auto_update_enabled}
            update_check_interval_minutes={@update_check_interval_minutes}
            update_check_interval_floor={@update_check_interval_floor}
            last_checked_label={@last_checked_label}
            update_schedule_label={@update_schedule_label}
            tmdb_missing={@tmdb_missing}
            show_setup_banner?={@show_setup_banner?}
            critical_failures={@critical_failures}
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
    </Layouts.app>
    """
  end

  # --- Section router ---

  defp section_content(%{active_section: "updates"} = assigns) do
    ~H"""
    <div class="space-y-5">
      <div
        :if={not SelfUpdate.enabled?()}
        class="p-5 rounded-lg glass-surface text-sm text-base-content/60"
      >
        <h2 class="text-lg font-semibold text-base-content">Automatic updates</h2>
        <p class="mt-1">
          Automatic updates are inactive in dev builds — upgrade by rebuilding from source.
        </p>
      </div>

      <div :if={SelfUpdate.enabled?()} class="p-5 rounded-lg glass-surface space-y-5">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Automatic updates</h2>
          <p class="text-sm opacity-50 mt-0.5">
            Choose when Media Centaur checks for new versions and whether it installs them for you.
          </p>
        </div>
        <%!-- Checking for updates --%>
        <div class="space-y-2">
          <.settings_row
            label="Automatically check for updates"
            description="Poll GitHub for new releases in the background. Turn off to check only when you press Check for updates."
            checked={@update_check_enabled}
            event="toggle_update_check"
          />
          <div :if={@update_check_enabled} class="glass-inset rounded-lg p-3.5 space-y-3">
            <form phx-submit="save_update_interval" class="flex items-center gap-2.5 text-sm">
              <label for="update-check-interval" class="text-base-content/70">Check every</label>
              <input
                id="update-check-interval"
                type="number"
                name="interval_minutes"
                value={@update_check_interval_minutes}
                min={@update_check_interval_floor}
                step="1"
                class="input input-bordered input-sm w-20 font-mono text-sm"
                data-nav-item
                tabindex="0"
              />
              <span class="text-base-content/70">minutes</span>
              <.button
                variant="neutral"
                size="sm"
                type="submit"
                class="ml-1"
                data-nav-item
                tabindex="0"
              >
                Save
              </.button>
            </form>
            <p class="text-xs text-base-content/50 leading-relaxed">
              Media Centaur asks the GitHub Releases API whether a newer version exists. GitHub
              allows about 60 unauthenticated requests an hour from your network, so checking more
              often than every {@update_check_interval_floor} minutes risks temporary rate-limiting
              with no benefit — releases are infrequent.
            </p>
            <p class="text-xs text-base-content/40">{@last_checked_label}</p>
          </div>
        </div>

        <%!-- Installing updates --%>
        <div class="space-y-2">
          <.settings_row
            label="Install updates automatically"
            description="When a new version is found, download and install it without asking — the app restarts to finish."
            checked={@auto_update_enabled}
            event="toggle_auto_update"
          />
          <p class="text-xs text-base-content/50 leading-relaxed px-3.5">
            If something is playing, the update waits until playback ends, so your session is never
            interrupted. Leave this off to review the release and press Update now yourself.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp section_content(%{active_section: "system"} = assigns) do
    groups =
      if assigns.config == %{} do
        []
      else
        Overview.build(%{
          watchers_running: assigns.watchers_running,
          pipeline_running: assigns.pipeline_running,
          image_pipeline_running: assigns.image_pipeline_running,
          acquisition_running: assigns.acquisition_running,
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
          alt="Media Centaur"
          width="96"
          height="96"
          class="h-24 w-24 shrink-0 object-contain centaur-logo"
        />
        <div class="min-w-0 space-y-1.5">
          <h2 class="text-xl font-semibold tracking-tight">Media Centaur</h2>
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
            <p class="text-xs text-base-content/50 mt-1.5">{@update_schedule_label}</p>
          </div>
          <.button
            variant="secondary"
            size="sm"
            class="shrink-0"
            phx-click="check_updates"
            disabled={@update_status == :checking}
            data-nav-item
            tabindex="0"
          >
            {if @update_status == :checking, do: "Checking…", else: "Check for updates"}
          </.button>
        </div>

        <div :if={@update_status != :idle} class="mt-4 pt-4 border-t border-base-content/10">
          <p class={"text-sm #{update_tone_class(SystemSection.update_status_tone(@update_status))}"}>
            {SystemSection.update_status_label(@update_status, @latest_release)}
          </p>
          <div
            :if={@update_status == :update_available and @latest_release}
            class="flex items-center gap-3 mt-2"
          >
            <.button
              variant="primary"
              size="sm"
              phx-click="apply_update"
              disabled={@apply_phase != nil}
              data-nav-item
              tabindex="0"
            >
              Update now
            </.button>
          </div>

          <div
            :if={@latest_release && SystemSection.show_release_notes?(@update_status)}
            class="mt-3 pt-3 border-t border-base-content/10"
          >
            <div class="text-sm text-base-content/70 mb-3">
              What's new in {@latest_release.tag}
            </div>
            <div class="space-y-2">
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
          </div>

          <details
            :if={SystemSection.show_terminal_recovery?(@update_status)}
            class="release-notes-disclosure mt-2"
          >
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
                  <.button
                    id="copy-terminal-update"
                    variant="dismiss"
                    size="xs"
                    class="shrink-0"
                    phx-hook="CopyButton"
                    data-copy-text={SystemSection.terminal_recovery_command()}
                    data-nav-item
                    tabindex="0"
                  >
                    Copy
                  </.button>
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
                  <.button
                    id="copy-terminal-force"
                    variant="dismiss"
                    size="xs"
                    class="shrink-0"
                    phx-hook="CopyButton"
                    data-copy-text={SystemSection.force_recovery_command()}
                    data-nav-item
                    tabindex="0"
                  >
                    Copy
                  </.button>
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
                  <.button
                    id="copy-terminal-bootstrap"
                    variant="dismiss"
                    size="xs"
                    class="shrink-0"
                    phx-hook="CopyButton"
                    data-copy-text={SystemSection.bootstrap_install_command()}
                    data-nav-item
                    tabindex="0"
                  >
                    Copy
                  </.button>
                </div>
              </div>
            </div>
          </details>
        </div>

        <div class="mt-4 pt-4 border-t border-base-content/10">
          <p class="text-xs text-base-content/50 leading-relaxed">
            Updates are published on GitHub. Media Centaur downloads, verifies, and installs each
            release in place and then restarts to finish — usually under a minute, and your library
            and settings are preserved. Choose how often it checks and whether it installs new
            versions on its own under <.link
              navigate={~p"/settings?section=updates"}
              class="link link-primary"
            >Updates</.link>.
          </p>
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
        <.button
          variant="primary"
          size="sm"
          class="shrink-0"
          navigate={~p"/settings?section=tmdb"}
          data-nav-item
        >
          Add key
        </.button>
      </div>

      <div
        :if={@show_setup_banner?}
        class="p-4 rounded-lg border border-error/30 bg-error/10 text-sm flex items-start justify-between gap-4"
      >
        <div>
          <p class="font-medium">
            Setup is incomplete: {Enum.map_join(
              @critical_failures,
              ", ",
              &(&1.id |> Atom.to_string() |> String.replace("_", " "))
            )}
          </p>
          <p class="text-base-content/70 mt-0.5">
            One or more required dependencies aren't working. Run the setup tour to fix them.
          </p>
        </div>
        <div class="flex gap-2 shrink-0">
          <.button
            variant="primary"
            size="sm"
            navigate={~p"/setup"}
            data-nav-item
          >
            Run tour
          </.button>
          <.button
            variant="dismiss"
            size="sm"
            phx-click="setup:dismiss_banner"
            data-nav-item
          >
            Dismiss
          </.button>
        </div>
      </div>

      <div class="p-5 rounded-lg glass-surface">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Health Check</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              {overview_summary(@issue_count)}
            </p>
          </div>
          <div class="shrink-0 flex items-center gap-2">
            <.button
              variant="dismiss"
              size="xs"
              navigate={~p"/setup"}
              data-nav-item
            >
              Run setup tour
            </.button>
            <div
              :if={@issue_count > 0}
              class="flex items-center gap-2 text-xs font-medium px-2.5 py-1 rounded-full bg-warning/10 text-warning"
            >
              <.icon name="hero-exclamation-triangle-mini" class="size-3.5" />
              {@issue_count} {if @issue_count == 1, do: "issue", else: "issues"}
            </div>
            <div
              :if={@issue_count == 0 and @config != %{}}
              class="flex items-center gap-2 text-xs font-medium px-2.5 py-1 rounded-full bg-success/10 text-success"
            >
              <.icon name="hero-check-circle-mini" class="size-3.5" /> All good
            </div>
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
        <.settings_row
          label="Auto-grab"
          description="Search and grab releases as tracked episodes air"
          checked={@acquisition_running}
          event="toggle_acquisition"
          color="info"
        />
      </div>

      <div class="mt-4 pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
        <p class="text-xs text-base-content/50 min-w-0">
          Manually scan all watch directories for new media files.
        </p>
        <div class="flex items-center gap-2 shrink-0">
          <.button
            :if={@scanning}
            variant="dismiss"
            size="sm"
            phx-click="cancel_scan"
            data-nav-item
            tabindex="0"
          >
            Cancel
          </.button>
          <.button
            variant="action"
            size="sm"
            phx-click="scan"
            disabled={@scanning}
            data-nav-item
            tabindex="0"
          >
            <span :if={@scanning} class="loading loading-spinner loading-xs"></span>
            {if @scanning, do: "Scanning…", else: "Scan now"}
          </.button>
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
        <.button
          type="submit"
          variant="secondary"
          size="sm"
          class="shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </.button>
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
        <.button
          type="submit"
          variant="neutral"
          size="sm"
          class="shrink-0"
          name="_action"
          value="test"
          disabled={@tmdb_testing}
          data-nav-item
          tabindex="0"
        >
          <span :if={@tmdb_testing} class="loading loading-spinner loading-xs"></span>
          <.icon :if={!@tmdb_testing} name="hero-signal-mini" class="size-4" />
          {if @tmdb_testing, do: "Testing…", else: "Test connection"}
        </.button>
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
        download_client_display: download_client_display,
        prowlarr_ready: MediaCentaur.Capabilities.prowlarr_ready?(),
        auto_grab: MediaCentaur.Acquisition.AutoGrabSettings.load()
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
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
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
          <.button
            type="submit"
            variant="neutral"
            size="sm"
            class="shrink-0"
            name="_action"
            value="test"
            disabled={@prowlarr_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@prowlarr_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@prowlarr_testing} name="hero-signal-mini" class="size-4" />
            {if @prowlarr_testing, do: "Testing…", else: "Test connection"}
          </.button>
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
            <.button
              variant="neutral"
              size="sm"
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
            </.button>
            <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
              Save
            </.button>
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
          <.button
            type="submit"
            variant="neutral"
            size="sm"
            class="shrink-0"
            name="_action"
            value="test"
            disabled={@download_client_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@download_client_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@download_client_testing} name="hero-signal-mini" class="size-4" />
            {if @download_client_testing, do: "Testing…", else: "Test connection"}
          </.button>
        </div>
      </form>

      <.auto_grab_defaults_form :if={@prowlarr_ready} auto_grab={@auto_grab} />
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
        <.button
          type="submit"
          variant="secondary"
          size="sm"
          class="shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </.button>
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
    <div class="space-y-4">
      <form phx-submit="save_playback" class="p-5 rounded-lg glass-surface space-y-5">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Playback</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              MPV player configuration.
            </p>
          </div>
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
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
    </div>
    """
  end

  defp section_content(%{active_section: "language"} = assigns) do
    ~H"""
    <div class="space-y-4">
      <form phx-submit="add_language" class="p-5 rounded-lg glass-surface space-y-4">
        <div>
          <h2 class="text-lg font-semibold">Languages you understand</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Add the languages you can follow without subtitles, most-preferred first.
            Used to pick audio you understand and which language to show subtitles in.
            Changes here save automatically.
          </p>
        </div>

        <div class="flex gap-2">
          <input
            type="text"
            name="lang"
            list="language-options"
            class="input input-bordered flex-1 text-sm"
            placeholder="Add a language…"
            autocomplete="off"
            data-nav-item
            tabindex="0"
          />
          <datalist id="language-options">
            <option :for={{_code, name} <- @language_options} value={name}></option>
          </datalist>
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            Add
          </.button>
        </div>

        <ol :if={@language_draft != []} class="space-y-2">
          <li
            :for={{code, index} <- Enum.with_index(@language_draft)}
            id={"understood-lang-#{code}"}
            class="flex items-center gap-2 glass-inset rounded-lg px-3 py-2"
          >
            <span class="w-5 text-xs tabular-nums text-base-content/40">{index + 1}</span>
            <span class="flex-1 text-sm">{Iso639.display_name(code)}</span>
            <.button
              type="button"
              variant="dismiss"
              size="xs"
              phx-click="move_language_up"
              phx-value-code={code}
              disabled={index == 0}
              data-nav-item
              tabindex="0"
              aria-label={"Move #{Iso639.display_name(code)} up"}
            >
              <.icon name="hero-chevron-up-mini" class="size-4" />
            </.button>
            <.button
              type="button"
              variant="dismiss"
              size="xs"
              phx-click="move_language_down"
              phx-value-code={code}
              disabled={index == length(@language_draft) - 1}
              data-nav-item
              tabindex="0"
              aria-label={"Move #{Iso639.display_name(code)} down"}
            >
              <.icon name="hero-chevron-down-mini" class="size-4" />
            </.button>
            <.button
              type="button"
              variant="destructive_inline"
              size="xs"
              phx-click="remove_language"
              phx-value-code={code}
              data-nav-item
              tabindex="0"
              aria-label={"Remove #{Iso639.display_name(code)}"}
            >
              <.icon name="hero-x-mark-mini" class="size-4" />
            </.button>
          </li>
        </ol>
        <p :if={@language_draft == []} class="text-sm text-base-content/40">
          No languages added yet — subtitles will always be shown until you add one.
        </p>
      </form>

      <form phx-submit="save_language_policy" class="p-5 rounded-lg glass-surface space-y-5">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Audio &amp; subtitles</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              How tracks are picked automatically when playback starts. Per-show overrides
              (set by changing tracks during playback) always win over these.
            </p>
          </div>
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
        </div>

        <div class="space-y-4">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Audio preference
            </label>
            <select
              name="audio_priority"
              class="select select-bordered w-full text-sm"
              data-nav-item
              tabindex="0"
            >
              <option
                value="original_first"
                selected={LanguagePolicy.audio_priority_preset(@language_policy) == "original_first"}
              >
                Original language first (subtitles do the work)
              </option>
              <option
                value="understood_first"
                selected={
                  LanguagePolicy.audio_priority_preset(@language_policy) == "understood_first"
                }
              >
                My languages first (prefer dubs)
              </option>
              <option
                value="any"
                selected={LanguagePolicy.audio_priority_preset(@language_policy) == "any"}
              >
                No preference (whatever the file defaults to)
              </option>
            </select>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Show subtitles
              </label>
              <select
                name="subtitles_when"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="off" selected={@language_policy.subtitles_when == "off"}>
                  Never
                </option>
                <option
                  value="when_audio_not_understood"
                  selected={@language_policy.subtitles_when == "when_audio_not_understood"}
                >
                  Only when I don't understand the audio
                </option>
                <option value="always" selected={@language_policy.subtitles_when == "always"}>
                  Always
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Subtitle language
              </label>
              <select
                name="subtitles_language"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option
                  value="understood"
                  selected={@language_policy.subtitles_language == "understood"}
                >
                  One of my languages
                </option>
                <option
                  value="audio_language"
                  selected={@language_policy.subtitles_language == "audio_language"}
                >
                  Match the audio (language learning)
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Subtitle style
              </label>
              <select
                name="subtitles_variant"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="standard" selected={@language_policy.subtitles_variant == "standard"}>
                  Standard
                </option>
                <option
                  value="sdh_preferred"
                  selected={@language_policy.subtitles_variant == "sdh_preferred"}
                >
                  Prefer SDH (deaf / hard-of-hearing)
                </option>
              </select>
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Forced subtitles
              </label>
              <select
                name="forced_subs"
                class="select select-bordered w-full text-sm"
                data-nav-item
                tabindex="0"
              >
                <option value="never" selected={@language_policy.forced_subs == "never"}>
                  Never
                </option>
                <option value="fill_gaps" selected={@language_policy.forced_subs == "fill_gaps"}>
                  Fill gaps (foreign-dialog scenes)
                </option>
                <option value="always" selected={@language_policy.forced_subs == "always"}>
                  Always
                </option>
              </select>
            </div>
          </div>
        </div>
      </form>
    </div>
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
          <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
            Save
          </.button>
        </div>

        <p class="text-xs text-base-content/50">
          Where Media Centaur stores its caches outside the watch directories —
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
          <.button
            variant="action"
            size="sm"
            phx-click="watch_dir:open_add"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-plus" class="size-4" /> Add
          </.button>
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
              <.button
                variant="dismiss"
                size="sm"
                phx-click="watch_dir:open_edit"
                phx-value-id={entry["id"]}
                aria-label="Edit watch directory"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </.button>
              <%= if @watch_dir_delete_confirm == entry["id"] do %>
                <.button
                  variant="danger"
                  size="sm"
                  phx-click="watch_dir:delete"
                  phx-value-id={entry["id"]}
                  data-nav-item
                  tabindex="0"
                >
                  Confirm
                </.button>
                <.button
                  variant="dismiss"
                  size="sm"
                  phx-click="watch_dir:delete_cancel"
                  data-nav-item
                  tabindex="0"
                >
                  Cancel
                </.button>
              <% else %>
                <.button
                  variant="destructive_inline"
                  size="sm"
                  phx-click="watch_dir:delete_confirm"
                  phx-value-id={entry["id"]}
                  aria-label="Remove watch directory"
                  data-nav-item
                  tabindex="0"
                >
                  <.icon name="hero-trash" class="size-4" />
                </.button>
              <% end %>
            </div>
          </li>
        </ul>

        <div class="mt-1 pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <p class="text-xs text-base-content/50 min-w-0">
            Moved or added files? Scan to pick them up now. Files that moved to a
            new directory are re-linked to their existing library entry automatically.
          </p>
          <div class="flex items-center gap-2 shrink-0">
            <.button
              :if={@scanning}
              variant="dismiss"
              size="sm"
              phx-click="cancel_scan"
              data-nav-item
              tabindex="0"
            >
              Cancel
            </.button>
            <.button
              variant="action"
              size="sm"
              phx-click="scan"
              disabled={@scanning}
              data-nav-item
              tabindex="0"
            >
              <span :if={@scanning} class="loading loading-spinner loading-xs"></span>
              {if @scanning, do: "Scanning…", else: "Scan now"}
            </.button>
          </div>
        </div>
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
            <.button
              variant="destructive_inline"
              size="sm"
              class="shrink-0"
              phx-click="exclude_dir:delete"
              phx-value-path={path}
              data-confirm={"Remove #{path} from excluded directories?"}
              aria-label="Remove excluded directory"
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
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
            <.button
              type="submit"
              variant="action"
              size="sm"
              class="shrink-0"
              disabled={exclude_dir_add_disabled?(@exclude_dir_input, @exclude_dir_error)}
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-plus" class="size-4" /> Add
            </.button>
          </div>
          <p :if={is_binary(@exclude_dir_error)} class="text-error text-xs">
            {@exclude_dir_error}
          </p>
        </form>
      </div>

      <div data-nav-grid class="p-5 rounded-lg glass-surface">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Library display</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              How library entries appear in the poster grid.
            </p>
          </div>
        </div>

        <div class="mt-4 space-y-0.5">
          <.settings_row
            label="Show titles below posters"
            description="Hide for a clean wall-of-posters view."
            checked={@show_card_info}
            event="toggle_show_card_info"
            color="info"
          />
        </div>
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
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
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
    ~H"""
    <form phx-submit="save_release_tracking" class="p-5 rounded-lg glass-surface space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Release Tracking</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            How often to poll TMDB for upcoming release dates.
          </p>
        </div>
        <.button
          type="submit"
          variant="secondary"
          size="sm"
          class="shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </.button>
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
                <.badge
                  :if={@missing_images_summary.missing > 0}
                  variant="warning"
                  class="ml-2"
                >
                  {@missing_images_summary.missing} missing
                </.badge>
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
            <.button
              variant="neutral"
              size="sm"
              class="shrink-0"
              phx-click="repair_missing_images"
              disabled={@repairing_images or @missing_images_summary.missing == 0}
              data-nav-item
              tabindex="0"
            >
              {if @repairing_images, do: "Repairing…", else: "Repair"}
            </.button>
          </div>

          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">Refresh movie credits</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Backfills cast, crew (director, writers, composer), and IMDb ids for movies imported before those fields existed. Skips movies that already have credits — safe to re-run.
              </p>
            </div>
            <.button
              variant="neutral"
              size="sm"
              class="shrink-0"
              phx-click="refresh_movie_credits"
              disabled={@refreshing_credits}
              data-nav-item
              tabindex="0"
            >
              {if @refreshing_credits, do: "Refreshing…", else: "Refresh"}
            </.button>
          </div>

          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">Refresh series credits</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Backfills creators, aggregate cast, and IMDb ids for TV series imported before those fields existed. Skips series that already have credits — safe to re-run.
              </p>
            </div>
            <.button
              variant="neutral"
              size="sm"
              class="shrink-0"
              phx-click="refresh_series_credits"
              disabled={@refreshing_series_credits}
              data-nav-item
              tabindex="0"
            >
              {if @refreshing_series_credits, do: "Refreshing…", else: "Refresh"}
            </.button>
          </div>

          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">Refresh movie subtitles</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Detects subtitle tracks (embedded streams via ffprobe + sidecar files) for movies imported before subtitle detection shipped. Skips files that already have tracks — safe to re-run.
              </p>
            </div>
            <.button
              variant="neutral"
              size="sm"
              class="shrink-0"
              phx-click="refresh_movie_subtitles"
              disabled={@refreshing_movie_subtitles}
              data-nav-item
              tabindex="0"
            >
              {if @refreshing_movie_subtitles, do: "Refreshing…", else: "Refresh"}
            </.button>
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
            <.button
              variant="danger"
              size="sm"
              class="shrink-0"
              phx-click="clear_database"
              disabled={@clearing_database}
              data-confirm="This will permanently delete ALL entities, files, images, and progress. This cannot be undone. Continue?"
              data-nav-item
              tabindex="0"
            >
              {if @clearing_database, do: "Clearing…", else: "Clear"}
            </.button>
          </div>

          <div class="flex items-start justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium">Refresh image cache</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Deletes all cached artwork and re-downloads from TMDB. May take a while.
              </p>
            </div>
            <.button
              variant="risky"
              size="sm"
              class="shrink-0"
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
            >
              {if @refreshing_images, do: "Refreshing…", else: "Refresh"}
            </.button>
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

  defp update_tone_class(tone), do: SystemSection.tone_class(tone)

  # The self-update reboot kills the BEAM, so the disconnect toast that
  # follows is rendered entirely client-side — by then there is no server
  # to relabel it. We instead flip a client flag (`data-update-applying`
  # on <html>, see app.js) *while the update runs*, so the client can swap
  # the red "Not connected to server" toast for a calm "Applying update"
  # one. `flag_update_aborted/1` clears it again on failure/stall/cancel so
  # a genuine later disconnect still shows the red toast.
  defp flag_update_applying(socket), do: push_event(socket, "mc:update:applying", %{})
  defp flag_update_aborted(socket), do: push_event(socket, "mc:update:aborted", %{})

  # One row in the apply-progress modal's phase list. Renders an icon
  # reflecting the phase's state (pending / active / done / failed), a
  # label, and — for the downloading phase specifically — an inline
  # progress bar that animates as `@progress` changes.
  attr :phase, :atom, required: true
  attr :current, :atom, required: true
  attr :failed_at, :atom, default: nil

  attr :progress, :any,
    default: nil,
    doc:
      "transient downloading-phase progress: `nil` or `%{percent: 0..100, bytes: integer(), total: integer()}`. Heterogeneous nil-or-map shape; `:any` is intentional."

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

  attr :apply_progress, :any,
    default: nil,
    doc: "transient apply-phase progress — same shape as `:progress` on `apply_phase_row/1`."

  attr :apply_error, :any,
    default: nil,
    doc:
      "transient apply-phase error: `nil`, a string message, or `%{stage: atom, message: string}`. Heterogeneous shape; `:any` is intentional."

  attr :apply_failed_at, :atom, default: nil

  attr :latest_release, :map,
    default: nil,
    doc:
      "the GitHub release map fetched by `MediaCentaur.SelfUpdate.latest_release/0` — keys vary; treat as an opaque struct, not a typed shape."

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
          :if={SystemSection.apply_cancelable?(@apply_phase) or @apply_phase in [:handing_off, :done]}
          class="flex justify-end pt-2"
        >
          <.button
            :if={SystemSection.apply_cancelable?(@apply_phase)}
            variant="dismiss"
            size="sm"
            phx-click="cancel_update"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-x-mark-mini" class="size-4" /> Cancel update
          </.button>
          <%!-- Once the install/restart begins the cancel option is gone, but
                we keep the slot occupied with a disabled spinner so the user
                sees that work is still happening while the BEAM restarts. --%>
          <.button
            :if={@apply_phase in [:handing_off, :done]}
            variant="dismiss"
            size="sm"
            class="pointer-events-none"
            disabled
            tabindex="-1"
            aria-live="polite"
          >
            <span class="loading loading-spinner loading-xs"></span> Installing…
          </.button>
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
              <.button
                id="copy-terminal-recovery"
                variant="dismiss"
                size="xs"
                class="shrink-0"
                phx-hook="CopyButton"
                data-copy-text={SystemSection.terminal_recovery_command()}
                data-nav-item
                tabindex="0"
              >
                Copy
              </.button>
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
              systemctl --user restart media-centaur
            </code>
            <.button
              id="copy-stuck-restart"
              variant="dismiss"
              size="xs"
              class="shrink-0"
              phx-hook="CopyButton"
              data-copy-text="systemctl --user restart media-centaur"
              data-nav-item
              tabindex="0"
            >
              Copy
            </.button>
          </div>
        </div>

        <div
          :if={@apply_phase in [:failed, :done_stuck]}
          class="flex justify-end gap-2 pt-2"
        >
          <.button
            variant="dismiss"
            size="sm"
            phx-click="dismiss_apply_modal"
            data-nav-item
            tabindex="0"
          >
            Close
          </.button>
          <.button
            :if={@apply_phase == :failed}
            variant="primary"
            size="sm"
            phx-click="apply_update"
            data-nav-item
            tabindex="0"
          >
            Retry
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # Service action confirmation modal. Always in DOM; opens when
  # `@action` is set to "restart" or "stop". Destructive actions get an
  # amber soft button; restart (recoverable) gets primary.
  attr :action, :any,
    default: nil,
    doc:
      ~s(the pending service action — `nil`, `"restart"`, or `"stop"`. String-or-nil shape; `:any` keeps the door open for future tagged variants.)

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
          <.button
            variant="dismiss"
            size="sm"
            phx-click="service_cancel"
            data-nav-item
            tabindex="0"
          >
            Cancel
          </.button>
          <.button
            variant={service_confirm_button_variant(@action)}
            size="sm"
            phx-click="service_execute"
            phx-value-action={@action || ""}
            data-nav-item
            tabindex="0"
          >
            {service_confirm_cta(@action)}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :watch_dir_dialog, :any,
    default: nil,
    doc:
      "transient watch-directory dialog state — `nil` or `%{mode: :add | :remove, path: String.t()}`. Heterogeneous nil-or-map shape; `:any` is intentional."

  attr :watch_dirs, :list,
    default: [],
    doc: "list of configured watch directory paths (strings)."

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
        <.button
          variant="dismiss"
          size="sm"
          shape="circle"
          class="absolute top-3 right-3 z-10"
          phx-click="watch_dir:close"
          aria-label="Close"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </.button>

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
            <.button variant="dismiss" phx-click="watch_dir:close">
              Cancel
            </.button>
            <.button
              type="submit"
              variant="primary"
              disabled={not WatchDirsLogic.saveable?(@watch_dir_dialog.validation)}
            >
              Save
            </.button>
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
      "The app will stop. You'll need to start it again manually (systemctl --user start media-centaur) to bring it back."

  defp service_confirm_body(_), do: ""

  defp service_confirm_cta("restart"), do: "Restart"
  defp service_confirm_cta("stop"), do: "Stop"
  defp service_confirm_cta(_), do: ""

  defp service_confirm_button_variant("restart"), do: "primary"
  defp service_confirm_button_variant("stop"), do: "risky"
  defp service_confirm_button_variant(_), do: "neutral"

  # Inline Service card — rendered inside the overview section.
  attr :service_state, :map,
    required: true,
    doc:
      "service status map from `MediaCentaur.SystemControl.service_state/0` — keys: `:installed?`, `:active?`, `:enabled?`, `:loaded?`, etc. Treated as opaque shape."

  attr :service_status_visible, :boolean, default: false

  attr :service_status_output, :any,
    default: nil,
    doc: "raw `systemctl status` output string, or `nil` when not yet fetched."

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
          <.button
            :if={@service_state.active}
            variant="secondary"
            size="sm"
            phx-click="service_confirm"
            phx-value-action="restart"
            data-nav-item
            tabindex="0"
            disabled={@service_action_pending != nil}
          >
            <.icon name="hero-arrow-path-mini" class="size-4" /> Restart
          </.button>
          <.button
            :if={@service_state.active}
            variant="risky"
            size="sm"
            phx-click="service_confirm"
            phx-value-action="stop"
            data-nav-item
            tabindex="0"
            disabled={@service_action_pending != nil}
          >
            <.icon name="hero-stop-mini" class="size-4" /> Stop
          </.button>
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
          ~/.local/lib/media-centaur/current/bin/media-centaur-install service install
        </code>.
      </p>

      <p
        :if={not @service_state.under_systemd and @service_state.systemd_available}
        class="text-sm text-base-content/60"
      >
        This BEAM wasn't started by systemd — start/stop/restart buttons aren't available here. Your user systemd session is reachable, so you can still manage a unit from a terminal: <code class="font-mono text-xs">systemctl --user status media-centaur.service</code>.
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
  defp service_card_unit_name(_), do: "media-centaur.service"

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

  attr :label, :any,
    required: true,
    doc: "label content — accepts a string or a HEEx slot/AST. `:any` covers both."

  attr :description, :string, required: true
  attr :checked, :boolean, required: true
  attr :event, :string, required: true
  attr :event_value, :map, default: %{}, doc: "phx-value-* params map (string-keyed)."
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

  attr :path, :any,
    required: true,
    doc:
      "path string OR a `{label, path}` tuple — `PathCheck.check/2` accepts both forms. `:any` covers the union."

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

  attr :test, :any,
    required: true,
    doc:
      "connection test result — `nil`, `%{status: :ok | :error, tested_at: DateTime.t(), ...}`, or atom shorthand. Heterogeneous shape; `:any` is intentional."

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

  # Computes the probe-driven setup banner state and assigns
  # `critical_failures` + `show_setup_banner?`. Called after any config
  # save — probes are pure (config + filesystem) so cost is negligible.
  defp assign_setup_banner_state(socket) do
    {critical_failures, show_banner?} =
      compute_setup_banner_state(socket.assigns.config, socket.assigns.setup_banner_dismissed?)

    socket
    |> assign(critical_failures: critical_failures)
    |> assign(show_setup_banner?: show_banner?)
  end

  # Pure helper — shared by the post-save banner assigner and the
  # async first-load task spawned from `start_async_settings_load/1`.
  # Returns the `{critical_failures, show_banner?}` pair without
  # touching the socket so the task can compute it off the LV process.
  defp compute_setup_banner_state(loaded_config, setup_banner_dismissed?) do
    probes = MediaCentaurWeb.Live.SetupLive.Probes.all(probe_input(loaded_config))
    critical_failures = Overview.critical_failures(probes)

    show_banner? =
      Overview.show_setup_banner?(
        Config.get(:setup_wizard_dismissed) == true,
        critical_failures,
        setup_banner_dismissed?
      )

    {critical_failures, show_banner?}
  end

  # Mirrors the input map `MediaCentaurWeb.SetupLive` builds — same shape
  # the probes expect.
  defp probe_input(loaded_config) do
    %{
      tmdb_api_key_configured?: Map.get(loaded_config, :tmdb_api_key_configured?, false),
      prowlarr_api_key_configured?: Map.get(loaded_config, :prowlarr_api_key_configured?, false),
      download_client_password_configured?:
        Map.get(loaded_config, :download_client_password_configured?, false),
      mpv_path: Map.get(loaded_config, :mpv_path),
      ffprobe_path: Config.get(:ffprobe_path),
      watch_dirs_entries: Config.watch_dirs_entries()
    }
  end

  # Owned async (ADR-049): runs a connection-test under the LiveView via
  # start_async/3, keyed by `result_key` so the result lands in the
  # matching `handle_async(result_key, …)` clause. Each save_* handler
  # dispatches here when the form was submitted with `_action=test`. The
  # test runs against the values the save handler just persisted, so a
  # failing test never displaces the user's typed-in input.
  defp start_async_test(socket, result_key, fun) when is_atom(result_key) and is_function(fun, 0) do
    start_async(socket, result_key, fun)
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
      tmdb_api_key_configured?: MediaCentaur.Secret.present?(cfg.get(:tmdb_api_key)),
      auto_approve_threshold: cfg.get(:auto_approve_threshold),
      prowlarr_url: cfg.get(:prowlarr_url),
      prowlarr_api_key_configured?: MediaCentaur.Secret.present?(cfg.get(:prowlarr_api_key)),
      download_client_type: cfg.get(:download_client_type),
      download_client_url: cfg.get(:download_client_url),
      download_client_username: cfg.get(:download_client_username),
      download_client_password_configured?:
        MediaCentaur.Secret.present?(cfg.get(:download_client_password)),
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

  # Connection-test persistence is owned by `MediaCentaur.Capabilities`,
  # which also broadcasts to `Topics.capabilities_updates/0` so LiveViews
  # that gate UI on integration health can re-render. These local
  # wrappers exist so callsites in this module stay readable.

  defp load_test_result(subject), do: Capabilities.load_test_result(subject)
  defp save_test_result(subject, status), do: Capabilities.save_test_result(subject, status)
  defp clear_test_result(subject), do: Capabilities.clear_test_result(subject)

  defp persist_service_flag(service, value) do
    env = Application.get_env(:media_centaur, :environment, :dev)

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

  # --- Watch-dir function components ---

  attr :errors, :list,
    required: true,
    doc: "list of `{field :: atom, message :: String.t()}` keyword tuples from changeset errors."

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
          MediaCentaur.Settings.find_or_create_entry!(%{key: key, value: %{"value" => value}})
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

  # Auto-acquisition defaults form — rendered inline by the acquisition
  # section_content/1 clause when Prowlarr is ready. Lives here at end-of-module
  # so it doesn't break the contiguous-grouping rule for `defp section_content/1`.
  defp auto_grab_defaults_form(assigns) do
    ~H"""
    <form
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
        <.button
          type="submit"
          variant="secondary"
          size="sm"
          class="shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </.button>
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
    """
  end
end
