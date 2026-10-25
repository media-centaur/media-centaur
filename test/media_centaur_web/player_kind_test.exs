defmodule MediaCentaurWeb.PlayerKindTest do
  @moduledoc """
  The root layout names the player a page is rendered for on `<html>`:
  `data-player="remote"` for a paired player (the TV app), nothing for the
  host. Styles that only a remote player's device can afford to drop key
  off it.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  @lan {192, 168, 1, 20}

  defp player_attribute(conn) do
    conn
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("html")
    |> LazyHTML.attribute("data-player")
  end

  test "a page for a paired player names it remote", %{conn: conn} do
    player = create_player(name: "Living room TV")

    conn =
      %{conn | remote_ip: @lan}
      |> Plug.Test.put_peer_data(%{address: @lan, port: 50_000, ssl_cert: nil})
      |> Plug.Test.init_test_session(%{"player_id" => player.id})
      |> get(~p"/settings")

    assert player_attribute(conn) == ["remote"]
  end

  test "a page for the host names no player", %{conn: conn} do
    assert player_attribute(get(conn, ~p"/settings")) == []
  end
end
