defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
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

    test "the tile's toolbar: the bookmark lists the title, Ignore hides it, Undo brings it back",
         %{conn: conn} = context do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache(context)
      store_movie(901, "Movie A")
      :ok = NewReleases.replace([digital(901)])

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#new-releases-row-movie-901-list[aria-label='Add to watchlist']")

      view |> element("#new-releases-row-movie-901-list") |> render_click()
      assert MediaCentaur.Watchlist.rung(901, :movie) == :list
      assert render_until(view, "On your list") =~ "On your list"
      assert has_element?(view, "#new-releases-row-movie-901-list[aria-label='Remove from watchlist']")

      view |> element("#new-releases-row-movie-901-ignore") |> render_click()
      assert MediaCentaur.Watchlist.rung(901, :movie) == :ignored
      assert has_element?(view, "#ignore-undo", "Movie A ignored")
      assert render_until(view, "New releases are on their way") =~ "New releases are on their way"

      view |> element("#ignore-undo-action") |> render_click()
      assert MediaCentaur.Watchlist.rung(901, :movie) == :list
      assert render_until(view, "Movie A") =~ "Movie A"
      refute has_element?(view, "#ignore-undo")
      await_supervised_tasks()
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

  describe "the watchlist shelves" do
    setup do
      Features.set(:discovery, true)
      TmdbStubs.mark_ready!()
      :ok
    end

    defp typed(dates) do
      %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" =>
              Enum.map(dates, fn {type, date} ->
                %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"}
              end)
          }
        ]
      }
    end

    defp list_movie(tmdb_id, name, rung, dates) do
      create_title_intent(%{
        tmdb_id: tmdb_id,
        media_type: :movie,
        name: name,
        rung: rung,
        payload:
          TmdbStubs.movie_detail(%{
            "id" => tmdb_id,
            "title" => name,
            "release_date" => nil,
            "release_dates" => typed(dates)
          })
      })
    end

    test "Out Now first, the Watchlist grouped row last with In Theaters and Coming Up chips; an owned title is on neither",
         %{conn: conn} do
      today = Date.utc_today()
      list_movie(901, "Movie Out", :follow, [{3, Date.add(today, -60)}, {4, Date.add(today, -5)}])
      list_movie(902, "Movie Opened", :list, [{3, Date.add(today, -12)}])
      list_movie(903, "Movie Ahead", :list, [{3, Date.add(today, 45)}])
      list_movie(904, "Movie Owned", :list, [{4, Date.add(today, -5)}])
      movie = create_movie(%{name: "Movie Owned", tmdb_id: "904"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, html} = live(conn, "/discovery")

      assert has_element?(view, "#out-now-row-movie-901", "Tracking")

      assert has_element?(
               view,
               "#watchlist-row [data-group='In Theaters'] #watchlist-row-movie-902",
               MediaCentaur.Format.month_day(Date.add(today, -12))
             )

      assert has_element?(view, "#watchlist-row [data-group='Coming Up'] #watchlist-row-movie-903")
      refute html =~ "Movie Owned"
      assert :binary.match(html, "Out Now") < :binary.match(html, "data-row=\"watchlist\"")
    end
  end

  describe "Reviewed by Friends" do
    alias MediaCentaur.Activities
    alias MediaCentaur.Activities.Translation
    alias MediaCentaur.Nostr.Event
    alias MediaCentaur.Secret
    alias MediaCentaur.Social
    alias MediaCentaur.Social.Identity
    alias MediaCentaur.TMDB.Title

    @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    setup context do
      Features.set(:discovery, true)
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache(context)
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      title = Title.new!(%{tmdb_id: 905, media_type: :movie, name: "Movie Reviewed"})

      event =
        Event.sign(
          Translation.to_event(:review, title, [sentiment: :love, text: "yes"], @friend_pubkey),
          @friend_secret
        )

      {:ok, _activity} = Activities.ingest(event)
      await_supervised_tasks()
      :ok
    end

    test "a friend's review puts the title on the shelf with its glyph; the shelf links to Social", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#friends-row-movie-905 [data-role='social-glyphs']")
      assert has_element?(view, "[data-row='friends'] a[href='/social']", "See all")
    end

    test "with Social off the shelf is gone", %{conn: conn} do
      Features.set(:social, false)

      {:ok, view, _html} = live(conn, "/discovery")
      refute has_element?(view, "#friends-row")
    end
  end
end
