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

  test "adds a profile inline, shows the new tile and clears the field; a blank name says why", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/profiles")

    assert has_element?(view, "#add-profile-form input#add-profile-name-0")

    view |> form("#add-profile-form", %{"name" => "   "}) |> render_submit()
    assert has_element?(view, "#add-profile-form p", "A profile needs a name")
    assert Profiles.count() == 1
    # A refusal keeps the field, and with it what was typed.
    assert has_element?(view, "#add-profile-form input#add-profile-name-0")

    view |> form("#add-profile-form", %{"name" => "Ana"}) |> render_submit()
    assert Profiles.count() == 2
    [_me, ana] = Profiles.list()
    render_until(view, fn _html -> has_element?(view, "#pick-#{ana.id} button", "Ana") end)
    # A success replaces the field with an empty one that takes the focus,
    # so a second press cannot add a duplicate.
    assert has_element?(view, "#add-profile-form input#add-profile-name-1[phx-mounted]")
    refute has_element?(view, "#add-profile-form p")
  end

  test "with an active profile the picker is a page of the shell, its switcher entry current", %{
    conn: conn
  } do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!("/profiles")
    assert has_element?(view, "h1", "Who's watching?")
    assert has_element?(view, "#sidebar")
    assert has_element?(view, "#sidebar-profile.sidebar-link-active", "Ana")
  end

  test "at the door — no active profile — the picker is full-screen", %{conn: conn} do
    create_profile(name: "Ana")
    {:ok, view, _html} = live(conn, "/profiles?return_to=/library")
    assert has_element?(view, "h1", "Who's watching?")
    refute has_element?(view, "#sidebar")
  end

  test "removing the active profile on the picker drops the shell and keeps the page", %{
    conn: conn
  } do
    ana = create_profile(name: "Ana")
    create_profile(name: "Bea")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!("/profiles")
    assert has_element?(view, "#sidebar")

    :ok = Profiles.remove(ana)
    render_until(view, fn _html -> not has_element?(view, "#sidebar") end)
    assert has_element?(view, "h1", "Who's watching?")
    refute has_element?(view, "#pick-#{ana.id}")
  end

  test "at the cap there is no add form", %{conn: conn} do
    for n <- 2..Profiles.max_profiles(), do: create_profile(name: "Person #{n}")
    {:ok, view, _html} = live(conn, "/profiles")
    refute has_element?(view, "#add-profile-form")
  end
end
