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
  alias MediaCentaurWeb.DiscoveryLive.People

  setup do
    TmdbStubs.setup_tmdb_client()
  end

  # The ids of every element matching `selector`, in document order.
  defp ids(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("id")
  end

  test "empty watchlist renders the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#watchlist-empty")
  end

  test "rows show state; the modal offers the honest action per state", %{conn: conn} do
    {:ok, _} =
      Discovery.put_rung(
        Title.new!(%{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          release_date: ~D[2020-01-01]
        }),
        :list
      )

    {:ok, _} =
      Discovery.put_rung(
        Title.new!(%{
          tmdb_id: 42,
          media_type: :tv_series,
          name: "Sample Show",
          release_date: ~D[2999-01-01]
        }),
        :list
      )

    # A presentable movie (container + linked file) owning TMDB id 777.
    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    create_linked_file(%{movie_id: movie.id})

    {:ok, view, html} = live(conn, "/discovery/watchlist")
    assert has_element?(view, "#watchlist-item-movie-777", "In library")
    refute html =~ "Track release"

    # The unaired show has nothing to download: no primary verb, and the
    # tracking-mode control in its modal is the arming surface. The owned
    # movie offers the library detail for its files — and the same
    # tracking-mode control, because an owned title is tracked too and
    # the mode is where you stop it.
    view |> element("#watchlist-item-tv_series-42") |> render_click()
    refute has_element?(view, "#title-download")
    assert has_element?(view, "#title-tracking-mode-follow")
    render_hook(view, "close_title", %{})

    view |> element("#watchlist-item-movie-777") |> render_click()
    assert has_element?(view, "#title-in-library[href='/library?selected=#{movie.id}']")
    assert has_element?(view, "#title-tracking-mode")
    await_supervised_tasks()
  end

  test "watchlist events refresh the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    {:ok, _} =
      Discovery.put_rung(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

    assert render(view) =~ "Sample Movie"
    await_supervised_tasks()
  end

  test "library changes flip a row to In library without a reload", %{conn: conn} do
    {:ok, _} =
      Discovery.put_rung(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

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
      Discovery.put_rung(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    assert has_element?(view, "h1", "Discovery")
    assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
    assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "1")
    await_supervised_tasks()
  end

  test "the watchlist tab does not tell you a row is on the watchlist", %{conn: conn} do
    {:ok, _} =
      Discovery.put_rung(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

    {:ok, view, html} = live(conn, ~p"/discovery/watchlist")

    assert has_element?(view, "[id^='watchlist-item-']")
    refute html =~ "On your list"
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
    @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    defp friend_card, do: "#person-" <> String.slice(@friend_pubkey, 0, 8)

    defp signed(kind, title, opts) do
      Event.sign(Translation.to_event(kind, title, opts, @friend_pubkey), @friend_secret)
    end

    test "shows the add form and points at Settings; no identity, no You card", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Friends")
      assert has_element?(view, "#add-friend-form")
      assert has_element?(view, "#friends-settings-pointer a[href='/settings?section=social']")
      refute has_element?(view, "#person-you")
      refute has_element?(view, "#identity-npub")
      refute has_element?(view, "#add-relay-form")
    end

    test "adds a friend by npub + name, shows their card, and removes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      npub = Keys.to_npub(@friend_pubkey)

      view
      |> form("#add-friend-form", %{"key" => npub, "nickname" => "Sample Friend"})
      |> render_submit()

      assert has_element?(view, friend_card() <> " h2", "Sample Friend")
      assert has_element?(view, friend_card() <> " footer", People.short_npub(@friend_pubkey))
      assert has_element?(view, friend_card(), "Nothing shared yet")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "1")
      assert [%{nickname: "Sample Friend"}] = Social.list_friends()

      view |> element(friend_card() <> " button", "Remove friend") |> render_click()
      refute has_element?(view, friend_card())
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
      refute has_element?(view, friend_card())

      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      render_until(view, fn _html -> has_element?(view, friend_card(), "Sample Friend") end)

      :ok = Social.remove_friend(@friend_pubkey)
      render_until(view, fn _html -> not has_element?(view, friend_card()) end)
    end

    test "a friend's card carries their shelves and presence; a poster opens that act", %{conn: conn} do
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      show = Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})
      episode = %Episode{season_number: 2, episode_number: 5, name: "The Fifth"}
      {:ok, watched} = Activities.ingest(signed(:watched, show, episode: episode))
      {:ok, listed} = Activities.ingest(signed(:listing, show, []))

      movie = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie 777"})

      {:ok, recommended} =
        Activities.ingest(signed(:recommendation, movie, note: "Watch it.", sentiment: :love))

      # The watched act is the newest, so it is the presence line.
      backdate(listed, :acted_at, ~U[2026-09-01 10:00:00Z])
      backdate(recommended, :acted_at, ~U[2026-09-01 09:00:00Z])

      {:ok, view, _html} = live(conn, "/discovery/friends")

      # You first, then the friend; the presence line is the newest act.
      assert ids(view, "[data-component='person-card']") == ["person-you", "person-f9308a01"]

      assert has_element?(
               view,
               friend_card() <> " [data-role='presence']",
               "watched S02E05 of Sample Show"
             )

      assert has_element?(view, friend_card() <> "-watched-#{watched.id}")
      assert has_element?(view, friend_card() <> "-#{listed.id}", "Sample Show")
      assert has_element?(view, friend_card() <> "-#{recommended.id}", "Sample Movie 777")
      assert has_element?(view, friend_card() <> "-#{recommended.id} .text-love")

      view |> element(friend_card() <> "-watched-#{watched.id}") |> render_click()
      assert_patch(view, "/discovery/friends?title=tv_series-1399&activity=#{watched.id}")
      # Who did what is the pennant's to say, not a line under the hero.
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='watched']", "Sample Friend")
      refute has_element?(view, "#title-activity-delete")
      render_hook(view, "close_title", %{})

      # The recommendation opens with its note, attributed, and the named pennant.
      view |> element(friend_card() <> "-#{recommended.id}") |> render_click()
      assert has_element?(view, "#title-note", "Sample Friend")
      assert has_element?(view, "#title-note", "Watch it.")
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='love']", "Sample Friend")

      await_supervised_tasks()
    end

    test "the You card shows what you broadcast and deletes it by kind", %{conn: conn} do
      title = Title.new!(%{tmdb_id: 42, media_type: :movie, name: "Sample Movie 42"})
      {:ok, mine} = Activities.listing(title)

      {:ok, rec} =
        Activities.recommend(
          Title.new!(%{tmdb_id: 99, media_type: :movie, name: "Sample Movie 99"}),
          :like,
          "mine"
        )

      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, "#person-you[data-own]", "How friends see you")
      assert has_element?(view, "#person-you [data-role='presence']", "recommended Sample Movie 99")
      refute has_element?(view, "#person-you footer")

      view |> element("#person-you-#{rec.id}") |> render_click()
      assert has_element?(view, "#title-activity-delete", "Delete recommendation")
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='like']", "You")
      view |> element("#title-watchlist") |> render_click()
      assert Discovery.listed?(99, :movie)
      render_hook(view, "close_title", %{})

      view |> element("#person-you-#{mine.id}") |> render_click()
      view |> element("#title-activity-delete", "Delete listing") |> render_click()
      assert render(view) =~ "Listing withdrawn"
      refute has_element?(view, "#person-you-#{mine.id}")
      assert Enum.map(Activities.list_sent(), & &1.kind) == [:recommendation]

      await_supervised_tasks()
    end

    # An activity's title snapshot carries no poster path, so the only
    # artwork this install can paint for a title it owns is the entity's
    # own poster — the top of the ladder `ActivityPosters` walks.
    test "an activity for a title in the library paints the entity's poster", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie 424242"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "424242"})
      create_linked_file(%{movie_id: movie.id})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      {:ok, watched} =
        Activities.watched(
          Title.new!(%{tmdb_id: 424_242, media_type: :movie, name: "Sample Movie 424242"}),
          nil
        )

      {:ok, view, _html} = live(conn, "/discovery/friends")

      assert has_element?(
               view,
               "#person-you-watched-#{watched.id} img[src^='/media-images/#{movie.id}/poster.jpg']"
             )

      await_supervised_tasks()
    end

    test "a You card with nothing shared says where sharing starts", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, "#person-you", "once sharing is on under Settings → Social")
      refute has_element?(view, "#person-you", "How friends see you")
    end

    test "all N grows the strip in place", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      for tmdb_id <- 1..7 do
        {:ok, _} =
          Activities.ingest(
            signed(
              :watched,
              Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie #{tmdb_id}"}),
              []
            )
          )
      end

      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, friend_card() <> "-watched-all", "all 7")

      assert length(
               ids(view, friend_card() <> " [data-role='watched-strip'] button[phx-value-activity]")
             ) == 5

      view |> element(friend_card() <> "-watched-all") |> render_click()
      refute has_element?(view, friend_card() <> "-watched-all")

      assert length(
               ids(view, friend_card() <> " [data-role='watched-strip'] button[phx-value-activity]")
             ) == 7
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

    defp other_event(tmdb_id, sentiment),
      do: other_event(tmdb_id, nil, sentiment, System.os_time(:second))

    # Every helper stamps the wire time and the domain time alike, so
    # the feed's order (by `acted_at`) is the order the test wrote.
    defp other_event(tmdb_id, note, sentiment, at) do
      title = Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: "Sample Movie #{tmdb_id}"})

      Event.sign(
        Translation.to_event(
          :recommendation,
          title,
          [note: note, sentiment: sentiment],
          @other_pubkey,
          created_at: at,
          acted_at: at
        ),
        @other_secret
      )
    end

    defp friend_event(tmdb_id, note, sentiment \\ :like, at \\ System.os_time(:second)) do
      title =
        Title.new!(%{
          tmdb_id: tmdb_id,
          media_type: :movie,
          name: "Sample Movie #{tmdb_id}",
          year: "2024"
        })

      Event.sign(
        Translation.to_event(
          :recommendation,
          title,
          [note: note, sentiment: sentiment],
          @friend_pubkey,
          created_at: at,
          acted_at: at
        ),
        @friend_secret
      )
    end

    defp friend_listing_event(tmdb_id, at \\ System.os_time(:second)) do
      title =
        Title.new!(%{
          tmdb_id: tmdb_id,
          media_type: :movie,
          name: "Sample Movie #{tmdb_id}",
          year: "2024"
        })

      Event.sign(
        Translation.to_event(:listing, title, [], @friend_pubkey, created_at: at, acted_at: at),
        @friend_secret
      )
    end

    defp entry(%{id: id}), do: "#feed-entry-#{id}"
    defp entries(view), do: ids(view, "[data-component='feed-entry']")
    defp feed_badge, do: "[data-nav-zone='zone-tabs'] a[href='/discovery'] .badge"

    test "empty state names the prerequisites, then the quiet empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Feed")

      # Unready: the copy explains the mechanism and both prerequisites are
      # offered as actions rather than named in prose the reader has to parse.
      assert render(view) =~ "What your friends recommend and want to watch lands here"
      assert render(view) =~ "Media Centaur reaches your friends over a relay"
      assert has_element?(view, "#feed-empty a[href='/settings?section=social']")
      assert has_element?(view, "#feed-empty a[href='/discovery/friends']")

      {:ok, _relay} = Social.add_relay("wss://relay.example")
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, view, _html} = live(conn, "/discovery")
      assert render(view) =~ "Each friend&#39;s action is one entry, newest first."
      refute has_element?(view, "#feed-empty a[href='/settings?section=social']")
    end

    test "a recommendation entry: name, verb, time, title, year, note; no pennant; opens the modal",
         %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, rec} =
        Activities.ingest(friend_event(777, "Watch it.", :love, System.os_time(:second) - 7200))

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(
               view,
               entry(rec) <> "[data-kind='recommendation'] [data-role='who']",
               "Sample Friend"
             )

      assert has_element?(view, entry(rec) <> " [data-role='who']", "recommended")
      assert has_element?(view, entry(rec) <> " [data-role='who']", "2h ago")
      assert has_element?(view, entry(rec) <> " [data-role='who'] [data-role='love']")
      assert has_element?(view, entry(rec) <> " [data-role='title']", "Sample Movie 777")
      assert has_element?(view, entry(rec) <> " [data-role='title']", "2024")
      assert has_element?(view, entry(rec) <> " [data-role='note']", "Watch it.")
      refute has_element?(view, entry(rec) <> " .pennant")
      # The toolbar's seat is always in the DOM — hover only reveals it.
      assert has_element?(view, entry(rec) <> " [data-role='toolbar'] " <> entry(rec) <> "-list", "List")

      assert has_element?(
               view,
               entry(rec) <> " [data-role='toolbar'] " <> entry(rec) <> "-download",
               "Download"
             )

      assert has_element?(
               view,
               entry(rec) <> " [data-role='toolbar'] " <> entry(rec) <> "-ignore",
               "Ignore"
             )

      # The card opens the modal, which still flies the pennant and shows the note.
      view |> element(entry(rec)) |> render_click()
      assert_patch(view, "/discovery?title=movie-777&activity=#{rec.id}")
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='love']", "Sample Friend")
      assert has_element?(view, "#title-note", "Watch it.")

      view |> element("#title-watchlist") |> render_click()
      assert Discovery.listed?(777, :movie)
      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery")

      assert [%{intent: %{source: :friend, activity_id: rec_id, note: "Watch it."}}] =
               Discovery.list_watchlist()

      assert rec_id == rec.id
      await_supervised_tasks()
    end

    test "a listing entry: name, wants to watch, time, title, year — and no note line", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, listing} = Activities.ingest(friend_listing_event(777))

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(
               view,
               entry(listing) <> "[data-kind='listing'] [data-role='who']",
               "Sample Friend"
             )

      assert has_element?(view, entry(listing) <> " [data-role='who']", "wants to watch")
      assert has_element?(view, entry(listing) <> " [data-role='title']", "Sample Movie 777")
      refute has_element?(view, entry(listing) <> " [data-role='note']")
      refute has_element?(view, entry(listing) <> " [data-role='love']")
      refute has_element?(view, entry(listing) <> " .pennant")
      await_supervised_tasks()
    end

    test "Like adds nothing to the first line", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil, :like))

      {:ok, view, _html} = live(conn, "/discovery")
      refute has_element?(view, entry(rec) <> " [data-role='love']")
      refute has_element?(view, entry(rec) <> " [data-role='note']")
      await_supervised_tasks()
    end

    test "one entry per action, newest first: two friends on a title, one friend twice", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
      now = System.os_time(:second)
      {:ok, mine} = Activities.ingest(friend_event(777, "Watch it."))
      {:ok, theirs} = Activities.ingest(other_event(777, "Agreed.", :love, now + 60))
      {:ok, listed} = Activities.ingest(friend_listing_event(777, now + 120))
      {:ok, quiet} = Activities.ingest(other_event(778, nil, :like, now - 600))

      {:ok, view, _html} = live(conn, "/discovery")

      assert entries(view) == [
               "feed-entry-#{listed.id}",
               "feed-entry-#{theirs.id}",
               "feed-entry-#{mine.id}",
               "feed-entry-#{quiet.id}"
             ]

      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "4")
      assert has_element?(view, entry(theirs) <> " [data-role='note']", "Agreed.")
      assert has_element?(view, entry(mine) <> " [data-role='note']", "Watch it.")
      refute has_element?(view, "[data-component='feed-entry'] .pennant")

      # The modal speaks for the newest recommendation — its note, attributed —
      # and flies both pennants.
      view |> element(entry(listed)) |> render_click()
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='love']", "Other Friend")
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='like']", "Sample Friend")
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='listing']", "Sample Friend")

      await_supervised_tasks()
    end

    test "watched actions, own actions and a former friend's actions never make an entry", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
      show = Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})
      episode = %Episode{season_number: 2, episode_number: 5, name: "The Fifth"}

      {:ok, _watched} =
        Activities.ingest(
          Event.sign(
            Translation.to_event(:watched, show, [episode: episode], @friend_pubkey),
            @friend_secret
          )
        )

      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, _mine} = Activities.recommend(title, :like, "mine")
      {:ok, _own_listing} = Activities.listing(title)

      {:ok, _former} = Activities.ingest(other_event(778, :love))
      :ok = Social.remove_friend(@other_pubkey)

      {:ok, view, _html} = live(conn, "/discovery")
      assert entries(view) == []
      refute has_element?(view, feed_badge())
      assert render(view) =~ "What your friends recommend and want to watch lands here"

      await_supervised_tasks()
    end

    test "a title the library has reads In library in the toolbar and in the modal", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")
      assert has_element?(view, entry(rec) <> "[data-download-slot='In library']")
      refute has_element?(view, entry(rec) <> "-download")
      assert has_element?(view, "#title-in-library[href='/library?selected=#{movie.id}']", "In library")

      await_supervised_tasks()
    end

    test "a received recommendation or listing appears without a reload", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery")

      {:ok, rec} = Activities.ingest(friend_event(778, "live"))
      render_until(view, fn _html -> has_element?(view, entry(rec)) end)

      {:ok, listing} = Activities.ingest(friend_listing_event(779))
      render_until(view, fn _html -> has_element?(view, entry(listing)) end)
      assert has_element?(view, feed_badge(), "2")

      await_supervised_tasks()
    end

    test "List toggles the bottom rung with the entry's provenance; Following is plain state", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, entry(rec) <> "[data-list-slot='list']")

      view |> element(entry(rec) <> "-list", "List") |> render_click()
      assert Discovery.rung(777, :movie) == :list

      assert %{source: :friend, activity_id: rec_id, note: "Watch it."} =
               Discovery.get_intent(777, :movie)

      assert rec_id == rec.id
      assert has_element?(view, entry(rec) <> "[data-list-slot='listed']")

      view |> element(entry(rec) <> "-list", "Listed") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      assert has_element?(view, entry(rec) <> "[data-list-slot='list']")

      {:ok, _intent} = ReleaseTracking.set_rung(released_movie(), :ask)

      render_until(view, fn _html -> has_element?(view, entry(rec) <> "[data-list-slot='following']") end)

      assert has_element?(view, entry(rec) <> " [data-role='toolbar']", "Following")
      refute has_element?(view, entry(rec) <> "-list")

      await_supervised_tasks()
    end

    test "Download starts the automatic plan and flashes; the slot then reads the state", %{conn: conn} do
      stub_prowlarr()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec) <> "-download") |> render_click()

      assert render(view) =~ "Finding a release for Sample Movie 777"
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      # Nothing found → the plan is ready with a gap → Needs review in the slot.
      render_until(view, fn _html ->
        has_element?(view, entry(rec) <> "[data-download-slot='Needs review']")
      end)

      refute has_element?(view, entry(rec) <> "-download")
    end

    test "Ignore removes every entry for the title, with provenance; Undo puts them back", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))
      {:ok, theirs} = Activities.ingest(other_event(777, :love))
      {:ok, other_title} = Activities.ingest(other_event(778, :like))

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, feed_badge(), "3")

      view |> element(entry(rec) <> "-ignore") |> render_click()

      assert Discovery.rung(777, :movie) == :ignored

      assert %{source: :friend, activity_id: rec_id, note: "Watch it."} =
               Discovery.get_intent(777, :movie)

      assert rec_id == rec.id
      refute has_element?(view, entry(rec))
      refute has_element?(view, entry(theirs))
      assert has_element?(view, entry(other_title))
      assert has_element?(view, feed_badge(), "1")
      assert has_element?(view, "#ignore-undo", "Sample Movie 777")

      view |> element("#ignore-undo-action") |> render_click()

      assert Discovery.rung(777, :movie) == nil
      assert has_element?(view, entry(rec))
      assert has_element?(view, entry(theirs))
      refute has_element?(view, "#ignore-undo")
      await_supervised_tasks()
    end

    test "Undo restores the rung the title had; the toast's own dismiss only clears the toast", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))
      {:ok, _} = Discovery.put_rung(released_movie(), :list)

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec) <> "-ignore") |> render_click()
      assert Discovery.rung(777, :movie) == :ignored

      view |> element("#ignore-undo-action") |> render_click()
      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, entry(rec))

      view |> element(entry(rec) <> "-ignore") |> render_click()
      render_hook(view, "ignore_undo_dismiss", %{})
      refute has_element?(view, "#ignore-undo")
      assert Discovery.rung(777, :movie) == :ignored
      await_supervised_tasks()
    end

    test "a title not on the list offers Add to watchlist; the tracking controls appear once it is listed",
         %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec)) |> render_click()

      # Two acts, in order (UIDR-039): the bookmark beside Download is the
      # only verb a title that is not on the list offers; the tracking
      # block below is empty, so nothing above List is reachable.
      assert has_element?(view, "#title-watchlist[aria-pressed='false'][phx-value-choice='list']")
      assert has_element?(view, "#title-tracking-mode[data-rung='off'][data-form='none']")
      refute has_element?(view, "#title-tracking-mode [data-nav-item]")

      view |> element("#title-watchlist") |> render_click()

      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, "#title-watchlist[aria-pressed='true'][phx-value-choice='off']")
      assert has_element?(view, "#title-tracking-mode[data-rung='list'][data-form='controls']")
      assert has_element?(view, "#title-tracking-mode-list[aria-pressed='true']")
      assert has_element?(view, "#title-tracking-mode-follow")

      # At Follow the bookmark is a marker: filled, and no click to tear
      # the calendar down — Off lives in the tracking controls. Following
      # fetches the calendar, so the movie is stubbed with a date to come.
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_movie(
        777,
        TmdbStubs.movie_detail(%{"id" => 777, "release_date" => "2999-01-01"})
      )

      view |> element("#title-tracking-mode-follow") |> render_click()
      await_supervised_tasks()
      assert has_element?(view, "#title-watchlist[aria-pressed='true']")
      refute has_element?(view, "#title-watchlist[phx-click]")

      # Off takes it back off the list, and the strip's bookmark empties again.
      view |> element("#title-tracking-mode-off") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      assert has_element?(view, "#title-watchlist[aria-pressed='false']")
      assert has_element?(view, "#title-tracking-mode[data-form='none']")
    end

    test "an ignored title says so and offers Add to watchlist, which replaces Ignore", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))
      {:ok, _} = Discovery.put_rung(released_movie(), :ignored)

      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")
      refute has_element?(view, entry(rec))
      assert has_element?(view, "#title-tracking-mode[data-rung='ignored'][data-form='ignored']")
      assert has_element?(view, "#title-watchlist[aria-pressed='false'][phx-value-choice='list']")
      assert render(view) =~ "Hidden from the Feed"

      view |> element("#title-watchlist") |> render_click()
      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, "#title-tracking-mode-follow")
    end

    test "the tracking controls' Ignore removes the entry and keeps the modal; no Ignore on the watchlist",
         %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))
      {:ok, _} = Discovery.put_rung(released_movie(), :list)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "#watchlist-item-movie-777")
      refute has_element?(view, "#watchlist-item-movie-777-ignore")

      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")
      view |> element("#title-tracking-mode-ignored") |> render_click()

      assert Discovery.rung(777, :movie) == :ignored
      refute has_element?(view, entry(rec))
      assert has_element?(view, "#title-tracking-mode[data-rung='ignored']")
      refute has_element?(view, "#ignore-undo")

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      refute has_element?(view, "#watchlist-item-movie-777")
      await_supervised_tasks()
    end

    test "the tab strip counts the entries in the window", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _rec} = Activities.ingest(friend_event(777, nil))
      {:ok, _listing} = Activities.ingest(friend_listing_event(777))

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Feed")
      assert has_element?(view, feed_badge(), "2")

      await_supervised_tasks()
    end

    test "the window holds a page; Show older widens it", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      now = System.os_time(:second)

      for offset <- 1..51,
          do: {:ok, _} = Activities.ingest(friend_listing_event(1000 + offset, now - offset))

      {:ok, view, _html} = live(conn, "/discovery")
      assert length(entries(view)) == 50
      assert has_element?(view, feed_badge(), "50")
      assert has_element?(view, "#feed-show-older", "Show older")

      view |> element("#feed-show-older") |> render_click()
      assert length(entries(view)) == 51
      assert has_element?(view, feed_badge(), "51")
      refute has_element?(view, "#feed-show-older")

      await_supervised_tasks()
    end

    test "a modal verb with no open modal, or a bad ?title=, is ignored, not a crash", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery?title=book-1")

      refute has_element?(view, "#title-detail-modal #title-tracking-mode")
      render_click(view, "set_rung", %{"choice" => "list", "ref" => "movie-1"})
      render_click(view, "feed_list", %{"activity" => Ecto.UUID.generate()})
      render_click(view, "feed_download", %{"activity" => Ecto.UUID.generate()})
      render_click(view, "ignore_title", %{"activity" => Ecto.UUID.generate()})

      assert Process.alive?(view.pid)
      assert Discovery.list_watchlist() == []
    end

    test "a friend's withdrawal removes the entry without a reload", %{conn: conn} do
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
      {:ok, listing} = Activities.ingest(friend_listing_event(779, now - 5))

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, entry(rec))
      assert has_element?(view, entry(listing))

      for {kind, row} <- [recommendation: rec, listing: listing] do
        deletion =
          Event.sign(
            Translation.to_deletion(kind, @friend_pubkey, :movie, 779, row.event_id),
            @friend_secret
          )

        {:ok, _gone} = Activities.ingest(deletion)
        render_until(view, fn _html -> not has_element?(view, entry(row)) end)
      end

      await_supervised_tasks()
    end

    test "neither the entry nor the modal offers Recommend", %{conn: conn} do
      {:ok, _item} =
        Discovery.put_rung(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      refute render(view) =~ "Recommend to your friends"
      # `show_discovery` is off here, so the modal's Recommend control is
      # never rendered and nothing can open the flow.
      refute has_element?(view, "#title-recommend")
      # The container itself mounts unconditionally, same as every other
      # `RecommendFlow` host (`EntityModal`'s) — only its open state is
      # gated, so absence is asserted on the open state.
      refute has_element?(view, "#recommend-modal[data-state='open']")
      await_supervised_tasks()
    end
  end

  # A configured, empty indexer: a one-click download plans, finds
  # nothing, and parks the plan as Needs review.
  defp stub_prowlarr do
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

  describe "title detail modal" do
    setup do
      stub_prowlarr()
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

      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")

      # Snapshot first: the modal is open before TMDB answers.
      assert has_element?(view, "#title-detail-modal #title-download")
      refute html =~ "Every confirmation counts."

      # The stubbed detail fetch plus the preview build outrun the 100ms
      # default under a loaded suite; the budget matches the other views'.
      html = render_async(view, 1_000)
      assert html =~ "Every confirmation counts."
      # The preview's metadata row takes the hero's type line; its facets follow the overview.
      assert has_element?(view, "#title-detail-modal .badge", "Movie")
      assert has_element?(view, "#title-detail-modal", "Director")
      assert html =~ "sample-backdrop.jpg"
      assert html =~ "sample-logo.png"
      await_supervised_tasks()
    end

    test "a watchlist card click opens the modal via the URL; close returns", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      view |> element("#watchlist-item-movie-777") |> render_click()

      assert_patch(view, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#title-detail-modal #title-download")
      assert has_element?(view, "#title-detail-modal #title-tracking-mode")

      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery/watchlist")
      await_supervised_tasks()
    end

    test "the Recommend control follows the friend-network preference", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, ~p"/discovery/watchlist")

      # Open whatever row this test module's setup put on the watchlist.
      view
      |> element("[data-component='title-row']")
      |> render_click()

      # `show_discovery` is default-off: Discovery is a preview, and
      # Recommend is the one control on this modal that belongs to it.
      refute has_element?(view, "#title-recommend")

      Settings.find_or_create_entry!(%{
        key: DiscoveryVisibility.setting_key(),
        value: %{"enabled" => true}
      })

      render_until(view, fn _html -> has_element?(view, "#title-recommend") end)
    end

    test "Download creates an automatic plan, closes the modal, flashes, and the row shows the state",
         %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
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

      {:ok, _} = Discovery.put_rung(show, :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      assert has_element?(view, "#title-download", "Download season 1")
      refute has_element?(view, "#title-scope-menu")

      view |> element("#title-scope-toggle") |> render_click()
      assert has_element?(view, "#title-scope-menu", "Download all")
      # Downloading is not a watchlist act: the menu carries no entry that
      # follows the series (campaign: the watchlist is the single entry point).
      refute has_element?(view, "#title-scope-menu", "Download all and track")
      refute has_element?(view, "#title-scope-menu [phx-value-track]")

      view |> element("#title-scope-menu li") |> render_click()
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.tmdb_type == "tv"

      # Downloading what has aired says nothing about what is to come: the
      # title stays where the person put it, at List.
      refute ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
      assert Discovery.rung(246_810, :tv_series) == :list
    end

    test "raising the rung on a listed title follows it — tracked, at that rung", %{
      conn: conn
    } do
      TmdbStubs.stub_series_universe_for_targeting()

      upcoming =
        Title.new!(%{
          tmdb_id: 246_810,
          media_type: :tv_series,
          name: "Sample Show",
          release_date: ~D[2999-01-01]
        })

      {:ok, _} = Discovery.put_rung(upcoming, :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      # Listed but not followed: the control reads List, and nothing
      # tracking-shaped shows.
      assert has_element?(view, "#title-tracking-mode[data-rung='list']")
      refute has_element?(view, "#title-release-timeline")

      view |> element("#title-tracking-mode-ask") |> render_click()
      assert render(view) =~ "Tracking Sample Show"

      await_supervised_tasks()
      assert Discovery.rung(246_810, :tv_series) == :ask
      assert ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)

      # The broadcast lands the timeline and the mode on the open modal
      # and the row.
      render_until(view, fn _html -> has_element?(view, "#title-tracking-mode[data-rung='ask']") end)
      assert has_element?(view, "#title-release-timeline")
      assert has_element?(view, "#watchlist-item-tv_series-246810", "Tracking: Ask")
    end

    test "moving the rung on a followed title; Off deletes the record and the row", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :default)
      item = create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#title-tracking-mode[data-rung='default']")

      view |> element("#title-tracking-mode-grab") |> render_click()
      assert Discovery.rung(777, :movie) == :grab
      assert has_element?(view, "#title-tracking-mode[data-rung='grab']")

      view |> element("#title-tracking-mode-off") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title too"
      refute has_element?(view, "#title-release-timeline")
      await_supervised_tasks()
    end

    test "a list row shows its rung as a marker and never a control; List shows nothing", %{
      conn: conn
    } do
      create_tracking_item(%{
        tmdb_id: 777,
        media_type: :movie,
        name: "Sample Movie",
        rung: :follow
      })

      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      assert has_element?(view, "#watchlist-item-movie-777", "Tracking: Follow")
      refute has_element?(view, "#watchlist-item-movie-777 [data-component='intent-control']")

      {:ok, _} = Discovery.put_rung(released_movie(), :list)

      render_until(view, fn _html ->
        not has_element?(view, "#watchlist-item-movie-777", "Tracking:")
      end)

      await_supervised_tasks()
    end

    test "a watchlist row states its next release date", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      item = create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 1),
        title: "Digital",
        release_type: "digital",
        released: false
      })

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "#watchlist-item-movie-777", "Next: Tomorrow")
      await_supervised_tasks()
    end

    test "the modal shows the timeline and activity for a tracked title", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :follow)
      item = create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 3),
        title: "Digital",
        release_type: "digital",
        released: false
      })

      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")

      assert has_element?(view, "#title-release-timeline-next", "Digital release")
      refute html =~ "Tracking since"
      await_supervised_tasks()
    end

    test "Off forgets the title and drops both its row and the modal on this page", %{
      conn: conn
    } do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-tracking-mode-off") |> render_click()

      refute Discovery.listed?(777, :movie)
      refute has_element?(view, "#watchlist-item-movie-777")
      # Nothing left to show: this page's titles *are* the list, so once
      # the record is gone the modal has no title to render.
      refute has_element?(view, "#title-tracking-mode")
      await_supervised_tasks()
    end

    test "acquisition events refresh the row state without a reload", %{conn: conn} do
      {:ok, _} = Discovery.put_rung(released_movie(), :list)
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
        Discovery.put_rung(rec.title, :list, %{
          source: :friend,
          activity_id: rec.id,
          note: rec.note
        })

      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant[data-flag='like']",
               "Sample Friend"
             )

      assert has_element?(view, "#watchlist-item-movie-777", "Watch it.")
      await_supervised_tasks()
    end

    test "a love arriving later stacks a second pennant above the like without a reload", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))
      {:ok, _} = Discovery.put_rung(rec.title, :list)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant[data-flag='like']",
               "Sample Friend"
             )

      {:ok, _love} = Activities.ingest(other_event(777, :love))

      render_until(view, fn _html ->
        has_element?(view, "#watchlist-item-movie-777 .pennant[data-flag='love']", "Other Friend")
      end)

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant-mast .pennant:first-child[data-flag='love']"
             )

      view |> element("#watchlist-item-movie-777") |> render_click()
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='love']", "Other Friend")
      await_supervised_tasks()
    end

    test "a friend who watched a listed title flies a watched pennant on the row and the modal", %{
      conn: conn
    } do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      {:ok, _} = Discovery.put_rung(title, :list)

      watched =
        Event.sign(
          Translation.to_event(:watched, title, [episode: nil], @friend_pubkey,
            created_at: 1_700_000_000
          ),
          @friend_secret
        )

      {:ok, _} = Activities.ingest(watched)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      assert has_element?(
               view,
               "#watchlist-item-movie-777 .pennant[data-flag='watched']",
               "Sample Friend"
             )

      view |> element("#watchlist-item-movie-777") |> render_click()
      assert has_element?(view, "#title-detail-modal .pennant[data-flag='watched']", "Sample Friend")
      refute has_element?(view, "#title-activity-delete")
      await_supervised_tasks()
    end

    test "your own listing broadcast is not narrated back on the watchlist", %{conn: conn} do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      {:ok, _} = Discovery.put_rung(title, :follow)
      {:ok, _} = Activities.listing(title)

      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")
      refute has_element?(view, "#watchlist-item-movie-777 .pennant")
      refute has_element?(view, "#title-detail-modal .pennant")
      refute has_element?(view, "#title-activity-delete")
      refute html =~ "wants to watch"
      await_supervised_tasks()
    end

    test "a row whose friend is gone shows no marker", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, _} =
        Discovery.put_rung(rec.title, :list, %{
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
