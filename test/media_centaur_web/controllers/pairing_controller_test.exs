defmodule MediaCentaurWeb.PairingControllerTest do
  use MediaCentaurWeb.ConnCase, async: false

  alias MediaCentaur.Players

  @lan {192, 168, 1, 20}

  defp from_lan(conn), do: %{conn | remote_ip: @lan}

  test "the host has nothing to pair and is sent home", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/pair")) == "/"
  end

  test "a LAN device sees the pairing form", %{conn: conn} do
    html = conn |> from_lan() |> get(~p"/pair") |> html_response(200)
    assert html =~ "Pair this device"
    assert html =~ "Settings → Players"
  end

  test "the open code with a name pairs the device: the session holds the player, home follows",
       %{conn: conn} do
    %{code: code} = Players.start_pairing()

    conn =
      conn
      |> from_lan()
      |> post(~p"/pair", %{"pairing" => %{"name" => "Living room TV", "code" => code}})

    assert redirected_to(conn) == "/"
    [player] = Players.list()
    assert player.name == "Living room TV"
    assert get_session(conn, "player_id") == player.id
  end

  test "a wrong code re-renders the form with the reason and keeps the name", %{conn: conn} do
    %{code: code} = Players.start_pairing()
    wrong = if code == "000000", do: "000001", else: "000000"

    conn =
      conn
      |> from_lan()
      |> post(~p"/pair", %{"pairing" => %{"name" => "Living room TV", "code" => wrong}})

    html = html_response(conn, 200)
    assert html =~ "code"
    assert html =~ "Living room TV"
    assert get_session(conn, "player_id") == nil
    assert Players.list() == []
  end

  test "a missing name re-renders the form and leaves the code open", %{conn: conn} do
    %{code: code} = Players.start_pairing()

    conn = conn |> from_lan() |> post(~p"/pair", %{"pairing" => %{"name" => "  ", "code" => code}})

    assert html_response(conn, 200) =~ "name"
    assert Players.pairing() != nil
  end
end
