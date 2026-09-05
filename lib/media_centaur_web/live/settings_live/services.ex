defmodule MediaCentaurWeb.SettingsLive.Services do
  @moduledoc """
  The Services section of the Settings page — start/stop toggles for the
  background services. `SettingsLive` delegates to `render/1` and hosts
  the toggle event handlers. The manual scan trigger lives on the Library
  section, next to the media directories it scans.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  attr :watchers_running, :boolean, required: true
  attr :pipeline_running, :boolean, required: true
  attr :image_pipeline_running, :boolean, required: true
  attr :acquisition_running, :boolean, required: true

  def render(assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Services</h2>
          <p class="text-sm text-base-content/55 mt-0.5">
            Start or stop background services. State persists across restarts.
          </p>
        </div>
      </div>

      <div class="mt-4 space-y-0.5">
        <.settings_row
          label="File watching"
          description="Detects new files in your media directories"
          checked={@watchers_running}
          event="toggle_watchers"
          color="info"
        />
        <.settings_row
          label="Media import"
          description="Identifies new files and adds them to your library"
          checked={@pipeline_running}
          event="toggle_pipeline"
          color="info"
        />
        <.settings_row
          label="Artwork downloads"
          description="Fetches posters and backdrops from TMDB"
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
    </div>
    """
  end
end
