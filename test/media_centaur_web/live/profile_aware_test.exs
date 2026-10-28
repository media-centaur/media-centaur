defmodule MediaCentaurWeb.Live.ProfileAwareTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Profiles

  # /guide is the lightest page under live_session :default.
  @page "/guide"

  test "one profile: every page mounts with it and no switcher", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @page)
    assert has_element?(view, "#sidebar")
    refute has_element?(view, "#sidebar-profile")
  end

  test "two profiles and no cookie: the first page redirects to the picker with the page as return_to",
       %{conn: conn} do
    create_profile(name: "Ana")
    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fguide"}}} = live(conn, @page)

    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fsettings%3Fsection%3Dtmdb"}}} =
             live(conn, "/settings?section=tmdb")
  end

  test "two profiles and a cookie: the named profile is active and the switcher shows it", %{conn: conn} do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)
    assert has_element?(view, "#sidebar-profile[aria-label='Ana · Switch profile']")
    # Activates on focus like every sidebar sibling — no data-nav-defer-activate.
    refute has_element?(view, "#sidebar-profile[data-nav-defer-activate]")
  end

  test "the switcher is the first System entry, in the profile's hue, with no picture", %{
    conn: conn
  } do
    ana = create_profile(name: "Ana", hue: 150)
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)
    assert has_element?(view, "#sidebar-system > #sidebar-profile:first-child")
    assert has_element?(view, "#sidebar-profile[data-hue='150']")
    refute has_element?(view, "#sidebar-profile img")
  end

  test "the switcher navigates live to the picker, which opens inside the shell", %{conn: conn} do
    ana = create_profile(name: "Ana")
    conn = with_profile(conn, ana)
    {:ok, view, _html} = live_async!(conn, @page)

    {:ok, picker, _html} =
      view |> element("#sidebar-profile") |> render_click() |> follow_redirect(conn, "/profiles")

    assert has_element?(picker, "h1", "Who's watching?")

    assert has_element?(
             picker,
             "#sidebar-profile.sidebar-link-active[aria-label='Ana · Switch profile']"
           )
  end

  test "a stale cookie asks again", %{conn: conn} do
    create_profile(name: "Ana")
    conn = Plug.Test.init_test_session(conn, %{"profile_id" => Ecto.UUID.generate()})
    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fguide"}}} = live(conn, @page)
  end

  test "a rename reaches the open page", %{conn: conn} do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)

    {:ok, _ana} = Profiles.rename(ana, "Anna")

    render_until(view, fn _html ->
      has_element?(view, "#sidebar-profile[aria-label='Anna · Switch profile']")
    end)
  end

  test "removing the active profile of three drops the page to the picker, returning to it", %{
    conn: conn
  } do
    ana = create_profile(name: "Ana")
    create_profile(name: "Bea")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)

    :ok = Profiles.remove(ana)
    assert_redirect(view, "/profiles?return_to=%2Fguide")
  end

  test "removing the active profile of two leaves the other active, with no switcher", %{conn: conn} do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)
    assert has_element?(view, "#sidebar-profile[aria-label='Ana · Switch profile']")

    :ok = Profiles.remove(ana)
    render_until(view, fn _html -> not has_element?(view, "#sidebar-profile") end)
  end

  test "adding a second profile shows the switcher on the open page", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @page)
    refute has_element?(view, "#sidebar-profile")

    create_profile(name: "Ana")
    render_until(view, fn _html -> has_element?(view, "#sidebar-profile") end)
  end

  test "removing another profile keeps the active one chosen by the cookie", %{conn: conn} do
    ana = create_profile(name: "Ana")
    create_profile(name: "Bea")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)

    [me | _] = Profiles.list()
    :ok = Profiles.remove(me)
    {:ok, _ana} = Profiles.rename(ana, "Anna")
    # Both broadcasts come from this process in order, so the switcher
    # showing "Anna" means the hook handled the removal with two profiles
    # left, the cookie lookup chose Ana, and the page was not redirected.
    render_until(view, fn _html ->
      has_element?(view, "#sidebar-profile[aria-label='Anna · Switch profile']")
    end)
  end
end
