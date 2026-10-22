defmodule MediaCentaurWeb.Plugs.RemoteAccessTest do
  @moduledoc """
  The gate, through the whole endpoint: a request from the host passes;
  a request from the LAN passes only when its session holds a paired
  player, and is otherwise sent to the pairing page (a GET, artwork
  included — `ImageServer` sits behind the gate) or refused (anything
  else).
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  @lan {192, 168, 1, 20}

  defp from_lan(conn), do: %{conn | remote_ip: @lan}

  defp as_player(conn, player), do: Plug.Test.init_test_session(conn, %{"player_id" => player.id})

  test "the host passes without a session", %{conn: conn} do
    assert html_response(get(conn, ~p"/settings"), 200)
  end

  test "an unpaired LAN browser is sent to the pairing page", %{conn: conn} do
    conn = conn |> from_lan() |> get(~p"/settings")
    assert redirected_to(conn) == ~p"/pair"
  end

  test "an unpaired LAN GET for artwork is sent to the pairing page too — ImageServer sits behind the gate",
       %{conn: conn} do
    conn = conn |> from_lan() |> get("/media-images/posters/sample.jpg")
    assert redirected_to(conn) == ~p"/pair"
  end

  test "an unpaired LAN request that is not a GET is refused", %{conn: conn} do
    conn = conn |> from_lan() |> post(~p"/profiles/#{Ecto.UUID.generate()}/activate", %{})
    assert response(conn, 403)
  end

  test "a paired LAN browser passes", %{conn: conn} do
    player = create_player(name: "Living room TV")
    conn = conn |> from_lan() |> as_player(player) |> get(~p"/settings")
    assert html_response(conn, 200)
  end

  test "a removed player is unpaired on its next request", %{conn: conn} do
    player = create_player(name: "Living room TV")
    :ok = MediaCentaur.Players.remove(player)
    conn = conn |> from_lan() |> as_player(player) |> get(~p"/settings")
    assert redirected_to(conn) == ~p"/pair"
  end

  test "the pairing page itself is open to the LAN", %{conn: conn} do
    conn = conn |> from_lan() |> get(~p"/pair")
    assert html_response(conn, 200)
  end
end
