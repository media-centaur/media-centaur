defmodule MediaCentaurWeb.SettingsLive.Playback do
  @moduledoc """
  The Playback section of the Settings page — MPV path, IPC socket
  directory, and timeout. `SettingsLive` delegates to `render/1` and hosts
  the save handler.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  attr :config, :map,
    required: true,
    doc: "settings config map (reads `:mpv_path`, `:mpv_socket_dir`, `:mpv_socket_timeout_ms`)."

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <form phx-submit="save_playback" class="p-5 rounded-lg glass-surface space-y-5">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold">Playback</h2>
            <p class="text-sm text-base-content/55 mt-0.5">
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
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/55 flex items-center gap-1.5 mb-1.5">
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
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/55 flex items-center gap-1.5 mb-1.5">
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
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/55 block mb-1.5">
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
end
