defmodule MediaCentaurWeb.Live.ViewingAwareTest do
  @moduledoc """
  The viewing layer: a paired device's page draws its player's viewing as
  the player's OSD and sends the reader's commands through `Playback`;
  the host's page never shows it. The session runs on a fake transport
  owned by the test, so every command the page causes arrives here as IPC.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import MediaCentaur.Eventually
  import Phoenix.LiveViewTest

  alias MediaCentaur.Playback.{Events, FakeTransport, SessionRegistry, Sessions}
  alias MediaCentaur.Profiles

  @lan {192, 168, 1, 20}

  defp from_lan(conn) do
    conn
    |> Map.put(:remote_ip, @lan)
    |> Plug.Test.put_peer_data(%{address: @lan, port: 40_000, ssl_cert: nil})
  end

  defp as_player(conn, player), do: Plug.Test.init_test_session(conn, %{"player_id" => player.id})

  setup do
    player = create_player(%{name: "Living room"})
    path = Path.join(System.tmp_dir!(), "mc-viewing-#{System.unique_integer([:positive])}.mkv")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)
    movie = create_standalone_movie(%{name: "Sample Movie"})

    params = %{
      action: :play,
      entity_id: movie.id,
      profile_id: Profiles.owner().id,
      entity_name: "Sample Movie",
      movie_id: movie.id,
      content_url: path,
      start_position: 0.0,
      transport: FakeTransport.new(self(), draws_subtitles?: false)
    }

    on_exit(fn ->
      for {{player, entity_id}, _pid} <- SessionRegistry.list(), do: Sessions.stop(player, entity_id)
    end)

    %{player: player, movie: movie, params: params}
  end

  defp start_viewing!(params, player) do
    :ok = Sessions.play(params, player.id)
    pid = SessionRegistry.lookup({player.id, params.entity_id})
    FakeTransport.emit(pid, {:attached, :fresh})
    assert_receive {:mpv_command, ["observe_property", 1, "time-pos"]}
    pid
  end

  test "the host's page never draws the layer, with or without a viewing", %{conn: conn, params: params} do
    :ok = Sessions.play(params, :host)
    {:ok, view, _html} = live(conn, ~p"/settings")
    refute has_element?(view, "[data-viewing]")
  end

  test "a device's page draws its player's viewing and hides it when the viewing ends", %{
    conn: conn,
    player: player,
    params: params,
    movie: movie
  } do
    pid = start_viewing!(params, player)
    {:ok, view, html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")

    assert has_element?(view, "[data-viewing]")
    assert html =~ "Sample Movie"

    FakeTransport.emit(
      pid,
      {:message, %{"event" => "property-change", "name" => "pause", "data" => true}}
    )

    eventually(fn -> render(view) =~ "Paused" end)

    Sessions.stop(player.id, movie.id)
    assert_receive {:mpv_command, ["quit"]}
    eventually(fn -> not has_element?(view, "[data-viewing]") end)
  end

  test "a device's page mounted before the viewing picks it up from the stream", %{
    conn: conn,
    player: player,
    params: params
  } do
    {:ok, view, _html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")
    refute has_element?(view, "[data-viewing]")

    start_viewing!(params, player)
    eventually(fn -> has_element?(view, "[data-viewing]") end)
    assert render(view) =~ "Sample Movie"
  end

  test "the page's commands reach the player as IPC through the session", %{
    conn: conn,
    player: player,
    params: params
  } do
    start_viewing!(params, player)
    {:ok, view, _html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")

    render_click(view, "viewing_command", %{"command" => "seek", "seconds" => "-10"})
    assert_receive {:mpv_command, ["seek", -10, "relative"]}

    render_click(view, "viewing_command", %{"command" => "toggle_pause"})
    assert_receive {:mpv_command, ["cycle", "pause"]}

    render_click(view, "viewing_track", %{"kind" => "subtitle", "id" => "none"})
    assert_receive {:mpv_command, ["set_property", "sid", "no"]}
  end

  test "the track menu opens on request; Back closes it first, then stops the viewing", %{
    conn: conn,
    player: player,
    params: params,
    movie: movie
  } do
    pid = start_viewing!(params, player)

    tracks = [
      %{"id" => 1, "type" => "audio", "lang" => "eng", "codec" => "dts"},
      %{"id" => 1, "type" => "sub", "lang" => "eng", "codec" => "subrip"},
      %{"id" => 2, "type" => "sub", "lang" => "eng", "codec" => "hdmv_pgs_subtitle"}
    ]

    FakeTransport.emit(
      pid,
      {:message, %{"event" => "property-change", "name" => "track-list", "data" => tracks}}
    )

    {:ok, view, _html} = conn |> from_lan() |> as_player(player) |> live(~p"/settings")

    refute has_element?(view, "[data-nav-overlay='viewing_menu'][data-state='open']")
    render_click(view, "viewing_menu_open", %{})
    assert has_element?(view, "[data-nav-overlay='viewing_menu'][data-state='open']")
    assert render(view) =~ "Not on this TV"

    render_click(view, "viewing_back", %{})
    refute has_element?(view, "[data-nav-overlay='viewing_menu'][data-state='open']")
    assert Sessions.get(player.id, movie.id)

    MediaCentaur.Playback.subscribe_viewing(player.id)
    render_click(view, "viewing_back", %{})
    assert_receive {:mpv_command, ["quit"]}
    assert_receive {:viewing_ended, %Events.ViewingEnded{}}, 500
    eventually(fn -> not has_element?(view, "[data-viewing]") end)
  end
end
