defmodule MediaCentaurWeb.SettingsLive.Preferences do
  @moduledoc """
  The Preferences section of the Settings page — session-local browsing
  preferences. `SettingsLive` delegates to `render/1` and hosts the toggle
  event handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  attr :spoiler_free, :boolean, required: true

  def render(assigns) do
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
end
