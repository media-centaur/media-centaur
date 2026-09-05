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
  use MediaCentaurWeb.Live.CardPlayButtonAware
  use MediaCentaurWeb.Live.LibraryBackdropAware
  use MediaCentaurWeb.Live.IncomingBackdropAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  # Settings is the only host for this flag (the consumer is the Playback
  # backend), so the SettingAware tuple is registered inline rather than
  # through a dedicated *Aware wrapper module.
  on_mount {MediaCentaurWeb.Live.SettingAware,
            {MediaCentaur.Settings.Preferences.AutoPlayNextEpisode, :auto_play_next_episode,
             :setting_aware_auto_play_next_episode}}

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.{Capabilities, SelfUpdate, Settings, Version}
  alias MediaCentaur.Platform.Autostart

  alias MediaCentaurWeb.Live.SettingsLive.{
    Overview,
    SystemSection
  }

  alias MediaCentaur.Maintenance
  alias MediaCentaur.Settings.Preferences.UIScale
  alias MediaCentaur.Acquisition
  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Watcher
  alias MediaCentaur.Pipeline
  alias MediaCentaur.Pipeline.Image, as: ImagePipeline
  alias MediaCentaurWeb.SettingsLive.MediaDirsLogic
  alias MediaCentaur.Settings.Controls
  alias MediaCentaur.Playback.LanguagePolicy
  alias MediaCentaurWeb.SettingsLive.Danger
  alias MediaCentaurWeb.SettingsLive.SystemSettings
  alias MediaCentaurWeb.SettingsLive.AcquisitionSection
  alias MediaCentaurWeb.SettingsLive.Controls, as: ControlsSection
  alias MediaCentaurWeb.SettingsLive.Language
  alias MediaCentaurWeb.SettingsLive.Library
  alias MediaCentaurWeb.SettingsLive.ImportSection
  alias MediaCentaurWeb.SettingsLive.MaintenanceSection
  alias MediaCentaurWeb.SettingsLive.Playback
  alias MediaCentaurWeb.SettingsLive.Preferences
  alias MediaCentaurWeb.SettingsLive.Services
  alias MediaCentaurWeb.SettingsLive.Tmdb
  alias MediaCentaurWeb.SettingsLive.SocialSection
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaurWeb.SettingsLive.LanguageLogic

  # Sections are grouped for sidebar display — a thin divider renders between
  # adjacent items whose :group differs. Order within a group is by frequency
  # of user interaction: things you touch daily come first.
  @sections [
    # Operational — the app itself and its background services.
    # (Update automation lives on the System section's Updates card.)
    %{id: "system", label: "System", group: :system},
    %{id: "services", label: "Services", group: :system},
    # Personal — start-of-session setup
    %{id: "preferences", label: "Preferences", group: :general},
    %{id: "controls", label: "Controls", group: :general},
    # Media workflow — the arr stack. (Release tracking's refresh interval
    # lives on the Acquisition section — it feeds auto-grab.)
    %{id: "library", label: "Library", group: :media},
    %{id: "tmdb", label: "TMDB", group: :media},
    %{id: "social", label: "Social", group: :media},
    %{id: "acquisition", label: "Acquisition", group: :media},
    %{id: "import", label: "Media Import", group: :media},
    %{id: "playback", label: "Playback", group: :media},
    %{id: "language", label: "Language", group: :media},
    # Infrastructure — rare-touch admin. Maintenance holds the recoverable
    # repair actions; Danger Zone is reserved for the irreversible.
    %{id: "maintenance", label: "Maintenance", group: :infra},
    %{id: "danger", label: "Danger Zone", group: :infra}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Settings")

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
      Social.subscribe()
      Social.subscribe_connections()
      # Coarse heartbeat so the "next check" estimate on the Updates card stays
      # roughly current without behaving like a per-second countdown. The
      # labels carry no seconds (minute grain at their finest), so a 60s
      # recompute changes the text at most once per tick.
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
     |> assign(media_dirs: [])
     |> assign(exclude_dirs: [])
     |> assign(missing_images_summary: %{total: 0, missing: 0, by_role: %{}})
     |> assign(blank_extra_names_count: 0)
     |> assign(controls_reset_armed: false)
     |> assign(tmdb_test: nil)
     |> assign(prowlarr_test: nil)
     |> assign(download_client_test: nil)
     |> assign(tmdb_missing: false)
     |> assign(
       service_state: %{
         under_supervisor: false,
         unit_name: nil,
         supervisor_available: false,
         unit_installed: false,
         active: false,
         enabled: false
       }
     )
     |> assign(bindings: %{})
     |> assign(glyph_style: nil)
     |> assign(identity_npub: nil, nsec_revealed: nil, import_armed?: false, import_draft: "")
     |> assign(relays: [], relay_status: %{})
     |> assign(
       sections: @sections,
       exclude_dir_input: "",
       exclude_dir_error: nil,
       media_dir_dialog: nil,
       media_dir_delete_confirm: nil,
       scanning: false,
       clearing_database: false,
       controls_reset_armed: false,
       clear_database_prompt: false,
       confirming_image_refresh: false,
       refreshing_images: false,
       repairing_images: false,
       rederiving_extra_names: false,
       refetching_backdrops: false,
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
       usenet_client_testing: false,
       detected_usenet_client: nil,
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
  def handle_params(%{"add_media_dir" => "1"} = params, _uri, socket) do
    section = params["section"] || "library"

    socket =
      socket
      |> ensure_loaded()
      |> assign(active_section: section)
      |> assign_update_snapshot(section)
      |> load_social(section)
      |> open_media_dir_dialog(MediaDirsLogic.new_entry())

    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    section =
      params["section"] || "system"

    socket =
      socket
      |> ensure_loaded()
      |> assign(active_section: section)
      |> assign_update_snapshot(section)
      |> load_social(section)

    {:noreply, socket}
  end

  # The Social section is where the identity comes into existence (the
  # only other minting site is `Recommendations.recommend/2`). Other
  # sections leave it alone, so opening Settings never creates a key.
  defp load_social(socket, "social") do
    Identity.ensure()

    socket
    |> assign(identity_npub: Identity.npub(), nsec_revealed: nil, import_armed?: false, import_draft: "")
    |> assign(relay_status: Connections.status())
    |> load_relays()
  end

  defp load_social(socket, _section), do: socket

  defp load_relays(socket), do: assign(socket, :relays, Social.list_relays())

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
      media_dirs: Config.media_dirs_entries(),
      exclude_dirs: Config.get(:exclude_dirs) || [],
      # The per-image disk walk already ran in the Overview projection;
      # read its result instead of walking every file on each mount
      # (audit P4). A repair re-walks live in its own result handler.
      missing_images_summary: MediaCentaur.Status.Views.overview().missing_images,
      blank_extra_names_count: Maintenance.blank_extra_names_count(),
      tmdb_test: load_test_result(:tmdb),
      prowlarr_test: load_test_result(:prowlarr),
      download_client_test: load_test_result(:download_client),
      usenet_client_test: load_test_result(:usenet_download_client),
      tmdb_missing: SystemSection.tmdb_key_missing?(Config.get(:tmdb_api_key)),
      service_state: Autostart.state(),
      bindings: Controls.get(),
      glyph_style: Controls.glyph_style(),
      # cached_scale/0 (not scale/0) so the picker reflects exactly what the
      # root layout rendered, and so /settings stays DB-free for this read
      # (NoDbOnRenderTest). Warm in production; defaults in the cold test cache.
      ui_scale: UIScale.cached_scale(),
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
    {status, release} = SelfUpdate.view_status()
    assign(socket, update_status: status, latest_release: release)
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
    case Autostart.restart() do
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
    case Autostart.stop() do
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
        case Autostart.status_output() do
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

  # --- Media-dir card events ---

  def handle_event("media_dir:open_add", _, socket) do
    {:noreply, open_media_dir_dialog(socket, MediaDirsLogic.new_entry())}
  end

  def handle_event("media_dir:open_edit", %{"id" => id}, socket) do
    entry = Enum.find(socket.assigns.media_dirs, &(&1["id"] == id)) || MediaDirsLogic.new_entry()
    {:noreply, open_media_dir_dialog(socket, entry)}
  end

  def handle_event("media_dir:close", _, socket) do
    {:noreply, close_media_dir_dialog(socket)}
  end

  def handle_event("media_dir:validate", %{"entry" => params}, socket) do
    {:noreply, schedule_media_dir_validation(socket, params)}
  end

  def handle_event("media_dir:save", _, socket) do
    %{entry: entry, validation: validation} = socket.assigns.media_dir_dialog

    if MediaDirsLogic.saveable?(validation) do
      entries = MediaDirsLogic.upsert(socket.assigns.media_dirs, entry)
      :ok = Config.put_media_dirs(entries)
      {:noreply, close_media_dir_dialog(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("media_dir:delete_confirm", %{"id" => id}, socket) do
    {:noreply, assign(socket, :media_dir_delete_confirm, id)}
  end

  def handle_event("media_dir:delete_cancel", _, socket) do
    {:noreply, assign(socket, :media_dir_delete_confirm, nil)}
  end

  def handle_event("media_dir:delete", %{"id" => id}, socket) do
    entries = MediaDirsLogic.remove(socket.assigns.media_dirs, id)
    :ok = Config.put_media_dirs(entries)
    {:noreply, assign(socket, :media_dir_delete_confirm, nil)}
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
        :ok = Config.update(:exclude_dirs, new_list)

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
    :ok = Config.update(:exclude_dirs, new_list)
    {:noreply, assign(socket, :exclude_dirs, new_list)}
  end

  def handle_event("scan", _params, socket) do
    # Owned async (ADR-049, MC0019) so the LiveView stays responsive and the
    # Cancel button has something to cancel. A synchronous call here would
    # block the socket process — no render could fire during the scan, so the
    # "Scanning…" label would never become visible.
    {:noreply,
     socket
     |> assign(scanning: true)
     |> start_async(:scan, fn -> MediaCentaur.Watcher.Rescan.scan() end)}
  end

  def handle_event("cancel_scan", _params, socket) do
    if socket.assigns[:scanning] do
      {:noreply,
       socket
       |> cancel_async(:scan)
       |> assign(scanning: false)
       |> put_flash(:info, "Scan cancelled.")}
    else
      {:noreply, socket}
    end
  end

  # Clearing the database is irreversible and unbounded, so the button only
  # raises the confirmation; `clear_database` below is reachable solely from
  # inside the modal. See Credo MC0027 for why neither uses `data-confirm`.
  def handle_event("clear_database_prompt", _params, socket) do
    {:noreply, assign(socket, clear_database_prompt: true)}
  end

  def handle_event("cancel_clear_database", _params, socket) do
    {:noreply, assign(socket, clear_database_prompt: false)}
  end

  def handle_event("clear_database", _params, socket) do
    Maintenance.clear_database_async(self())
    {:noreply, assign(socket, clearing_database: true, clear_database_prompt: false)}
  end

  # Refreshing the image cache is recoverable — it costs a long re-download,
  # not data — so it arms in place instead of raising a modal.
  def handle_event("refresh_image_cache_confirm", _params, socket) do
    {:noreply, assign(socket, confirming_image_refresh: true)}
  end

  def handle_event("refresh_image_cache_cancel", _params, socket) do
    {:noreply, assign(socket, confirming_image_refresh: false)}
  end

  def handle_event("refresh_image_cache", _params, socket) do
    Maintenance.refresh_image_cache_async(self())
    {:noreply, assign(socket, refreshing_images: true, confirming_image_refresh: false)}
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

  def handle_event("rederive_extra_names", _params, socket) do
    Maintenance.rederive_extra_names_async(self())
    {:noreply, assign(socket, rederiving_extra_names: true)}
  end

  def handle_event("refetch_backdrops", _params, socket) do
    {:noreply, start_backdrop_refetch(socket, "")}
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

  def handle_event("toggle_letterboxd_links", _params, socket) do
    enabled = !socket.assigns.letterboxd_links
    MediaCentaur.Settings.Preferences.LetterboxdLinks.set(enabled)
    {:noreply, assign(socket, letterboxd_links: enabled)}
  end

  def handle_event("toggle_show_discovery", _params, socket) do
    enabled = !socket.assigns.show_discovery
    MediaCentaur.Settings.Preferences.DiscoveryVisibility.set(enabled)
    {:noreply, assign(socket, show_discovery: enabled)}
  end

  def handle_event("toggle_show_apps", _params, socket) do
    enabled = !socket.assigns.show_apps
    MediaCentaur.Settings.Preferences.AppsVisibility.set(enabled)
    {:noreply, assign(socket, show_apps: enabled)}
  end

  def handle_event("toggle_spoiler_free", _params, socket) do
    enabled = !socket.assigns.spoiler_free
    MediaCentaur.Settings.Preferences.SpoilerFree.set(enabled)
    {:noreply, assign(socket, spoiler_free: enabled)}
  end

  def handle_event("toggle_library_backdrop", _params, socket) do
    enabled = !socket.assigns.library_backdrop
    MediaCentaur.Settings.Preferences.LibraryBackdrop.set(enabled)
    {:noreply, assign(socket, library_backdrop: enabled)}
  end

  def handle_event("toggle_incoming_backdrop", _params, socket) do
    enabled = !socket.assigns.incoming_backdrop
    MediaCentaur.Settings.Preferences.IncomingBackdrop.set(enabled)
    {:noreply, assign(socket, incoming_backdrop: enabled)}
  end

  def handle_event("set_ui_scale", %{"choice" => scale}, socket) do
    # Persist (single source of truth) and push the new preference factor to
    # the open document so the whole shell rescales without a reload — the
    # effective zoom is composed in CSS as auto × preference. The CSS custom
    # property lives on <html>, so it also survives live navigation away from
    # Settings — no per-page :ui_scale assign needed elsewhere.
    applied = UIScale.set(scale)

    {:noreply,
     socket
     |> assign(ui_scale: applied)
     |> push_event("ui-scale", %{scale: applied})}
  end

  def handle_event("toggle_show_card_info", _params, socket) do
    enabled = !socket.assigns.show_card_info
    MediaCentaur.Settings.Preferences.LibraryCardInfo.set(enabled)
    {:noreply, assign(socket, show_card_info: enabled)}
  end

  def handle_event("toggle_show_play_button", _params, socket) do
    enabled = !socket.assigns.show_play_button
    MediaCentaur.Settings.Preferences.CardPlayButton.set(enabled)
    {:noreply, assign(socket, show_play_button: enabled)}
  end

  def handle_event("toggle_auto_play_next_episode", _params, socket) do
    enabled = !socket.assigns.auto_play_next_episode
    MediaCentaur.Settings.Preferences.AutoPlayNextEpisode.set(enabled)
    {:noreply, assign(socket, auto_play_next_episode: enabled)}
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

  # --- Social: identity + relays ------------------------------------------

  def handle_event("reveal_nsec", _params, socket),
    do: {:noreply, assign(socket, nsec_revealed: Identity.export_nsec())}

  def handle_event("hide_nsec", _params, socket), do: {:noreply, assign(socket, nsec_revealed: nil)}

  # Two-click arm (MC0027 treatment b): the first submit arms, the second
  # replaces. Costly but recoverable — the old nsec can be re-imported.
  def handle_event("import_nsec", %{"nsec" => nsec}, %{assigns: %{import_armed?: false}} = socket),
    do: {:noreply, assign(socket, import_armed?: true, import_draft: nsec)}

  def handle_event("import_nsec", %{"nsec" => nsec}, socket) do
    case Identity.import_nsec(nsec) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           identity_npub: Identity.npub(),
           nsec_revealed: nil,
           import_armed?: false,
           import_draft: ""
         )
         |> put_flash(:info, "Identity replaced")}

      {:error, :invalid_secret} ->
        {:noreply,
         socket
         |> assign(import_armed?: false, import_draft: "")
         |> put_flash(:error, "That is not a valid secret key")}
    end
  end

  def handle_event("add_relay", %{"url" => url}, socket) do
    case Social.add_relay(url) do
      {:ok, _relay} ->
        {:noreply, load_relays(socket)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Relay addresses start with wss:// or ws://")}
    end
  end

  def handle_event("remove_relay", %{"url" => url}, socket) do
    :ok = Social.remove_relay(url)
    {:noreply, load_relays(socket)}
  end

  def handle_event("save_tmdb", params, socket) do
    if Capabilities.save_integration(:tmdb, params) do
      # Recovery hook: a fresh key may unblock files that were stranded
      # by an earlier TMDB auth failure. Re-emit `:file_detected` for
      # any present watcher_files row with no library link so the
      # pipeline gets another chance.
      MediaCentaur.Watcher.Rescan.rescan_unlinked_async()
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
    Capabilities.save_integration(:prowlarr, params)
    socket = assign(socket, config: load_config(), prowlarr_test: load_test_result(:prowlarr))

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
    Capabilities.save_integration(:download_client, params)

    socket =
      assign(socket,
        config: load_config(),
        download_client_test: load_test_result(:download_client),
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

  def handle_event("save_usenet_client", params, socket) do
    Capabilities.save_integration(:usenet_download_client, params)

    socket =
      assign(socket,
        config: load_config(),
        usenet_client_test: load_test_result(:usenet_download_client),
        detected_usenet_client: nil
      )

    case params["_action"] do
      "test" ->
        socket =
          start_async_test(socket, :usenet_client_test_result, fn ->
            case Acquisition.test_download_client(:usenet) do
              :ok -> :ok
              {:error, _} -> :error
            end
          end)

        {:noreply, assign(socket, usenet_client_testing: true)}

      _ ->
        {:noreply, put_flash(socket, :info, "Usenet client settings saved")}
    end
  end

  def handle_event("detect_download_client", _params, socket) do
    Acquisition.discover_download_clients_async(self())
    {:noreply, assign(socket, download_client_detecting: true, download_client_detect_status: nil)}
  end

  def handle_event("save_import", params, socket) do
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

    case Float.parse(params["auto_approve_threshold"] || "") do
      {threshold, _} -> Config.update(:auto_approve_threshold, threshold)
      :error -> :ok
    end

    previous_resolution = Config.image_resolution()

    if params["image_resolution"] in Config.image_resolutions() do
      Config.update(:image_resolution, params["image_resolution"])
    end

    socket = assign(socket, config: load_config())

    # Changing the resolution is one trigger for re-fetching the affected
    # artwork (backdrops) at the new size; the Library Maintenance button is
    # the other. Both go through `refetch_backdrops_async`.
    socket =
      if Config.image_resolution() == previous_resolution do
        put_flash(socket, :info, "Media import settings saved")
      else
        start_backdrop_refetch(socket, "Media import settings saved — ")
      end

    {:noreply, socket}
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
    with kind_atom when not is_nil(kind_atom) <- safe_existing_atom(kind),
         id_atom when not is_nil(id_atom) <- safe_existing_atom(id) do
      {:noreply,
       socket
       |> assign(listening: {kind_atom, id_atom})
       |> push_event("controls:listen", %{kind: kind})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("controls:cancel", _params, socket) do
    {:noreply, assign(socket, listening: nil)}
  end

  def handle_event("controls:bind", %{"id" => id, "kind" => kind, "value" => value}, socket) do
    with id_atom when not is_nil(id_atom) <- safe_existing_atom(id),
         kind_atom when not is_nil(kind_atom) <- safe_existing_atom(kind) do
      normalized = normalize_bind_value(kind_atom, value)

      case Controls.put(id_atom, kind_atom, normalized) do
        {:ok, _} -> {:noreply, socket}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to bind key")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("controls:clear", %{"id" => id, "kind" => kind}, socket) do
    with id_atom when not is_nil(id_atom) <- safe_existing_atom(id),
         kind_atom when not is_nil(kind_atom) <- safe_existing_atom(kind) do
      :ok = Controls.clear(id_atom, kind_atom)
      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  # Resetting every binding has no undo: arm first (MC0027 tier 2).
  def handle_event("controls:reset_all_arm", _params, socket) do
    {:noreply, assign(socket, controls_reset_armed: true)}
  end

  def handle_event("controls:reset_all", _params, %{assigns: %{controls_reset_armed: false}} = socket) do
    {:noreply, assign(socket, controls_reset_armed: true)}
  end

  def handle_event("controls:reset_all", _params, socket) do
    :ok = Controls.reset_all()
    {:noreply, assign(socket, controls_reset_armed: false)}
  end

  def handle_event("controls:reset_category", %{"category" => category}, socket) do
    case safe_existing_atom(category) do
      nil ->
        {:noreply, socket}

      category_atom ->
        :ok = Controls.reset_category(category_atom)
        {:noreply, socket}
    end
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

  def handle_info({:image_cache_refreshed, count}, socket) do
    {:noreply,
     socket
     |> assign(refreshing_images: false)
     |> put_flash(
       :info,
       "Image cache cleared — #{count} #{if count == 1, do: "entry", else: "entries"} queued for re-download. New artwork will appear as downloads catch up."
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

  def handle_info({:extra_names_rederived, result}, socket) do
    {:noreply,
     socket
     |> assign(
       rederiving_extra_names: false,
       blank_extra_names_count: Maintenance.blank_extra_names_count()
     )
     |> put_flash(:info, rederive_extra_names_message(result))}
  end

  def handle_info({:backdrop_refetch_complete, %{enqueued: enqueued}}, socket) do
    msg =
      case enqueued do
        0 ->
          "No backdrops to re-fetch."

        n ->
          "Re-queued #{n} backdrop#{if n == 1, do: "", else: "s"} for download at the current resolution."
      end

    {:noreply,
     socket
     |> assign(refetching_backdrops: false)
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

  def handle_info({:config_updated, :media_dirs, entries}, socket) do
    {:noreply, assign(socket, :media_dirs, entries)}
  end

  def handle_info({:media_dir_validate, params}, socket) do
    case socket.assigns.media_dir_dialog do
      %{} = dialog ->
        entry = merge_entry(dialog.entry, params)

        validation =
          MediaCentaur.Watcher.validate_dir(
            entry,
            other_entries(socket.assigns.media_dirs, entry)
          )

        new_dialog = %{dialog | entry: entry, validation: validation, debounce_timer: nil}
        {:noreply, assign(socket, :media_dir_dialog, new_dialog)}

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
  def handle_info({:download_client_detect_result, {:ok, [_ | _] = clients}}, socket) do
    # Stash detected values as suggestions — do NOT persist. The URL
    # Prowlarr returns is correct from Prowlarr's perspective but is
    # often a Docker service name unreachable from this host. The user
    # reviews each form and clicks Save to commit. See ADR-037.
    # Each detected client routes to its protocol slot's form; the first
    # match per slot wins (one client per protocol, mirroring how
    # Prowlarr routes grabs).
    torrent = Enum.find(clients, &(ClientConfig.protocol_for_type(&1.type) == :torrent))
    usenet = Enum.find(clients, &(ClientConfig.protocol_for_type(&1.type) == :usenet))

    detected_torrent =
      case torrent do
        nil -> nil
        client -> %{type: client.type, url: client.url, username: client.username}
      end

    detected_usenet =
      case usenet do
        nil -> nil
        client -> %{type: client.type, url: client.url}
      end

    {:noreply,
     socket
     |> assign(
       detected_download_client: detected_torrent,
       detected_usenet_client: detected_usenet,
       download_client_detecting: false,
       download_client_detect_status: if(detected_torrent || detected_usenet, do: :ok, else: :empty)
     )
     |> put_flash(:info, detect_flash(detected_torrent, detected_usenet))}
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

  # Another tab replaced the identity. A key revealed here belongs to the
  # identity that is gone, an arm here is aimed at it too, and the pasted
  # draft is the secret that arm would have installed — all three drop.
  def handle_info({:identity_changed, _event}, socket) do
    {:noreply,
     assign(socket,
       identity_npub: Identity.npub(),
       nsec_revealed: nil,
       import_armed?: false,
       import_draft: ""
     )}
  end

  def handle_info({tag, _event}, socket) when tag in [:relay_added, :relay_removed] do
    {:noreply, load_relays(socket)}
  end

  # `Connections.apply_message/2` is the owner's own fold, so the page and
  # the owner can never disagree about what a connection message means.
  def handle_info({:relay_connection, url, message}, socket) do
    entry = Map.get(socket.assigns.relay_status, url, Connections.blank_entry())
    status = Map.put(socket.assigns.relay_status, url, Connections.apply_message(entry, message))
    {:noreply, assign(socket, relay_status: status)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp detect_flash(nil, nil),
    do: "Prowlarr's download clients have no driver in Media Centaur — nothing pre-filled"

  defp detect_flash(_torrent, nil),
    do: "Pre-filled the torrent client from Prowlarr — review URL, enter password, then Save"

  defp detect_flash(nil, _usenet),
    do: "Pre-filled the usenet client from Prowlarr — review URL, enter the API key, then Save"

  defp detect_flash(_torrent, _usenet),
    do: "Pre-filled both clients from Prowlarr — review URLs, enter credentials, then Save each form"

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

  def handle_async(:usenet_client_test_result, {:ok, status}, socket) do
    info = save_test_result(:usenet_download_client, status)
    {:noreply, assign(socket, usenet_client_testing: false, usenet_client_test: info)}
  end

  def handle_async(:scan, {:ok, {:ok, count}}, socket) do
    message =
      case count do
        0 -> "Scan complete — no new files found"
        1 -> "Scan complete — 1 new file detected"
        n -> "Scan complete — #{n} new files detected"
      end

    {:noreply,
     socket
     |> assign(scanning: false)
     |> put_flash(:info, message)}
  end

  # A crashed scan must clear the label; leaving `scanning` true strands the
  # page on "Scanning…" with only Cancel to escape (audit E52/DS17).
  def handle_async(:scan, {:exit, reason}, socket) do
    Log.warning(:settings, "library scan task exited — #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(scanning: false)
     |> put_flash(:error, "Scan failed. Check the console for details.")}
  end

  # A crashed connection test must clear its `*_testing` flag; leaving it
  # true strands the button on "Testing…" (audit DS17). One clause per
  # test so nothing falls through to a silent catch-all.
  for {result_key, flag, label} <- [
        {:tmdb_test_result, :tmdb_testing, "TMDB"},
        {:prowlarr_test_result, :prowlarr_testing, "Prowlarr"},
        {:download_client_test_result, :download_client_testing, "Download client"},
        {:usenet_client_test_result, :usenet_client_testing, "Usenet client"}
      ] do
    def handle_async(unquote(result_key), {:exit, reason}, socket) do
      Log.warning(:settings, "#{unquote(label)} connection test exited — #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(unquote(flag), false)
       |> put_flash(:error, "#{unquote(label)} test failed. Check the console for details.")}
    end
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

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/settings"
      full_width
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
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

        <.clear_database_modal open={@clear_database_prompt} />

        <%!--
          Media-dir dialog — always in DOM so backdrop-filter compositing
          layer is kept warm.
        --%>
        <.media_dir_dialog media_dir_dialog={@media_dir_dialog} media_dirs={@media_dirs} />
      </:overlays>
      <%!-- Outer relative wrapper carries the page-behavior + default zone and
            scopes the ambient scrim, matching the library/downloads/upcoming
            page shell so the heading sits at the same height across pages. --%>
      <div class="relative" data-page-behavior="settings" data-nav-default-zone="settings">
        <%!-- Scrim only — no `.page-atmosphere` image. Settings has no content
              entity to source a hero from, so it gets the dimmed sense-of-place
              of the other pages without a random backdrop competing with a
              utility surface. The calm variant: the page is mostly bare, so
              the standard ramp reads as a harsh band here. Fixed + behind
              content (z-0). --%>
        <div class="page-side-dim page-side-dim-calm" aria-hidden="true"></div>

        <div class="relative z-[1] space-y-6">
          <.page_header title="Settings">
            <:subtitle>Services, preferences, and configuration</:subtitle>
          </.page_header>

          <%!-- Header spans full width so its title aligns with the other
                pages; the nav + content row is capped at a comfortable measure
                so forms and toggle rows stay readable. --%>
          <div class="flex gap-8 max-w-[1100px]">
            <nav
              data-nav-zone="sections"
              class="w-40 shrink-0 sticky top-6 self-start flex flex-col gap-0.5"
            >
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
                      "menu-item-active !opacity-100 text-primary bg-primary/10 font-medium"
                  ]}
                >
                  {section.label}
                </.link>
              </div>
            </nav>

            <div data-nav-zone="grid" class="flex-1 min-w-0">
              <.section_content
                active_section={@active_section}
                identity_npub={@identity_npub}
                nsec_revealed={@nsec_revealed}
                import_armed?={@import_armed?}
                import_draft={@import_draft}
                relays={@relays}
                relay_status={@relay_status}
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
                confirming_image_refresh={@confirming_image_refresh}
                refreshing_images={@refreshing_images}
                repairing_images={@repairing_images}
                rederiving_extra_names={@rederiving_extra_names}
                blank_extra_names_count={@blank_extra_names_count}
                refetching_backdrops={@refetching_backdrops}
                refreshing_credits={@refreshing_credits}
                refreshing_series_credits={@refreshing_series_credits}
                refreshing_movie_subtitles={@refreshing_movie_subtitles}
                missing_images_summary={@missing_images_summary}
                spoiler_free={@spoiler_free}
                ui_scale={@ui_scale}
                show_card_info={@show_card_info}
                show_play_button={@show_play_button}
                auto_play_next_episode={@auto_play_next_episode}
                letterboxd_links={@letterboxd_links}
                show_discovery={@show_discovery}
                show_apps={@show_apps}
                library_backdrop={@library_backdrop}
                incoming_backdrop={@incoming_backdrop}
                tmdb_test={@tmdb_test}
                tmdb_testing={@tmdb_testing}
                prowlarr_test={@prowlarr_test}
                prowlarr_testing={@prowlarr_testing}
                download_client_test={@download_client_test}
                download_client_testing={@download_client_testing}
                download_client_detect_status={@download_client_detect_status}
                download_client_detecting={@download_client_detecting}
                detected_download_client={@detected_download_client}
                usenet_client_test={@usenet_client_test}
                usenet_client_testing={@usenet_client_testing}
                detected_usenet_client={@detected_usenet_client}
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
                media_dirs={@media_dirs}
                media_dir_delete_confirm={@media_dir_delete_confirm}
                exclude_dirs={@exclude_dirs}
                exclude_dir_input={@exclude_dir_input}
                exclude_dir_error={@exclude_dir_error}
                bindings={@bindings}
                glyph_style={@glyph_style}
                listening={@listening}
                controls_reset_armed={@controls_reset_armed}
              />
            </div>
          </div>
        </div>
      </div>
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
    <SystemSettings.render
      config={@config}
      app_version={@app_version}
      build_info={@build_info}
      critical_failures={@critical_failures}
      groups={@groups}
      issue_count={@issue_count}
      latest_release={@latest_release}
      service_state={@service_state}
      service_status_output={@service_status_output}
      service_status_visible={@service_status_visible}
      service_action_pending={@service_action_pending}
      show_setup_banner={@show_setup_banner?}
      tmdb_missing={@tmdb_missing}
      update_schedule_label={@update_schedule_label}
      update_status={@update_status}
      apply_phase={@apply_phase}
      update_check_enabled={@update_check_enabled}
      update_check_interval_minutes={@update_check_interval_minutes}
      update_check_interval_floor={@update_check_interval_floor}
      last_checked_label={@last_checked_label}
      auto_update_enabled={@auto_update_enabled}
    />
    """
  end

  defp section_content(%{active_section: "services"} = assigns) do
    ~H"""
    <Services.render
      watchers_running={@watchers_running}
      pipeline_running={@pipeline_running}
      image_pipeline_running={@image_pipeline_running}
      acquisition_running={@acquisition_running}
    />
    """
  end

  defp section_content(%{active_section: "preferences"} = assigns) do
    ~H"""
    <Preferences.render
      spoiler_free={@spoiler_free}
      ui_scale={@ui_scale}
      library_backdrop={@library_backdrop}
      incoming_backdrop={@incoming_backdrop}
      show_card_info={@show_card_info}
      show_play_button={@show_play_button}
      auto_play_next_episode={@auto_play_next_episode}
      letterboxd_links={@letterboxd_links}
      show_discovery={@show_discovery}
      show_apps={@show_apps}
    />
    """
  end

  defp section_content(%{active_section: "controls"} = assigns) do
    ~H"""
    <ControlsSection.render
      bindings={@bindings}
      glyph_style={@glyph_style}
      listening={@listening}
      reset_armed={@controls_reset_armed}
    />
    """
  end

  defp section_content(%{active_section: "tmdb"} = assigns) do
    ~H"""
    <Tmdb.render config={@config} tmdb_test={@tmdb_test} tmdb_testing={@tmdb_testing} />
    """
  end

  defp section_content(%{active_section: "social"} = assigns) do
    ~H"""
    <SocialSection.render
      npub={@identity_npub}
      nsec_revealed={@nsec_revealed}
      import_armed?={@import_armed?}
      import_draft={@import_draft}
      relays={@relays}
      status={@relay_status}
    />
    """
  end

  defp section_content(%{active_section: "acquisition"} = assigns) do
    prowlarr_configured = Acquisition.available?()

    # Form values prefer a pending `detected_download_client` (pre-filled
    # by "Detect from Prowlarr", not yet saved) over the persisted config.
    # See ADR-037 — the user must review and click Save to commit.
    detected = assigns[:detected_download_client] || %{}
    detected_usenet = assigns[:detected_usenet_client] || %{}
    config = assigns.config

    download_client_display = %{
      type: detected[:type] || config[:download_client_type],
      url: detected[:url] || config[:download_client_url],
      username: detected[:username] || config[:download_client_username]
    }

    usenet_client_display = %{
      type: detected_usenet[:type] || config[:usenet_download_client_type],
      url: detected_usenet[:url] || config[:usenet_download_client_url]
    }

    assigns =
      assign(assigns,
        prowlarr_configured: prowlarr_configured,
        download_client_display: download_client_display,
        usenet_client_display: usenet_client_display,
        prowlarr_ready: MediaCentaur.Capabilities.prowlarr_ready?(),
        auto_grab: MediaCentaur.Acquisition.AutoGrabSettings.load()
      )

    ~H"""
    <AcquisitionSection.render
      config={@config}
      prowlarr_configured={@prowlarr_configured}
      prowlarr_ready={@prowlarr_ready}
      prowlarr_test={@prowlarr_test}
      prowlarr_testing={@prowlarr_testing}
      download_client_display={@download_client_display}
      download_client_detecting={@download_client_detecting}
      download_client_test={@download_client_test}
      download_client_testing={@download_client_testing}
      usenet_client_display={@usenet_client_display}
      usenet_client_test={@usenet_client_test}
      usenet_client_testing={@usenet_client_testing}
      auto_grab={@auto_grab}
    />
    """
  end

  defp section_content(%{active_section: "import"} = assigns) do
    ~H"""
    <ImportSection.render config={@config} />
    """
  end

  defp section_content(%{active_section: "playback"} = assigns) do
    ~H"""
    <Playback.render config={@config} />
    """
  end

  defp section_content(%{active_section: "language"} = assigns) do
    ~H"""
    <Language.render
      language_options={@language_options}
      language_draft={@language_draft}
      language_policy={@language_policy}
    />
    """
  end

  defp section_content(%{active_section: "library"} = assigns) do
    ~H"""
    <Library.render
      config={@config}
      media_dirs={@media_dirs}
      media_dir_delete_confirm={@media_dir_delete_confirm}
      scanning={@scanning}
      exclude_dirs={@exclude_dirs}
      exclude_dir_input={@exclude_dir_input}
      exclude_dir_error={@exclude_dir_error}
    />
    """
  end

  defp section_content(%{active_section: "maintenance"} = assigns) do
    ~H"""
    <MaintenanceSection.render
      blank_extra_names_count={@blank_extra_names_count}
      missing_images_summary={@missing_images_summary}
      confirming_image_refresh={@confirming_image_refresh}
      rederiving_extra_names={@rederiving_extra_names}
      refetching_backdrops={@refetching_backdrops}
      refreshing_credits={@refreshing_credits}
      refreshing_images={@refreshing_images}
      refreshing_movie_subtitles={@refreshing_movie_subtitles}
      refreshing_series_credits={@refreshing_series_credits}
      repairing_images={@repairing_images}
    />
    """
  end

  defp section_content(%{active_section: "danger"} = assigns) do
    ~H"""
    <Danger.render clearing_database={@clearing_database} />
    """
  end

  defp section_content(assigns) do
    ~H"""
    <div class="p-5 rounded-lg glass-surface">
      <p class="text-base-content/60">Unknown section.</p>
    </div>
    """
  end

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

  defp phase_text_class(:pending), do: "text-sm text-base-content/55"
  defp phase_text_class(:active), do: "text-sm text-base-content font-medium"
  defp phase_text_class(:done), do: "text-sm text-base-content/70"
  defp phase_text_class(:failed), do: "text-sm text-error"

  # Modal rendered at the `Layouts.app` slot root so its `position:
  # fixed` containing block is the viewport, not some nested content
  # wrapper. Same placement pattern as `DetailPanel.detail_panel` in
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
    <.modal
      id="apply-progress-modal"
      open={SystemSection.apply_visible?(@apply_phase)}
      dismiss={:persistent}
      size={:sm}
      panel_class="p-6 space-y-5"
      role="dialog"
      aria-modal="true"
      aria-labelledby="apply-modal-title"
    >
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
          <p class="text-xs text-base-content/55">
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
    </.modal>
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
    <.modal
      id="service-action-modal"
      open={!is_nil(@action)}
      dismiss={:ephemeral}
      on_close="service_cancel"
      size={:sm}
      panel_class="p-6 space-y-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="service-confirm-title"
    >
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
    </.modal>
    """
  end

  attr :open, :boolean, required: true

  # `:persistent` on purpose: this is the one action in the app that is both
  # irreversible and unbounded, so a stray backdrop click or an Escape meant
  # for something else must not be able to answer it. Every other
  # confirmation in Settings is lighter — see Credo MC0027 for the rule.
  defp clear_database_modal(assigns) do
    ~H"""
    <.modal
      id="clear-database-modal"
      open={@open}
      dismiss={:persistent}
      on_close="cancel_clear_database"
      size={:sm}
      panel_class="p-6 space-y-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="clear-database-title"
    >
      <div class="space-y-1">
        <h3 id="clear-database-title" class="text-lg font-semibold text-error">
          Clear the database?
        </h3>
        <p class="text-sm text-base-content/70">
          Deletes every entry, watch record, and cached image. Your video files remain
          untouched, and a rescan re-imports them — but your watch history and any
          matches you corrected by hand are gone for good.
        </p>
      </div>

      <div class="flex justify-end gap-2 pt-2">
        <.button
          variant="dismiss"
          size="sm"
          phx-click="cancel_clear_database"
          data-nav-item
          tabindex="0"
        >
          Cancel
        </.button>
        <.button
          variant="danger"
          size="sm"
          phx-click="clear_database"
          data-nav-item
          tabindex="0"
        >
          Clear database
        </.button>
      </div>
    </.modal>
    """
  end

  attr :media_dir_dialog, :any,
    default: nil,
    doc:
      "transient media-directory dialog state — `nil` or `%{mode: :add | :remove, path: String.t()}`. Heterogeneous nil-or-map shape; `:any` is intentional."

  attr :media_dirs, :list,
    default: [],
    doc: "list of configured media directory paths (strings)."

  defp media_dir_dialog(assigns) do
    ~H"""
    <.modal
      id="media-dir-dialog"
      open={!is_nil(@media_dir_dialog)}
      dismiss={:persistent}
      on_close="media_dir:close"
      size={:sm}
      panel_class="p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="media-dir-dialog-title"
    >
      <.button
        variant="dismiss"
        size="sm"
        shape="circle"
        class="absolute top-3 right-3 z-10"
        phx-click="media_dir:close"
        aria-label="Close"
      >
        <.icon name="hero-x-mark-mini" class="size-5" />
      </.button>

      <h3 id="media-dir-dialog-title" class="text-lg font-semibold mb-4">
        {if @media_dir_dialog &&
              Enum.any?(@media_dirs, &(&1["id"] == @media_dir_dialog.entry["id"])),
            do: "Edit media directory",
            else: "Add media directory"}
      </h3>

      <form
        :if={@media_dir_dialog}
        id="media-dir-form"
        phx-change="media_dir:validate"
        phx-submit="media_dir:save"
        class="space-y-3"
      >
        <div>
          <label class="text-sm font-medium">Directory</label>
          <input
            type="text"
            name="entry[dir]"
            value={@media_dir_dialog.entry["dir"]}
            class="library-filter w-full"
          />
          <.media_dir_errors errors={@media_dir_dialog.validation.errors} field={:dir} />
        </div>

        <div>
          <label class="text-sm font-medium">
            Name <span class="text-base-content/55">(optional)</span>
          </label>
          <input
            type="text"
            name="entry[name]"
            value={@media_dir_dialog.entry["name"]}
            class="library-filter w-full"
          />
          <.media_dir_errors errors={@media_dir_dialog.validation.errors} field={:name} />
        </div>

        <details>
          <summary class="cursor-pointer text-sm text-base-content/60">
            Advanced — images directory
          </summary>
          <div class="mt-2 space-y-1">
            <input
              type="text"
              name="entry[images_dir]"
              value={@media_dir_dialog.entry["images_dir"]}
              class="library-filter w-full"
              placeholder="Leave blank to use the default"
            />
            <p class="text-xs text-base-content/55">
              If blank, artwork is cached at
              <code class="font-mono">
                {MediaDirsLogic.default_images_dir_hint(@media_dir_dialog.entry["dir"])}
              </code>
              and automatically skipped by the file watcher.
            </p>
            <.media_dir_errors
              errors={@media_dir_dialog.validation.errors}
              field={:images_dir}
            />
          </div>
        </details>

        <%!-- The id is the deterministic signal that the debounced validate
              has landed. Tests waited on the copy ("video files") until an
              unrelated string elsewhere on the page satisfied the wait
              instantly and the race came back. --%>
        <div
          :if={@media_dir_dialog.validation.preview}
          id="media-dir-preview"
          class="glass-inset rounded-lg p-3 text-sm text-base-content/70"
        >
          Found {@media_dir_dialog.validation.preview.video_count} video files, {@media_dir_dialog.validation.preview.subdir_count} subdirectories.
        </div>

        <div
          :for={warning <- @media_dir_dialog.validation.warnings}
          class="text-warning text-sm"
        >
          {MediaDirsLogic.error_message(warning)}
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <.button variant="dismiss" phx-click="media_dir:close">
            Cancel
          </.button>
          <.button
            type="submit"
            variant="primary"
            disabled={not MediaDirsLogic.saveable?(@media_dir_dialog.validation)}
          >
            Save
          </.button>
        </div>
      </form>
    </.modal>
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
      media_dirs_entries: Config.media_dirs_entries()
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

  defp rederive_extra_names_message(%{scanned: scanned, updated: updated}) do
    cond do
      scanned == 0 -> "No bonus features to check."
      updated == 0 -> "Checked #{scanned} bonus feature#{plural(scanned)} — all names current."
      true -> "Re-derived #{updated} bonus-feature name#{plural(updated)} from #{scanned} checked."
    end
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"

  # Shared by the resolution-change auto-trigger and the maintenance button.
  defp start_backdrop_refetch(socket, prefix) do
    Maintenance.refetch_backdrops_async(self())

    socket
    |> assign(refetching_backdrops: true)
    |> put_flash(:info, "#{prefix}Re-fetching backdrops at #{Config.image_resolution()}…")
  end

  defp load_config do
    config = Config

    %{
      # Sensitive values are NOT placed in LV assigns — only their
      # presence flags. The templates use *_configured? to decide whether
      # to show the "✓ configured" badge and the placeholder text.
      tmdb_api_key_configured?: MediaCentaur.Secret.present?(config.get(:tmdb_api_key)),
      auto_approve_threshold: config.get(:auto_approve_threshold),
      prowlarr_url: config.get(:prowlarr_url),
      prowlarr_api_key_configured?: MediaCentaur.Secret.present?(config.get(:prowlarr_api_key)),
      download_client_type: config.get(:download_client_type),
      download_client_url: config.get(:download_client_url),
      download_client_username: config.get(:download_client_username),
      download_client_password_configured?:
        MediaCentaur.Secret.present?(config.get(:download_client_password)),
      usenet_download_client_type: config.get(:usenet_download_client_type),
      usenet_download_client_url: config.get(:usenet_download_client_url),
      usenet_download_client_api_key_configured?:
        MediaCentaur.Secret.present?(config.get(:usenet_download_client_api_key)),
      mpv_path: config.get(:mpv_path),
      mpv_socket_dir: config.get(:mpv_socket_dir),
      mpv_socket_timeout_ms: config.get(:mpv_socket_timeout_ms),
      file_absence_ttl_days: config.get(:file_absence_ttl_days),
      recent_changes_days: config.get(:recent_changes_days),
      release_tracking_refresh_interval_hours: config.get(:release_tracking_refresh_interval_hours),
      extras_dirs: config.get(:extras_dirs) || [],
      skip_dirs: config.get(:skip_dirs) || [],
      database_path: config.get(:database_path),
      data_dir: config.get(:data_dir),
      media_dirs: config.get(:media_dirs) || []
    }
  end

  # Connection-test persistence is owned by `MediaCentaur.Capabilities`,
  # which also broadcasts to `Topics.capabilities_updates/0` so LiveViews
  # that gate UI on integration health can re-render. These local
  # wrappers exist so callsites in this module stay readable.

  defp load_test_result(subject), do: Capabilities.load_test_result(subject)
  defp save_test_result(subject, status), do: Capabilities.save_test_result(subject, status)

  defp persist_service_flag(service, value), do: Settings.Services.set(service, value)

  # --- Media-dir private helpers ---

  defp open_media_dir_dialog(socket, entry) do
    assign(socket, :media_dir_dialog, %{
      entry: entry,
      validation: %{errors: [], warnings: [], preview: nil},
      debounce_timer: nil
    })
  end

  defp close_media_dir_dialog(socket) do
    assign(socket, :media_dir_dialog, nil)
  end

  defp schedule_media_dir_validation(socket, params) do
    case socket.assigns.media_dir_dialog do
      %{debounce_timer: timer} = dialog ->
        if timer, do: Process.cancel_timer(timer)
        new_timer = Process.send_after(self(), {:media_dir_validate, params}, 500)
        assign(socket, :media_dir_dialog, %{dialog | debounce_timer: new_timer})

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

  # --- Media-dir function components ---

  attr :errors, :list,
    required: true,
    doc: "list of `{field :: atom, message :: String.t()}` keyword tuples from changeset errors."

  attr :field, :atom, required: true

  defp media_dir_errors(assigns) do
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
      {MediaDirsLogic.error_message(err)}
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
        {"auto_grab.max_attempts", params["max_attempts"], :integer},
        {"auto_grab.pack_min_fit", params["pack_min_fit"], :integer},
        {"auto_grab.size_preference", params["size_preference"], :string}
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
end
