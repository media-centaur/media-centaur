defmodule MediaCentaurWeb.SettingsLive.Playback do
  @moduledoc """
  The Playback section of the Settings page (UIDR-041): the mpv binary and
  IPC socket directory as text rows carrying their path check, and the
  socket timeout as a stepper. `SettingsLive` delegates to `render/1` and
  hosts the `set_mpv_*` handlers. `timeout_ladder/0` is the stepper's
  rungs, shared with its handler.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.Settings.Ladder

  @timeout_default 5000

  attr :config, :map,
    required: true,
    doc: "settings config map (reads `:mpv_path`, `:mpv_socket_dir`, `:mpv_socket_timeout_ms`)."

  def render(assigns) do
    assigns =
      assign(assigns,
        timeout: assigns.config[:mpv_socket_timeout_ms] || @timeout_default,
        timeout_default: @timeout_default
      )

    ~H"""
    <.settings_card title="mpv">
      <div class="space-y-0.5">
        <.settings_text_row
          id="mpv-path"
          label="mpv binary"
          name="mpv_path"
          value={@config[:mpv_path]}
          placeholder="/usr/bin/mpv"
          event="set_mpv_path"
          mono
        >
          <:label_suffix>
            <.path_status :if={@config[:mpv_path]} path={@config[:mpv_path]} kind={:executable} />
          </:label_suffix>
        </.settings_text_row>

        <.settings_text_row
          id="mpv-socket-dir"
          label="IPC socket directory"
          description="Where mpv's control socket is created for each playback session."
          name="mpv_socket_dir"
          value={@config[:mpv_socket_dir]}
          placeholder="/tmp"
          event="set_mpv_socket_dir"
          mono
        >
          <:label_suffix>
            <.path_status
              :if={@config[:mpv_socket_dir]}
              path={@config[:mpv_socket_dir]}
              kind={:directory}
            />
          </:label_suffix>
        </.settings_text_row>

        <.settings_stepper
          id="mpv-socket-timeout"
          label="Socket timeout"
          description="How long to wait for mpv to answer on its socket before giving up on a command."
          value_label={"#{@timeout} ms"}
          down_value={Ladder.down(timeout_ladder(), @timeout)}
          up_value={Ladder.up(timeout_ladder(), @timeout)}
          reset_value={@timeout_default}
          at_min={@timeout <= 100}
          at_max={@timeout >= 10_000}
          at_default={@timeout == @timeout_default}
          event="set_mpv_socket_timeout_ms"
        />
      </div>
    </.settings_card>
    """
  end

  @doc "The socket-timeout stepper's rungs, in milliseconds."
  @spec timeout_ladder() :: [pos_integer()]
  def timeout_ladder, do: [100, 250, 500, 1000, 2000, 3000, 5000, 7500, 10_000]
end
