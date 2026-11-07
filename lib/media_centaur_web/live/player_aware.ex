defmodule MediaCentaurWeb.Live.PlayerAware do
  @moduledoc """
  The gate on the LiveView socket, which bypasses plugs: the first entry
  in `live_session :default`'s `on_mount` list, ahead of `ProfileAware`,
  so an unpaired device never reaches the profile picker.

  Judges the peer address (`:peer_data` in the endpoint's `connect_info`)
  and the session's `"player_id"` through `MediaCentaurWeb.RemoteAccess.admit/2`,
  exactly as `Plugs.RemoteAccess` does for HTTP. Admitted, it assigns
  `:player` — the player this socket is on, as the id every viewing names
  (`Playback.player/0`: `:host`, or the paired player's id), the value
  `Playback.play/3` takes — and subscribes to `players:updates` through
  the subscribe door; when the player this socket holds is removed, the
  page drops to the pairing page. A paired player's connected socket
  records the browser's user agent on its row
  (`Players.record_user_agent/2`, a write only when it changed). Unpaired, it halts the mount with a
  redirect there.
  """

  use MediaCentaurWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]

  alias MediaCentaur.Players
  alias MediaCentaur.Players.Events.PlayerRemoved
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.RemoteAccess

  def on_mount(:default, _params, session, socket) do
    %{address: address} = get_connect_info(socket, :peer_data)

    case RemoteAccess.admit(address, session["player_id"]) do
      {:ok, player} ->
        record_user_agent(socket, player)

        {:cont,
         socket
         |> assign(player: player)
         |> Subscriptions.subscribe(Players)
         |> attach_hook(:player_aware, :handle_info, &on_players_event/2)}

      :unpaired ->
        {:halt, redirect(socket, to: ~p"/pair")}
    end
  end

  # The connected mount only: the dead render is the same browser.
  defp record_user_agent(socket, player_id) when is_binary(player_id) do
    with true <- connected?(socket),
         user_agent when is_binary(user_agent) <- get_connect_info(socket, :user_agent) do
      Players.record_user_agent(player_id, user_agent)
    end
  end

  defp record_user_agent(_socket, :host), do: :ok

  defp on_players_event({:player_removed, %PlayerRemoved{id: id}}, %{assigns: %{player: id}} = socket),
    do: {:halt, redirect(socket, to: ~p"/pair")}

  defp on_players_event(_message, socket), do: {:cont, socket}
end
