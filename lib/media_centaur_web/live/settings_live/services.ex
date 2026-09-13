defmodule MediaCentaurWeb.SettingsLive.Services do
  @moduledoc """
  The Services section of the Settings page — start/stop toggles for the
  background services. `SettingsLive` delegates to `render/1` and hosts
  the toggle event handlers. The manual scan trigger lives on the Library
  section, next to the media directories it scans.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  attr :watchers_running, :boolean, required: true
  attr :pipeline_running, :boolean, required: true
  attr :image_pipeline_running, :boolean, required: true
  attr :acquisition_running, :boolean, required: true

  def render(assigns) do
    ~H"""
    <.settings_card title="Background services" data-nav-grid>
      <div class="space-y-0.5">
        <.settings_row
          label="File watching"
          description="Detects new files in your media directories"
          checked={@watchers_running}
          event="toggle_watchers"
        />
        <.settings_row
          label="Media import"
          description="Identifies new files and adds them to your library"
          checked={@pipeline_running}
          event="toggle_pipeline"
        />
        <.settings_row
          label="Artwork downloads"
          description="Fetches posters and backdrops from TMDB"
          checked={@image_pipeline_running}
          event="toggle_image_pipeline"
        />
        <.settings_row
          label="Auto-grab"
          description="Search and grab releases as tracked episodes air"
          checked={@acquisition_running}
          event="toggle_acquisition"
        />
      </div>
    </.settings_card>
    """
  end
end
