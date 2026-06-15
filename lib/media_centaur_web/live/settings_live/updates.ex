defmodule MediaCentaurWeb.SettingsLive.Updates do
  @moduledoc """
  The Updates section of the Settings page — automatic update-check and
  auto-install preferences. `SettingsLive` delegates to `render/1` and hosts
  the toggle / save-interval handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  alias MediaCentaur.SelfUpdate

  attr :update_check_enabled, :boolean, required: true
  attr :update_check_interval_minutes, :integer, required: true
  attr :update_check_interval_floor, :integer, required: true
  attr :last_checked_label, :string, required: true
  attr :auto_update_enabled, :boolean, required: true

  def render(assigns) do
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
end
