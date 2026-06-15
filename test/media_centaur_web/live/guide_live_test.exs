defmodule MediaCentaurWeb.GuideLiveTest do
  use MediaCentaurWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "GET /guide renders the first chapter and the sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide")
    assert html =~ "How identification works"
    assert html =~ "Your library"
  end

  test "deep link /guide/:slug renders that chapter", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide/how-identification-works")
    assert html =~ "How identification works"
  end

  test "unknown slug redirects to the guide index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/guide"}}} =
             live(conn, ~p"/guide/does-not-exist")
  end
end
