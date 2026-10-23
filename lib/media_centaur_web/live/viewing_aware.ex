defmodule MediaCentaurWeb.Live.ViewingAware do
  @moduledoc """
  A remote player's OSD is the host's page (`campaigns/remote-players.md`,
  M5): the device's mpv draws nothing, so the page over it draws the
  **viewing layer** — the bar, the prompt, the subtitle line, the track
  menu — from the player's viewing stream, and sends the reader's keys
  back as `Playback.Command`s.

  An `on_mount` in `live_session :default` after `PlayerAware`: for a
  socket on a paired player it subscribes to that player's stream
  (`Playback.subscribe_viewing/1`), seeds `:viewing_layer` from the
  sessions already running, and attaches the hooks that keep the layer
  current and answer its events. The host player's socket gets
  `:viewing_layer` nil and no hooks: its mpv window draws its own OSD and
  covers the browser. `Layouts.app` renders `Components.ViewingLayer` on
  every page from the assign, so a viewing recovered while the page is on
  Settings has its OSD too.

  Events the layer sends: `viewing_command` (`command`, `seconds`),
  `viewing_prompt`, `viewing_track` (`kind`, `id`), `viewing_menu_open`,
  `viewing_menu_close`, `viewing_back` (closes the menu if open, else
  stops the viewing). The bar shows for #{4} s after any command and
  while paused (`Logic.bar_shown?/2`); nothing animates continuously.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias MediaCentaur.Playback
  alias MediaCentaur.Playback.Sessions
  alias MediaCentaur.Playback.Viewing
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.Live.ViewingAware.Logic

  @bar_shown_ms 4_000

  def on_mount(:default, _params, _session, %{assigns: %{player: :host}} = socket) do
    {:cont, assign(socket, viewing_layer: nil)}
  end

  def on_mount(:default, _params, _session, %{assigns: %{player: player_id}} = socket)
      when is_binary(player_id) do
    {:cont,
     socket
     |> Subscriptions.subscribe({Playback, :subscribe_viewing, [player_id]})
     |> assign(viewing_layer: Logic.initial(Sessions.list(), player_id))
     |> attach_hook(:viewing_aware, :handle_info, &on_info/2)
     |> attach_hook(:viewing_aware, :handle_event, &on_event/3)}
  end

  # --- the stream ---

  defp on_info({:viewing, %Viewing{}} = message, %{assigns: %{player: player_id}} = socket) do
    {:viewing, viewing} = message

    if viewing.player == player_id,
      do: {:halt, assign(socket, viewing_layer: Logic.update(socket.assigns.viewing_layer, viewing))},
      else: {:cont, socket}
  end

  defp on_info({:viewing_ended, %{player: player_id}}, %{assigns: %{player: player_id}} = socket) do
    {:halt, socket |> cancel_bar_timer() |> assign(viewing_layer: nil)}
  end

  defp on_info(:viewing_bar_hide, %{assigns: %{viewing_layer: %{} = layer}} = socket) do
    {:halt, assign(socket, viewing_layer: Logic.bar_released(layer))}
  end

  defp on_info(_message, socket), do: {:cont, socket}

  # --- the layer's events ---

  defp on_event("viewing_" <> _rest, _params, %{assigns: %{viewing_layer: nil}} = socket),
    do: {:halt, socket}

  defp on_event("viewing_command", params, socket) do
    case Logic.command_from_params(params) do
      {:ok, command} -> send_command(socket, command)
      :error -> :ok
    end

    {:halt, show_bar(socket)}
  end

  defp on_event("viewing_prompt", _params, socket) do
    send_command(socket, :activate_prompt)
    {:halt, socket}
  end

  defp on_event("viewing_track", params, socket) do
    case Logic.track_from_params(params) do
      {:ok, command} -> send_command(socket, command)
      :error -> :ok
    end

    {:halt, socket}
  end

  defp on_event("viewing_menu_open", _params, socket), do: {:halt, set_menu(socket, true)}
  defp on_event("viewing_menu_close", _params, socket), do: {:halt, set_menu(socket, false)}

  defp on_event("viewing_back", _params, %{assigns: %{viewing_layer: %{menu_open?: true}}} = socket),
    do: {:halt, set_menu(socket, false)}

  defp on_event("viewing_back", _params, socket) do
    %{player: player_id, viewing_layer: %{viewing: viewing}} = socket.assigns
    Sessions.stop(player_id, viewing.entity_id)
    {:halt, socket}
  end

  defp on_event(_event, _params, socket), do: {:cont, socket}

  defp send_command(%{assigns: %{player: player_id, viewing_layer: %{viewing: viewing}}}, command) do
    Playback.command(player_id, viewing.entity_id, command)
  end

  defp set_menu(%{assigns: %{viewing_layer: layer}} = socket, open?),
    do: assign(socket, viewing_layer: %{layer | menu_open?: open?})

  defp show_bar(socket) do
    socket = cancel_bar_timer(socket)
    layer = socket.assigns.viewing_layer
    timer = Process.send_after(self(), :viewing_bar_hide, @bar_shown_ms)
    assign(socket, viewing_layer: Logic.bar_held(layer, timer))
  end

  defp cancel_bar_timer(%{assigns: %{viewing_layer: %{bar_timer: timer}}} = socket)
       when is_reference(timer) do
    Process.cancel_timer(timer)
    socket
  end

  defp cancel_bar_timer(socket), do: socket
end
