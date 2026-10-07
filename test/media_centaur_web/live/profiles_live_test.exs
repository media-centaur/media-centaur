defmodule MediaCentaurWeb.ProfilesLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Profiles

  test "asks who is watching with a tile per profile that posts to the activate route", %{conn: conn} do
    ana = create_profile(name: "Ana")
    [me, _ana] = Profiles.list()
    {:ok, view, _html} = live(conn, "/profiles?return_to=/library")

    assert has_element?(view, "h1", "Who's watching?")
    assert has_element?(view, "#pick-#{me.id} button", "Me")
    assert has_element?(view, "#pick-#{ana.id} button", "Ana")
    assert has_element?(view, "#pick-#{ana.id}[action='/profiles/#{ana.id}/activate'][method='post']")
    assert has_element?(view, "#pick-#{ana.id} input[name='return_to'][value='/library']")

    conn = view |> form("#pick-#{ana.id}") |> submit_form(conn)
    assert redirected_to(conn) == "/library"
    assert get_session(conn, "profile_id") == ana.id
  end

  test "adds a profile inline and shows the new tile; a blank name says why", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/profiles")

    view |> form("#add-profile-form", %{"name" => "   "}) |> render_submit()
    assert render(view) =~ "A profile needs a name"
    assert Profiles.count() == 1

    view |> form("#add-profile-form", %{"name" => "Ana"}) |> render_submit()
    assert Profiles.count() == 2
    [_me, ana] = Profiles.list()
    render_until(view, fn _html -> has_element?(view, "#pick-#{ana.id} button", "Ana") end)
  end

  test "at the cap there is no add form", %{conn: conn} do
    for n <- 2..8, do: create_profile(name: "Person #{n}")
    {:ok, view, _html} = live(conn, "/profiles")
    refute has_element?(view, "#add-profile-form")
  end
end
