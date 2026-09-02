defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Discovery
  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Events
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Library
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Preferences.DiscoveryVisibility
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.RelayBlock
  alias MediaCentaurWeb.DiscoveryLive.RosterBlock

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
      assert has_element?(view, "#import-nsec", nsec)
      assert Identity.pubkey() == before

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert Identity.pubkey() == "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      assert render(view) =~ "Identity replaced"
      assert has_element?(view, "#identity-npub", Identity.npub())
      refute has_element?(view, "#import-nsec", nsec)
    end

    test "replacing the identity in another tab clears the revealed key and the arm", %{conn: conn} do
      {:ok, tab_a, _html} = live(conn, "/discovery/friends")
      {:ok, tab_b, _html} = live(conn, "/discovery/friends")

      old_nsec = Identity.export_nsec()
      tab_a |> element("#reveal-nsec") |> render_click()
      assert has_element?(tab_a, "#identity-nsec", old_nsec)

      tab_a |> form("#import-nsec-form", %{"nsec" => old_nsec}) |> render_submit()
      assert has_element?(tab_a, "#import-nsec-submit", "Click again to replace")

      replacement = Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "3"))
      tab_b |> form("#import-nsec-form", %{"nsec" => replacement}) |> render_submit()
      tab_b |> form("#import-nsec-form", %{"nsec" => replacement}) |> render_submit()

      render_until(tab_a, fn _html -> not has_element?(tab_a, "#identity-nsec", old_nsec) end)
      assert has_element?(tab_a, "#import-nsec-submit", "Replace identity")
    end

    test "an invalid secret key is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      before = Identity.pubkey()

      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()
      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()

      assert render(view) =~ "That is not a valid secret key"
      assert has_element?(view, "#import-nsec-submit", "Replace identity")
      assert Identity.pubkey() == before
    end

    test "the watchlist tab still renders and the strip shows both tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Friends")
    end
  end

  describe "friends tab — relays" do
    @relay_url "wss://relay.example/"

    defp relay_row, do: "#" <> RelayBlock.dom_id(@relay_url)

    test "lists relays with their connection state, adds by URL, and removes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")

      view |> form("#add-relay-form", %{"url" => "wss://relay.example"}) |> render_submit()
      assert has_element?(view, relay_row(), @relay_url)
      assert has_element?(view, relay_row(), "Not connected")
      assert [%{url: @relay_url}] = Friends.list_relays()

      view |> element(relay_row() <> " button", "Remove") |> render_click()
      refute has_element?(view, relay_row())
      assert Friends.list_relays() == []
    end

    test "an invalid relay address is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      view |> form("#add-relay-form", %{"url" => "https://relay.example"}) |> render_submit()
      assert render(view) =~ "Relay addresses start with wss:// or ws://"
      assert Friends.list_relays() == []
    end

    test "connection state updates live from friends:connections", %{conn: conn} do
      {:ok, _relay} = Friends.add_relay(@relay_url)
      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, relay_row(), "Not connected")

      # The owner is not started under :test — stand in for its re-broadcast.
      Events.broadcast_connection(@relay_url, :connected)
      render_until(view, fn _html -> has_element?(view, relay_row(), "Connected") end)

      Events.broadcast_connection(@relay_url, {:auth, {:failed, "not on the allowlist"}})
      render_until(view, fn _html -> has_element?(view, relay_row(), "Rejected") end)
      assert has_element?(view, relay_row(), "not on the allowlist")
    end
  end

  describe "friends tab — roster" do
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    defp friend_row, do: "#friend-" <> String.slice(@friend_pubkey, 0, 8)

    test "adds a friend by npub + name, lists them, and removes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      npub = Keys.to_npub(@friend_pubkey)

      view
      |> form("#add-friend-form", %{"key" => npub, "nickname" => "Sample Friend"})
      |> render_submit()

      assert has_element?(view, friend_row(), "Sample Friend")
      assert has_element?(view, friend_row(), RosterBlock.short_npub(@friend_pubkey))
      assert [%{nickname: "Sample Friend"}] = Friends.list_friends()

      view |> element(friend_row() <> " button", "Remove") |> render_click()
      refute has_element?(view, friend_row())
      assert Friends.list_friends() == []
    end

    test "refuses a bad key, your own key, and a blank name with flashes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")

      view |> form("#add-friend-form", %{"key" => "npub1nope", "nickname" => "X"}) |> render_submit()
      assert render(view) =~ "That is not a valid public key"

      view
      |> form("#add-friend-form", %{"key" => Identity.npub(), "nickname" => "Me"})
      |> render_submit()

      assert render(view) =~ "That is your own key"

      view
      |> form("#add-friend-form", %{"key" => Keys.to_npub(@friend_pubkey), "nickname" => " "})
      |> render_submit()

      assert render(view) =~ "Give your friend a name"
      assert Friends.list_friends() == []
    end

    test "a roster change in another tab lands live", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      refute has_element?(view, friend_row())

      {:ok, _friend} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      render_until(view, fn _html -> has_element?(view, friend_row(), "Sample Friend") end)

      :ok = Friends.remove_friend(@friend_pubkey)
      render_until(view, fn _html -> not has_element?(view, friend_row()) end)
    end
  end
end
