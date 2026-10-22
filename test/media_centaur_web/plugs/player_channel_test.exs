defmodule MediaCentaurWeb.Plugs.PlayerChannelTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.MediaToken
  alias MediaCentaurWeb.Plugs.PlayerChannel

  @lan {192, 168, 1, 20}

  defp from_lan(conn), do: %{conn | remote_ip: @lan}
  defp as_player(conn, player), do: Plug.Test.init_test_session(conn, %{"player_id" => player.id})

  test "the host has no channel", %{conn: conn} do
    assert conn |> get("/players/channel") |> response(403)
  end

  test "an unpaired device meets the gate first", %{conn: conn} do
    assert conn |> from_lan() |> get("/players/channel") |> redirected_to() == "/pair"
  end

  test "a paired player must ask for a WebSocket", %{conn: conn} do
    player = create_player(name: "Living room TV")
    assert conn |> from_lan() |> as_player(player) |> get("/players/channel") |> response(426)
  end

  test "a browser page from elsewhere cannot open a channel", %{conn: conn} do
    player = create_player(name: "Living room TV")

    conn =
      conn
      |> from_lan()
      |> as_player(player)
      |> put_req_header("upgrade", "websocket")
      |> put_req_header("origin", "http://evil.example")
      |> get("/players/channel")

    assert response(conn, 403)
  end

  test "only GET opens a channel", %{conn: conn} do
    player = create_player(name: "Living room TV")
    assert conn |> from_lan() |> as_player(player) |> post("/players/channel", %{}) |> response(405)
  end

  test "the locators point at the address the device reached us by and read it back", %{conn: conn} do
    player_id = Ecto.UUID.generate()
    presence_id = Ecto.UUID.generate()
    conn = %{conn | host: "192.168.1.5", port: 2160, scheme: :http}

    %{locate: locate, identify: identify} = PlayerChannel.locators(conn, player_id)
    url = locate.(presence_id)

    assert String.starts_with?(url, "http://192.168.1.5:2160/media/#{presence_id}?t=")
    assert identify.(url) == presence_id
    assert identify.("http://192.168.1.5:2160/pair") == nil

    %URI{query: query} = URI.parse(url)
    assert {:ok, {^player_id, ^presence_id}} = MediaToken.verify(URI.decode_query(query)["t"])
  end
end
