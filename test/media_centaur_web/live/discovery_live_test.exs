defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.NewReleases
  alias MediaCentaur.TmdbStubs

  describe "the feature (ADR-081)" do
    test "off by default: no sidebar entry, and the page is its off state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")

      refute has_element?(view, "[data-tip='Discovery']")
      assert has_element?(view, "#discovery-off")
      assert render(view) =~ "Discovery is off"
    end

    test "Turn on sets the flag and mounts the page, whose entry is in the sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")

      view |> element("#discovery-off-turn-on") |> render_click()
      assert Features.enabled?(:discovery)
      assert_redirect(view, "/discovery")

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-tip='Discovery']")
      assert render(view) =~ "Connect TMDB to fill this page"
    end

    test "the Feature flags row says it is in development", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/settings?section=features")
      assert html =~ "In development."
    end
  end

  describe "the New Releases shelf" do
    setup do
      Features.set(:discovery, true)
      TmdbStubs.mark_ready!()
      :ok
    end

    defp store_movie(tmdb_id, name) do
      create_title_record(%{
        tmdb_id: tmdb_id,
        media_type: :movie,
        payload:
          TmdbStubs.movie_detail(%{"id" => tmdb_id, "title" => name, "release_date" => "2026-10-02"})
      })
    end

    defp digital(tmdb_id), do: %{tmdb_id: tmdb_id, digital_date: ~D[2026-10-30]}

    test "the membership in shelf order, from the store's records; a tile opens the title detail",
         %{conn: conn} do
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      :ok = NewReleases.replace([digital(902), digital(901)])

      {:ok, view, html} = live(conn, "/discovery")

      assert has_element?(view, "#new-releases-row-movie-902")
      assert has_element?(view, "#new-releases-row-movie-901")
      assert :binary.match(html, "Movie B") < :binary.match(html, "Movie A")
      refute has_element?(view, "#discovery-empty")

      view |> element("#new-releases-row-movie-901") |> render_click()
      assert_patch(view, "/discovery?title=movie-901")
    end

    test "a member without a record is not drawn, an ignored one is dropped, an owned one says In library",
         %{conn: conn} do
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      store_movie(903, "Movie C")
      create_title_intent(%{tmdb_id: 902, media_type: :movie, rung: :ignored, name: "Movie B"})
      movie = create_movie(%{name: "Movie C", tmdb_id: "903"})
      _ = create_linked_file(%{movie_id: movie.id})
      :ok = NewReleases.replace([digital(901), digital(902), digital(903), digital(904)])

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#new-releases-row-movie-901")
      refute has_element?(view, "#new-releases-row-movie-902")
      refute has_element?(view, "#new-releases-row-movie-904")
      assert has_element?(view, "#new-releases-row-movie-903", "In library")
    end

    test "the shelf follows the membership", %{conn: conn} do
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      :ok = NewReleases.replace([digital(901)])

      {:ok, view, html} = live(conn, "/discovery")
      refute html =~ "Movie B"

      :ok = NewReleases.replace([digital(901), digital(902)])
      assert render_until(view, "Movie B") =~ "Movie B"
    end

    test "nothing stored yet: the page says the first refresh is on its way", %{conn: conn} do
      {:ok, view, html} = live(conn, "/discovery")

      assert has_element?(view, "#discovery-empty")
      assert html =~ "New releases are on their way"
    end

    test "nothing stored and TMDB down: the page says the shelf fills when TMDB is back",
         %{conn: conn} do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      {:ok, _view, html} = live(conn, "/discovery")
      assert html =~ "New releases arrive when TMDB is back"
    end
  end
end
