defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Discovery
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Library
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Preferences.DiscoveryVisibility
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.RosterBlock

  setup do
    TmdbStubs.setup_tmdb_client()
  end

  test "empty watchlist renders the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#watchlist-empty")
  end

  test "rows show state; the modal offers the honest action per state", %{conn: conn} do
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

    {:ok, view, html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#watchlist-item-movie-777", "In library")
    refute html =~ "Track release"

    # The verb lives in the modal: the unaired show offers Track release,
    # the owned movie offers the library detail.
    view |> element("#watchlist-item-tv_series-42") |> render_click()
    assert has_element?(view, "#title-track", "Track release")
    render_hook(view, "close_title", %{})

    view |> element("#watchlist-item-movie-777") |> render_click()
    assert has_element?(view, "#title-in-library[href='/library?selected=#{movie.id}']")
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
    assert has_element?(view, "#sidebar a.sidebar-link-active[href='/discovery']")
  end

  describe "friends tab" do
    test "shows the roster and points at Settings for identity and relays", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Friends")
      assert has_element?(view, "#add-friend-form")
      assert has_element?(view, "#friends-settings-pointer a[href='/settings?section=social']")
      refute has_element?(view, "#identity-npub")
      refute has_element?(view, "#add-relay-form")
    end

    test "the watchlist tab still renders and the strip shows both tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Friends")
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
      assert [%{nickname: "Sample Friend"}] = Social.list_friends()

      view |> element(friend_row() <> " button", "Remove") |> render_click()
      refute has_element?(view, friend_row())
      assert Social.list_friends() == []
    end

    test "refuses a bad key, your own key, and a blank name with flashes", %{conn: conn} do
      Identity.ensure()
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
      assert Social.list_friends() == []
    end

    test "a roster change in another tab lands live", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      refute has_element?(view, friend_row())

      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      render_until(view, fn _html -> has_element?(view, friend_row(), "Sample Friend") end)

      :ok = Social.remove_friend(@friend_pubkey)
      render_until(view, fn _html -> not has_element?(view, friend_row()) end)
    end
  end

  describe "feed tab" do
    @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    setup do
      Identity.ensure()
      :ok
    end

    @other_secret Secret.wrap(String.duplicate("0", 63) <> "2")
    @other_pubkey "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

    defp other_event(tmdb_id, sentiment) do
      title = Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie #{tmdb_id}"})

      Event.sign(
        Translation.to_event(:recommendation, title, [note: nil, sentiment: sentiment], @other_pubkey),
        @other_secret
      )
    end

    defp friend_event(tmdb_id, note, sentiment \\ :like) do
      title = Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie #{tmdb_id}"})

      Event.sign(
        Translation.to_event(:recommendation, title, [note: note, sentiment: sentiment], @friend_pubkey),
        @friend_secret
      )
    end

    test "empty state names the prerequisites, then the quiet empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Feed")
      assert has_element?(view, "#feed-scope-incoming.zone-tab-active")
      assert render(view) =~ "Add a relay under Settings → Social and a friend on the Friends tab"

      {:ok, _relay} = Social.add_relay("wss://relay.example")
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, view, _html} = live(conn, "/discovery")
      assert render(view) =~ "Nothing from your friends yet."
    end

    test "rows show the title, who and when, the note, and add to the watchlist", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#feed-#{rec.id}", "Sample Movie 777")
      assert has_element?(view, "#feed-#{rec.id}", "Sample Friend recommended")
      assert has_element?(view, "#feed-#{rec.id}", "Watch it.")
      # The lead already says who, so the pennant is icon-only.
      assert has_element?(view, "#feed-#{rec.id} .pennant[data-sentiment='like']")
      refute has_element?(view, "#feed-#{rec.id} .pennant", "Sample Friend")

      # The card opens the modal; Add to watchlist lives there and carries
      # the recommendation's provenance onto the item.
      view |> element("#feed-#{rec.id}") |> render_click()
      assert_patch(view, "/discovery?title=movie-777")
      assert render(view) =~ "Sample Friend recommended"

      view |> element("#title-watchlist-add") |> render_click()
      assert Discovery.on_watchlist?(777, :movie)
      assert has_element?(view, "#title-on-watchlist")
      assert has_element?(view, "#title-watchlist-remove")

      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery")
      assert has_element?(view, "#feed-#{rec.id}", "On watchlist")

      assert [%{item: %{source: :friend, activity_id: rec_id, note: "Watch it."}}] =
               Discovery.list_watchlist()

      assert rec_id == rec.id

      await_supervised_tasks()
    end

    test "a title the library has shows In library and links to it", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")
      assert has_element?(view, "#feed-#{rec.id}", "In library")
      assert has_element?(view, "#title-in-library[href='/library?selected=#{movie.id}']", "In library")

      await_supervised_tasks()
    end

    test "a received recommendation appears without a reload", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery")

      {:ok, rec} = Activities.ingest(friend_event(778, "live"))
      render_until(view, fn _html -> has_element?(view, "#feed-#{rec.id}") end)

      await_supervised_tasks()
    end

    test "the tab strip counts the feed", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Feed")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a .badge", "1")

      await_supervised_tasks()
    end

    test "an own recommendation reads You, not from, and still counts", %{conn: conn} do
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, rec} = Activities.recommend(title, :like, "mine")

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element("#feed-scope-own") |> render_click()

      assert has_element?(view, "#feed-#{rec.id}", "You recommended ·")
      refute has_element?(view, "#feed-#{rec.id}", "Sample Friend")

      # The tab badge counts incoming only; own rows count on the Yours scope.
      refute has_element?(view, "[data-nav-zone='zone-tabs'] a .badge")
      assert has_element?(view, "#feed-scope-own .badge", "1")

      view |> element("#feed-#{rec.id}") |> render_click()
      assert render(view) =~ "You recommended"
      view |> element("#title-watchlist-add") |> render_click()
      assert Discovery.on_watchlist?(999, :movie)

      await_supervised_tasks()
    end

    test "a modal verb with no open modal, or a bad ?title=, is ignored, not a crash", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery?title=book-1")

      refute has_element?(view, "#title-detail-modal #title-watchlist-add")
      render_click(view, "title_watchlist_add", %{})

      assert Process.alive?(view.pid)
      assert Discovery.list_watchlist() == []
    end

    test "watched and tracking rows say who did what, and an own one deletes by kind", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      show = Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})
      episode = %Episode{season_number: 2, episode_number: 5, name: "The Fifth"}

      {:ok, watched} =
        Activities.ingest(
          Event.sign(
            Translation.to_event(:watched, show, [episode: episode], @friend_pubkey),
            @friend_secret
          )
        )

      {:ok, tracked} =
        Activities.ingest(
          Event.sign(Translation.to_event(:tracking, show, [], @friend_pubkey), @friend_secret)
        )

      # One title, two kinds — two rows; the ids differ.
      refute watched.id == tracked.id

      {:ok, mine} =
        Activities.tracking(Title.new!(%{tmdb_id: 42, media_type: :movie, name: "Sample Movie 42"}))

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#feed-#{watched.id}", "Sample Friend watched S02E05")
      assert has_element?(view, "#feed-#{tracked.id}", "Sample Friend started tracking")

      view |> element("#feed-#{watched.id}") |> render_click()
      assert render(view) =~ "Sample Friend watched S02E05"
      refute has_element?(view, "#title-activity-delete")
      render_hook(view, "close_title", %{})

      view |> element("#feed-scope-own") |> render_click()
      assert has_element?(view, "#feed-#{mine.id}", "You started tracking")
      view |> element("#feed-#{mine.id}") |> render_click()
      view |> element("#title-activity-delete", "Delete tracking activity") |> render_click()
      assert render(view) =~ "Tracking activity withdrawn"
      refute has_element?(view, "#feed-#{mine.id}")
      await_supervised_tasks()
    end

    test "Yours shows own rows with Delete; Incoming hides them; delete withdraws", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, theirs} = Activities.ingest(friend_event(777, nil))
      title = Title.new!(%{tmdb_id: 42, media_type: :movie, name: "Sample Movie 42"})
      {:ok, mine} = Activities.recommend(title, :like, "mine")

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#feed-#{theirs.id}")
      refute has_element?(view, "#feed-#{mine.id}")

      # A friend's recommendation carries no Delete verb in its modal.
      view |> element("#feed-#{theirs.id}") |> render_click()
      refute has_element?(view, "#title-activity-delete")
      render_hook(view, "close_title", %{})

      view |> element("#feed-scope-own") |> render_click()
      assert has_element?(view, "#feed-scope-own.zone-tab-active")
      assert has_element?(view, "#feed-#{mine.id}", "You")
      refute has_element?(view, "#feed-#{theirs.id}")

      view |> element("#feed-#{mine.id}") |> render_click()
      view |> element("#title-activity-delete", "Delete recommendation") |> render_click()
      assert_patch(view, "/discovery")
      refute has_element?(view, "#feed-#{mine.id}")
      assert render(view) =~ "Recommendation withdrawn"
      assert render(view) =~ "Titles you recommend from their detail page show up here"
      assert Activities.list_sent() == []

      await_supervised_tasks()
    end

    test "a friend's deletion removes their row without a reload", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      now = System.os_time(:second)
      title = Title.new!(%{tmdb_id: 779, media_type: :movie, name: "Sample Movie 779"})

      event =
        Event.sign(
          %{
            Translation.to_event(:recommendation, title, [note: nil], @friend_pubkey)
            | created_at: now - 5
          },
          @friend_secret
        )

      {:ok, rec} = Activities.ingest(event)

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#feed-#{rec.id}")

      deletion =
        Event.sign(
          Translation.to_deletion(:recommendation, @friend_pubkey, :movie, 779, rec.event_id),
          @friend_secret
        )

      {:ok, _gone} = Activities.ingest(deletion)
      render_until(view, fn _html -> not has_element?(view, "#feed-#{rec.id}") end)

      await_supervised_tasks()
    end

    test "neither the row nor the modal offers Recommend", %{conn: conn} do
      {:ok, _item} =
        Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      refute render(view) =~ "Recommend to your friends"
      refute has_element?(view, "#recommend-modal")
      await_supervised_tasks()
    end
  end

  describe "title detail modal" do
    setup do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        config
        |> Map.put(:prowlarr_url, "http://prowlarr.test")
        |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)
      :ok
    end

    defp released_movie do
      Title.new!(%{
        tmdb_id: 777,
        media_type: :movie,
        name: "Sample Movie",
        year: "2005",
        release_date: ~D[2005-01-01]
      })
    end

    test "the modal opens from the snapshot, then dresses itself from the live TMDB detail",
         %{conn: conn} do
      # A ready TMDB capability: a key in config plus a passed test.
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        Map.put(config, :tmdb_api_key, MediaCentaur.Secret.wrap("test-key"))
      )

      MediaCentaur.Capabilities.save_test_result(:tmdb, :ok)

      TmdbStubs.stub_get_movie(
        777,
        TmdbStubs.movie_detail(%{
          "id" => 777,
          "title" => "Sample Movie",
          "tagline" => "Every confirmation counts.",
          "backdrop_path" => "/sample-backdrop.jpg",
          "images" => %{"logos" => [%{"iso_639_1" => "en", "file_path" => "/sample-logo.png"}]}
        })
      )

      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")

      # Snapshot first: the modal is open before TMDB answers.
      assert has_element?(view, "#title-detail-modal #title-download")
      refute html =~ "Every confirmation counts."

      html = render_async(view)
      assert html =~ "Every confirmation counts."
      assert has_element?(view, "#title-detail-modal [data-component='preview-body']")
      assert html =~ "sample-backdrop.jpg"
      assert html =~ "sample-logo.png"
      await_supervised_tasks()
    end

    test "a watchlist card click opens the modal via the URL; close returns", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      view |> element("#watchlist-item-movie-777") |> render_click()

      assert_patch(view, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#title-detail-modal #title-download")
      assert has_element?(view, "#title-detail-modal #title-watchlist-remove")

      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery/watchlist")
      await_supervised_tasks()
    end

    test "Download creates an automatic plan, closes the modal, flashes, and the row shows the state",
         %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-download") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      assert render(view) =~ "Finding a release for Sample Movie"
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      # Nothing found → the plan is ready with a gap → Needs review on the row.
      render_until(view, fn _html -> has_element?(view, "#watchlist-item-movie-777", "Needs review") end)
    end

    test "a series Download offers season 1 and the scope menu's Download all", %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()

      show =
        Title.new!(%{
          tmdb_id: 246_810,
          media_type: :tv_series,
          name: "Sample Show",
          year: "2010",
          release_date: ~D[2010-01-01]
        })

      {:ok, _} = Discovery.add_to_watchlist(show)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      assert has_element?(view, "#title-download", "Download season 1")
      refute has_element?(view, "#title-scope-menu")

      view |> element("#title-scope-toggle") |> render_click()
      assert has_element?(view, "#title-scope-menu", "Download all")

      view |> element("#title-scope-menu li", "Download all") |> render_click()
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.tmdb_type == "tv"
      assert %ReleaseTracking.Item{} = ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
    end

    test "Track release from the modal hands off to tracking", %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()

      upcoming =
        Title.new!(%{
          tmdb_id: 246_810,
          media_type: :tv_series,
          name: "Sample Show",
          release_date: ~D[2999-01-01]
        })

      {:ok, _} = Discovery.add_to_watchlist(upcoming)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      view |> element("#title-track") |> render_click()
      assert render(view) =~ "Tracking Sample Show"

      await_supervised_tasks()
      assert %{tmdb_id: 246_810} = ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
    end

    test "Remove from watchlist deletes the item and closes", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-watchlist-remove") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      refute Discovery.on_watchlist?(777, :movie)
      refute has_element?(view, "#watchlist-item-movie-777")
      await_supervised_tasks()
    end

    test "acquisition events refresh the row state without a reload", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      refute has_element?(view, "#watchlist-item-movie-777", "Needs review")

      {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})

      render_until(view, fn _html -> has_element?(view, "#watchlist-item-movie-777", "Needs review") end)
      await_supervised_tasks()
    end
  end

  describe "watchlist tab — provenance" do
    setup do
      Identity.ensure()
      :ok
    end

    test "a friend-sourced watchlist row says who recommended it", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, _} =
        Discovery.add_to_watchlist(rec.title, %{
          source: :friend,
          activity_id: rec.id,
          note: rec.note
        })

      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant[data-sentiment='like']",
               "Sample Friend"
             )

      assert has_element?(view, "#watchlist-item-movie-777", "Watch it.")
      await_supervised_tasks()
    end

    test "a love arriving later stacks a second pennant above the like without a reload", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))
      {:ok, _} = Discovery.add_to_watchlist(rec.title)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant[data-sentiment='like']",
               "Sample Friend"
             )

      {:ok, _love} = Activities.ingest(other_event(777, :love))

      render_until(view, fn _html ->
        has_element?(view, "#watchlist-item-movie-777 .pennant[data-sentiment='love']", "Other Friend")
      end)

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant-mast .pennant:first-child[data-sentiment='love']"
             )

      view |> element("#watchlist-item-movie-777") |> render_click()
      assert has_element?(view, "#title-detail-modal .pennant[data-sentiment='love']", "Other Friend")
      await_supervised_tasks()
    end

    test "a row whose friend is gone shows no marker", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, _} =
        Discovery.add_to_watchlist(rec.title, %{
          source: :friend,
          activity_id: rec.id,
          note: rec.note
        })

      :ok = Social.remove_friend(@friend_pubkey)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "#watchlist-item-movie-777")
      refute has_element?(view, "#watchlist-item-movie-777 .pennant")
      await_supervised_tasks()
    end
  end
end
