defmodule MediaCentaurWeb.ProfileControllerTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  test "activating a profile writes it to the session and returns to the page", %{conn: conn} do
    ana = create_profile(name: "Ana")
    conn = post(conn, ~p"/profiles/#{ana.id}/activate", %{"return_to" => "/library"})
    assert redirected_to(conn) == "/library"
    assert get_session(conn, "profile_id") == ana.id
  end

  test "an unknown or malformed id goes back to the picker and writes nothing", %{conn: conn} do
    conn = post(conn, ~p"/profiles/#{Ecto.UUID.generate()}/activate", %{})
    assert redirected_to(conn) == "/profiles"
    assert get_session(conn, "profile_id") == nil

    conn = post(build_conn(), "/profiles/not-a-uuid/activate", %{})
    assert redirected_to(conn) == "/profiles"
  end
end
