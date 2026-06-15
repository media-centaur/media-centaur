defmodule MediaCentaurWeb.SettingsLive.ReleaseTrackingSection do
  @moduledoc """
  The Release Tracking section of the Settings page — TMDB poll interval.
  `SettingsLive` delegates to `render/1` and hosts the save handler.
  """

  use MediaCentaurWeb, :html

  attr :config, :map,
    required: true,
    doc: "settings config map (reads `:release_tracking_refresh_interval_hours`)."

  def render(assigns) do
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
end
