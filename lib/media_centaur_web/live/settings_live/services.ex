defmodule MediaCentaurWeb.SettingsLive.Services do
  @moduledoc """
  The Services section of the Settings page — start/stop toggles for the
  background services plus a manual scan trigger. `SettingsLive` delegates
  to `render/1` and hosts the toggle / scan event handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  attr :watchers_running, :boolean, required: true
  attr :pipeline_running, :boolean, required: true
  attr :image_pipeline_running, :boolean, required: true
  attr :acquisition_running, :boolean, required: true
  attr :scanning, :boolean, required: true

  def render(assigns) do
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
          Manually scan all media directories for new media files.
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
end
