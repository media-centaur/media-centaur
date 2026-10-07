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
    assert has_element?(view, "#sidebar-profile", "Ana")
  end

  test "a stale cookie asks again", %{conn: conn} do
    create_profile(name: "Ana")
    conn = Plug.Test.init_test_session(conn, %{"profile_id" => Ecto.UUID.generate()})
    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fguide"}}} = live(conn, @page)
  end

  test "a rename reaches the open page; removing the active profile drops it to the picker", %{
    conn: conn
  } do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)

    {:ok, ana} = Profiles.rename(ana, "Anna")
    render_until(view, fn _html -> has_element?(view, "#sidebar-profile", "Anna") end)

    :ok = Profiles.remove(ana)
    assert_redirect(view, "/profiles")
  end
end
