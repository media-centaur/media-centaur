defmodule MediaCentaurWeb.LibraryLiveTest do
  use MediaCentaurWeb.ConnCase

  import Phoenix.LiveViewTest
  import MediaCentaur.TestFactory

  describe "URL param state restoration" do
    test "default mount sets active_tab :all, no selection, empty filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")

      assert view |> element("[role=tablist] .tab-active") |> render() =~ "All"
    end

    test "?tab=movies activates movies tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library?tab=movies")

      assert view |> element("[role=tablist] .tab-active") |> render() =~ "Movies"
    end

    test "?tab=tv activates tv tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library?tab=tv")

      assert view |> element("[role=tablist] .tab-active") |> render() =~ "TV"
    end

    test "?tab=bogus falls back to :all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library?tab=bogus")

      assert view |> element("[role=tablist] .tab-active") |> render() =~ "All"
    end

    test "?selected=<uuid> selects that entity", %{conn: conn} do
      entity = create_entity(%{name: "Selected Movie"})

      {:ok, view, _html} = live(conn, "/library?selected=#{entity.id}")

      # The side drawer should show the selected entity's name
      assert render(view) =~ "Selected Movie"
    end

    test "?filter=text sets filter input and filters the grid", %{conn: conn} do
      create_entity(%{name: "The Matrix"})
      create_entity(%{name: "Inception"})

      {:ok, view, _html} = live(conn, ~p"/library?filter=matrix")

      assert view |> element("#library-filter") |> render() =~ "matrix"
      html = render(view)
      assert html =~ "The Matrix"
      refute html =~ "Inception"
    end

    test "?tab=movies&filter=text&selected=uuid restores all three params", %{conn: conn} do
      entity = create_entity(%{name: "Matrix Reloaded"})

      {:ok, view, _html} = live(conn, "/library?tab=movies&filter=matrix&selected=#{entity.id}")

      html = render(view)
      assert view |> element("[role=tablist] .tab-active") |> render() =~ "Movies"
      assert view |> element("#library-filter") |> render() =~ "matrix"
      assert html =~ "Matrix Reloaded"
    end
  end

  describe "URL updates on navigation" do
    test "switching tab patches URL with tab param", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")

      view |> element("[role=tablist] button", "Movies") |> render_click()

      assert_patched(view, "/library?tab=movies")
    end

    test "switching to All tab removes tab param from URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library?tab=movies")

      view |> element("[role=tablist] button", "All") |> render_click()

      assert_patched(view, "/library")
    end

    test "selecting entity patches URL with selected param", %{conn: conn} do
      entity = create_entity(%{name: "Clickable Movie"})

      {:ok, view, _html} = live(conn, ~p"/library")

      view
      |> element(~s([phx-click="select_entity"][phx-value-id="#{entity.id}"]))
      |> render_click()

      assert_patched(view, "/library?selected=#{entity.id}")
    end

    test "deselecting entity removes selected param from URL", %{conn: conn} do
      entity = create_entity(%{name: "Toggle Movie"})

      {:ok, view, _html} = live(conn, "/library?selected=#{entity.id}")

      # Click the same entity again to deselect
      view
      |> element(~s([phx-click="select_entity"][phx-value-id="#{entity.id}"]))
      |> render_click()

      assert_patched(view, "/library")
    end

    test "filtering patches URL with filter param", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")

      view |> form("form", %{filter_text: "matrix"}) |> render_change()

      assert_patched(view, "/library?filter=matrix")
    end

    test "combined state: tab + selection produces correct URL", %{conn: conn} do
      entity = create_entity(%{name: "TV Show", type: :tv_series})

      {:ok, view, _html} = live(conn, ~p"/library?tab=tv")

      view
      |> element(~s([phx-click="select_entity"][phx-value-id="#{entity.id}"]))
      |> render_click()

      assert_patch(view)
      # Verify assigns directly since param order in URL is non-deterministic
      assert render(view) =~ "TV Show"
      assert view |> element("[role=tablist] .tab-active") |> render() =~ "TV"
    end
  end
end
