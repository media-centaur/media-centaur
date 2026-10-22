defmodule MediaCentaurWeb.Live.PlayerAwareTest do
  @moduledoc """
  The gate's second enforcement point: the LiveView socket bypasses plugs,
  so the `on_mount` hook judges the peer address and the session the same
  way the plug does. What `:player` holds is `RemoteAccessTest`'s claim;
  here, whether the mount proceeds.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Players

  @lan {192, 168, 1, 20}

  defp from_lan(conn) do
    conn
    |> Map.put(:remote_ip, @lan)
    |> Plug.Test.put_peer_data(%{address: @lan, port: 40_000, ssl_cert: nil})
  end

  defp as_player(conn, player), do: Plug.Test.init_test_session(conn, %{"player_id" => player.id})

  test "the host mounts without a session", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/settings")
  end

  test "an unpaired LAN socket is redirected to the pairing page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/pair"}}} = conn |> from_lan() |> live(~p"/settings")
  end

  test "a paired LAN socket mounts", %{conn: conn} do
    player = create_player(name: "Living room TV")
    {:ok, _view, _html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")
  end

  test "removing the player drops its live session to the pairing page", %{conn: conn} do
    player = create_player(name: "Living room TV")
    {:ok, view, _html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")

    :ok = Players.remove(player)

    assert_redirect(view, "/pair")
  end

  test "removing another player leaves the session alone", %{conn: conn} do
    player = create_player(name: "Living room TV")
    other = create_player(name: "Bedroom TV")
    {:ok, view, _html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")

    :ok = Players.remove(other)

    assert render(view) =~ "Settings"
  end
end
