defmodule MediaCentaurWeb.SettingsLive.Preferences do
  @moduledoc """
  The Preferences section of the Settings page — personal display and browsing
  preferences (durable, stored in Settings). `SettingsLive` delegates to
  `render/1` and hosts the event handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  alias MediaCentaur.UIScale

  attr :spoiler_free, :boolean, required: true
  attr :ui_scale, :float, required: true
  attr :library_backdrop, :boolean, required: true
  attr :incoming_backdrop, :boolean, required: true

  def render(assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Preferences</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Personal display and browsing preferences.
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

        <.settings_row
          label="Library backdrop"
          description="Show ambient artwork behind the Library page"
          checked={@library_backdrop}
          event="toggle_library_backdrop"
          color="info"
        />

        <.settings_row
          label="Incoming backdrop"
          description="Show ambient artwork behind the Incoming page"
          checked={@incoming_backdrop}
          event="toggle_incoming_backdrop"
          color="info"
        />

        <.settings_choice
          label="Interface scale"
          description="The interface sizes itself to your screen automatically — use this to enlarge it further."
          options={UIScale.choices()}
          selected={@ui_scale}
          event="set_ui_scale"
        />
      </div>
    </div>
    """
  end
end
