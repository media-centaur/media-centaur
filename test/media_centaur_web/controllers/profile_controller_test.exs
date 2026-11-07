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

  describe "the chosen profile outlives the browser" do
    test "activating a profile sets a session cookie with an expiry", %{conn: conn} do
      ana = create_profile(name: "Ana")
      conn = post(conn, ~p"/profiles/#{ana.id}/activate", %{"return_to" => "/library"})

      assert %{max_age: max_age} = conn.resp_cookies["_media_centaur_key"]
      assert max_age >= 365 * 24 * 60 * 60
    end

    test "a page load renews the cookie's expiry", %{conn: conn} do
      ana = create_profile(name: "Ana")
      conn = post(conn, ~p"/profiles/#{ana.id}/activate", %{"return_to" => "/library"})

      # The first page load writes the CSRF token; the second changes nothing
      # in the session, so only the renewal writes the cookie.
      conn = conn |> recycle() |> get(~p"/profiles")
      conn = conn |> recycle() |> get(~p"/profiles")

      assert %{max_age: max_age} = conn.resp_cookies["_media_centaur_key"]
      assert max_age >= 365 * 24 * 60 * 60
    end
  end
end
