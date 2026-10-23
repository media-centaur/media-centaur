defmodule MediaCentaurWeb.SettingsLivePlayersTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Players

  @section "/settings?section=players"

  defp card(id), do: "#player-card-#{id}"

  test "one card per paired player, and the Pair card", %{conn: conn} do
    player = create_player(name: "Living room TV")
    {:ok, view, _html} = live_async!(conn, @section)
    assert has_element?(view, "#{card(player.id)} h3", "Living room TV")
    assert has_element?(view, "#pair-player")
    assert has_element?(view, "#start-pairing")
  end

  test "the Pair card links the TV app's release page", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)

    assert has_element?(
             view,
             "#pair-player a[href='https://github.com/media-centaur/media-centaur-android/releases/latest']",
             "Media Centaur TV app"
           )
  end

  test "Start pairing shows the open code; Cancel closes it", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#start-pairing") |> render_click()
    %{code: code} = Players.pairing()
    assert has_element?(view, "#pairing-code", code)
    assert render(view) =~ "#{Players.Pairing.Code.lifetime_minutes()} minutes"

    view |> element("#cancel-pairing") |> render_click()
    assert Players.pairing() == nil
    refute has_element?(view, "#pairing-code")
    assert has_element?(view, "#start-pairing")
  end

  test "a device pairing while the code shows adds its card and closes the code", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)
    view |> element("#start-pairing") |> render_click()
    %{code: code} = Players.pairing()

    {:ok, player} = Players.pair(code, "Bedroom TV")

    render_until(view, fn _html -> has_element?(view, "#{card(player.id)} h3", "Bedroom TV") end)
    refute has_element?(view, "#pairing-code")
  end

  test "Remove is an arm gesture: the second press removes the player", %{conn: conn} do
    player = create_player(name: "Living room TV")
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#remove-player-#{player.id}") |> render_click()
    assert Players.get(player.id)
    assert has_element?(view, "#remove-player-#{player.id}", "Click again to remove")

    view |> element("#remove-player-#{player.id}") |> render_click()
    assert Players.get(player.id) == nil
    assert render(view) =~ "Living room TV removed"
    refute has_element?(view, card(player.id))
  end

  test "bound to loopback, the Pair card says other devices cannot reach the install", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)
    assert render(view) =~ "127.0.0.1"
  end
end
