defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Discovery
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Library
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Preferences.DiscoveryVisibility
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  setup do
    TmdbStubs.setup_tmdb_client()
  end

  test "empty watchlist renders the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#watchlist-empty")
  end

  test "renders rows with the honest action per state", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(
        Title.new!(%{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          release_date: ~D[2020-01-01]
        })
      )

    {:ok, _} =
      Discovery.add_to_watchlist(
        Title.new!(%{
          tmdb_id: 42,
          media_type: :tv_series,
          name: "Sample Show",
          release_date: ~D[2999-01-01]
        })
      )

    # A presentable movie (container + linked file) owning TMDB id 777.
    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    create_linked_file(%{movie_id: movie.id})

    {:ok, _view, html} = live(conn, "/discovery/watchlist")
    assert html =~ "In library"
    assert html =~ "Track release"
    await_supervised_tasks()
  end

  test "remove deletes the item live", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    view
    |> element("#watchlist-item-movie-777 button", "Remove")
    |> render_click()

    refute has_element?(view, "#watchlist-item-movie-777")
    refute Discovery.on_watchlist?(777, :movie)
    await_supervised_tasks()
  end

  test "watchlist events refresh the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    {:ok, _} =
      Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    assert render(view) =~ "Sample Movie"
    await_supervised_tasks()
  end

  test "library changes flip a row to In library without a reload", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    {:ok, view, html} = live(conn, "/discovery/watchlist")
    refute html =~ "In library"

    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    create_linked_file(%{movie_id: movie.id})
    Library.broadcast_entities_changed([movie.id])

    render_until(view, "In library")
    await_supervised_tasks()
  end

  test "track action hands off to release tracking", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(
        Title.new!(%{
          tmdb_id: 42,
          media_type: :tv_series,
          name: "Sample Show",
          release_date: ~D[2999-01-01]
        })
      )

    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    view
    |> element("#watchlist-item-tv_series-42 button", "Track release")
    |> render_click()

    assert render(view) =~ "Tracking Sample Show"

    # The tracking itself runs on a supervised context task; await it,
    # then assert the effect landed.
    await_supervised_tasks()
    assert %{tmdb_id: 42} = ReleaseTracking.get_item_by_tmdb(42, :tv_series)
  end

  test "renders the Discovery heading and the Watchlist tab with its count", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    assert has_element?(view, "h1", "Discovery")
    assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
    assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "1")
    await_supervised_tasks()
  end

  test "the sidebar marks Discovery active on the watchlist tab", %{conn: conn} do
    Settings.find_or_create_entry!(%{
      key: DiscoveryVisibility.setting_key(),
      value: %{"enabled" => true}
    })

    {:ok, view, _html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#sidebar a.sidebar-link-active[href='/discovery/watchlist']")
  end

  describe "friends tab — identity" do
    test "opening the tab generates an identity and shows the npub with a copy control", %{conn: conn} do
      refute Identity.present?()
      {:ok, view, _html} = live(conn, "/discovery/friends")

      assert Identity.present?()
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Friends")
      assert has_element?(view, "#identity-npub", Identity.npub())
      assert has_element?(view, "#copy-npub[data-copy-text='#{Identity.npub()}']")
      refute render(view) =~ Identity.export_nsec()
    end

    test "the secret key is revealed only on request", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      nsec = Identity.export_nsec()

      refute render(view) =~ nsec
      view |> element("#reveal-nsec") |> render_click()
      assert has_element?(view, "#identity-nsec", nsec)
      assert has_element?(view, "#copy-nsec[data-copy-text='#{nsec}']")
    end

    test "importing a secret key replaces the identity after a second click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      before = Identity.pubkey()
      nsec = Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "3"))

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert has_element?(view, "#import-nsec-submit", "Click again to replace")
      assert Identity.pubkey() == before

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert Identity.pubkey() == "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      assert render(view) =~ "Identity replaced"
      assert has_element?(view, "#identity-npub", Identity.npub())
    end

    test "an invalid secret key is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      before = Identity.pubkey()

      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()
      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()

      assert render(view) =~ "That is not a valid secret key"
      assert Identity.pubkey() == before
    end

    test "the watchlist tab still renders and the strip shows both tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Friends")
    end
  end
end
