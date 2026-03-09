defmodule MediaCentaurWeb.LibraryLiveTest do
  use MediaCentaurWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "skeleton" do
    test "renders continue watching and browse sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/library")

      assert html =~ "Continue Watching"
      assert html =~ "Browse"
    end
  end
end
