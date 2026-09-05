defmodule MediaCentaurWeb.SettingsLive.SystemSettings do
  @moduledoc """
  The System section of the Settings page — app/build info, the overview
  health summary, the self-update controls, and the systemd/launchd service
  card. `SettingsLive` computes the overview `groups`/`issue_count` and
  delegates to `render/1`; it hosts the update / service-control handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  alias MediaCentaur.SelfUpdate
  alias MediaCentaurWeb.Live.SettingsLive.{ReleaseNotes, SystemSection}

  attr :config, :map, required: true, doc: "settings config map."
  attr :app_version, :string, required: true
  attr :build_info, :any, required: true, doc: ":dev_build or {:ok, %{built_at, git_sha}}."
  attr :critical_failures, :list, required: true, doc: "setup-probe critical failures."
  attr :groups, :list, required: true, doc: "Overview health-item groups."
  attr :issue_count, :integer, required: true
  attr :latest_release, :any, required: true, doc: "latest GitHub release map or nil."

  attr :service_state, :map,
    required: true,
    doc: "OS-neutral autostart state from `Platform.Autostart.state/0` (under_supervisor, etc.)."

  attr :service_status_output, :any, required: true, doc: "systemctl status text or nil."
  attr :service_status_visible, :boolean, required: true
  attr :service_action_pending, :atom, required: true, doc: "pending service action atom or nil."
  attr :show_setup_banner, :boolean, required: true
  attr :tmdb_missing, :boolean, required: true
  attr :update_schedule_label, :string, required: true
  attr :update_status, :any, required: true, doc: "self-update status atom/tuple."
  attr :apply_phase, :any, required: true, doc: "update apply-phase state or nil."
  attr :update_check_enabled, :boolean, required: true
  attr :update_check_interval_minutes, :integer, required: true
  attr :update_check_interval_floor, :integer, required: true
  attr :last_checked_label, :string, required: true
  attr :auto_update_enabled, :boolean, required: true

  def render(assigns) do
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
          <p class="text-xs text-base-content/55">
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
            <p class="text-xs text-base-content/55 mt-1.5">{@update_schedule_label}</p>
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

        <div class="mt-4 pt-4 border-t border-base-content/10 space-y-5">
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
              <p class="text-xs text-base-content/55 leading-relaxed">
                Media Centaur asks the GitHub Releases API whether a newer version exists. GitHub
                allows about 60 unauthenticated requests an hour from your network, so checking more
                often than every {@update_check_interval_floor} minutes risks temporary rate-limiting
                with no benefit — releases are infrequent.
              </p>
              <p class="text-xs text-base-content/55">{@last_checked_label}</p>
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
            <p class="text-xs text-base-content/55 leading-relaxed px-3.5">
              If something is playing, the update waits until playback ends, so your session is never
              interrupted. Leave this off to review the release and press Update now yourself.
            </p>
          </div>

          <p class="text-xs text-base-content/55 leading-relaxed">
            Updates are published on GitHub. Media Centaur downloads, verifies, and installs each
            release in place and then restarts to finish — usually under a minute, and your library
            and settings are preserved.
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
          variant="secondary"
          size="sm"
          class="shrink-0"
          navigate={~p"/settings?section=tmdb"}
          data-nav-item
        >
          Add key
        </.button>
      </div>

      <div
        :if={@show_setup_banner}
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
            variant="secondary"
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
            <p class="text-sm text-base-content/55 mt-0.5">
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

      <div class="p-5 rounded-lg glass-surface">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Guide</h2>
            <p class="text-sm text-base-content/55 mt-0.5">
              How Media Centaur works, chapter by chapter — including features you may not be using yet.
            </p>
          </div>
          <div class="shrink-0">
            <.button variant="dismiss" size="xs" navigate={~p"/guide"} data-nav-item>
              Open the guide
            </.button>
          </div>
        </div>
      </div>

      <div :if={@config == %{}} class="p-5 rounded-lg glass-surface text-base-content/60">
        Loading configuration…
      </div>

      <div :for={group <- @groups} class="p-5 rounded-lg glass-surface space-y-2">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
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

  defp update_tone_class(tone), do: SystemSection.tone_class(tone)

  # Inline Service card — rendered inside the overview section.
  attr :service_state, :map,
    required: true,
    doc:
      "OS-neutral autostart state from `MediaCentaur.Platform.Autostart.state/0` — keys `:under_supervisor`, `:supervisor_available`, `:unit_name`, `:unit_installed`, `:active`, `:enabled`."

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
          @service_state.under_supervisor and @service_state.supervisor_available and
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
            <p :if={!@service_status_output} class="text-xs text-base-content/55 italic">
              Loading…
            </p>
          </div>
        </details>
      </div>

      <p
        :if={
          @service_state.under_supervisor and @service_state.supervisor_available and
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
        :if={not @service_state.under_supervisor and @service_state.supervisor_available}
        class="text-sm text-base-content/60"
      >
        This BEAM wasn't started by systemd — start/stop/restart buttons aren't available here. Your user systemd session is reachable, so you can still manage a unit from a terminal: <code class="font-mono text-xs">systemctl --user status media-centaur.service</code>.
      </p>

      <p
        :if={not @service_state.under_supervisor and not @service_state.supervisor_available}
        class="text-sm text-base-content/60"
      >
        This install isn't running under a systemd user session — start/stop/restart buttons aren't available here. Use the terminal you started the app from, or a process manager of your choice.
      </p>
    </div>
    """
  end

  defp service_card_subtitle(%{under_supervisor: true, unit_name: unit, active: true, enabled: true})
       when is_binary(unit), do: "Managed by systemd (#{unit}). Running and set to start on login."

  defp service_card_subtitle(%{under_supervisor: true, unit_name: unit, active: true, enabled: false})
       when is_binary(unit), do: "Managed by systemd (#{unit}). Running, but not set to start on login."

  defp service_card_subtitle(%{under_supervisor: true, unit_name: unit, active: false})
       when is_binary(unit), do: "Managed by systemd (#{unit}). Not running."

  defp service_card_subtitle(%{under_supervisor: true, active: true, enabled: true}),
    do: "Managed by systemd. Running and set to start on login."

  defp service_card_subtitle(%{under_supervisor: true, active: true, enabled: false}),
    do: "Managed by systemd. Running, but not set to start on login."

  defp service_card_subtitle(%{under_supervisor: true, active: false}),
    do: "Managed by systemd. Not running."

  defp service_card_subtitle(%{supervisor_available: false}), do: "Not running under systemd."

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

  defp service_state_badge_class(%{under_supervisor: true, active: true}),
    do:
      "shrink-0 flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-success/10 text-success"

  defp service_state_badge_class(%{under_supervisor: true, active: false}),
    do:
      "shrink-0 flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-warning/10 text-warning"

  defp service_state_badge_class(_),
    do:
      "shrink-0 flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-base-content/10 text-base-content/60"

  defp service_state_badge_icon(%{under_supervisor: true, active: true}), do: "hero-check-circle-mini"
  defp service_state_badge_icon(%{under_supervisor: true, active: false}), do: "hero-pause-circle-mini"
  defp service_state_badge_icon(_), do: "hero-minus-circle-mini"

  defp service_state_badge_text(%{under_supervisor: true, active: true}), do: "Running"
  defp service_state_badge_text(%{under_supervisor: true, active: false}), do: "Stopped"
  defp service_state_badge_text(_), do: "Unmanaged"

  defp overview_summary(0), do: "Configuration looks healthy."

  defp overview_summary(n), do: "#{n} #{if n == 1, do: "item needs", else: "items need"} your attention."

  defp overview_detail_class(:ok), do: "text-base-content/55"
  defp overview_detail_class(:neutral), do: "text-base-content/55"
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
end
