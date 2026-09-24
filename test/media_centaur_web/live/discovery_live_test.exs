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
  alias MediaCentaur.Activities.Publisher
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Preferences.DiscoveryVisibility
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.IncomingLive.PlanQuery
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.People

  setup do
    TmdbStubs.setup_tmdb_client()
  end

  # Lists `title` the way the app does — through `Discovery.put_rung/3`,
  # so the page hears the rung change — with the TMDB store holding the
  # title first (ADR-071): a listed row paints from the store, and in the
  # app a title is listed from its detail, which the store already holds.
  # `payload` is the detail the store is seeded with; the default is the
  # title's own name and date.
  defp list(title, rung, attrs \\ %{}, payload \\ nil) do
    create_title_record(%{
      tmdb_id: title.tmdb_id,
      media_type: title.media_type,
      payload: payload || TmdbStubs.detail_for(title)
    })

    Discovery.put_rung(title, rung, attrs)
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

  test "the page root declares its modal params transient, comma-separated", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    assert has_element?(
             view,
             "[data-page-behavior='discovery'][data-nav-transient-params='title,entity,view,activity']"
           )
  end

  test "rows show state; the modal offers the honest action per state", %{conn: conn} do
    {:ok, _} =
      list(
        Title.new!(%{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          release_date: ~D[2020-01-01]
        }),
        :list
      )

    {:ok, _} =
      list(
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
    refute has_element?(view, "#detail-download")
    assert has_element?(view, "#detail-tracking-controls-track")
    render_hook(view, "close_title", %{})

    # An owned movie plays where it is: Play in the action row, no bridge.
    view |> element("#watchlist-item-movie-777") |> render_click()
    assert has_element?(view, "#detail-modal button[phx-click='play'][phx-value-id='#{movie.id}']")
    assert has_element?(view, "#detail-tracking-controls[data-form='controls']")
    refute has_element?(view, "#detail-tracking-controls-grab")
    await_supervised_tasks()
  end

  test "watchlist events refresh the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    {:ok, _} =
      list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

    assert render(view) =~ "Sample Movie"
    await_supervised_tasks()
  end

  test "library changes flip a row to In library without a reload", %{conn: conn} do
    {:ok, _} =
      list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

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
      list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

    {:ok, view, _html} = live(conn, "/discovery/watchlist")

    assert has_element?(view, "h1", "Discovery")
    assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
    assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "1")
    await_supervised_tasks()
  end

  test "the watchlist tab does not tell you a row is on the watchlist", %{conn: conn} do
    {:ok, _} =
      list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

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

      {:ok, reviewed} =
        Activities.ingest(signed(:review, movie, text: "Watch it.", sentiment: :love))

      # The watched act is the newest, so it is the presence line.
      backdate(listed, :acted_at, ~U[2026-09-01 10:00:00Z])
      backdate(reviewed, :acted_at, ~U[2026-09-01 09:00:00Z])

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
      assert has_element?(view, friend_card() <> "-#{reviewed.id}", "Sample Movie 777")
      assert has_element?(view, friend_card() <> "-#{reviewed.id} .text-love")

      view |> element(friend_card() <> "-watched-#{watched.id}") |> render_click()
      assert_patch(view, "/discovery/friends?title=tv_series-1399&activity=#{watched.id}")
      # Who did what is the pennant's to say, not a line under the hero.
      assert has_element?(view, "#detail-modal .pennant[data-flag='watched']", "Sample Friend")
      refute has_element?(view, "#detail-activity-delete")
      render_hook(view, "close_title", %{})

      # The review opens with its note, attributed, and the named pennant.
      view |> element(friend_card() <> "-#{reviewed.id}") |> render_click()
      assert has_element?(view, "#detail-note", "Sample Friend")
      assert has_element?(view, "#detail-note", "Watch it.")
      assert has_element?(view, "#detail-modal .pennant[data-flag='love']", "Sample Friend")

      await_supervised_tasks()
    end

    test "the You card shows what you broadcast and deletes it by kind", %{conn: conn} do
      {:ok, rec} =
        Activities.review(
          Title.new!(%{tmdb_id: 99, media_type: :movie, name: "Sample Movie 99"}),
          :like,
          "mine"
        )

      # Listed last, so the presence line — the latest act — is the listing.
      title = Title.new!(%{tmdb_id: 42, media_type: :movie, name: "Sample Movie 42"})
      {:ok, mine} = Activities.listing(title)

      {:ok, view, _html} = live(conn, "/discovery/friends")
      assert has_element?(view, "#person-you[data-own]", "How friends see you")
      assert has_element?(view, "#person-you [data-role='presence']", "want to watch Sample Movie 42")
      refute has_element?(view, "#person-you [data-role='presence']", "wants to watch")
      refute has_element?(view, "#person-you footer")

      view |> element("#person-you-#{rec.id}") |> render_click()
      assert has_element?(view, "#detail-activity-delete", "Delete review")
      assert has_element?(view, "#detail-modal .pennant[data-flag='like']", "You")
      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Discovery.listed?(99, :movie)
      render_hook(view, "close_title", %{})

      view |> element("#person-you-#{mine.id}") |> render_click()
      view |> element("#detail-activity-delete", "Delete listing") |> render_click()
      assert render(view) =~ "Listing withdrawn"
      refute has_element?(view, "#person-you-#{mine.id}")
      # With the listing withdrawn the presence falls back to the review.
      assert has_element?(view, "#person-you [data-role='presence']", "reviewed Sample Movie 99")
      assert Enum.map(Activities.list_sent(), & &1.kind) == [:review]

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
          :review,
          title,
          [text: note, sentiment: sentiment],
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
          :review,
          title,
          [text: note, sentiment: sentiment],
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

    defp entry(%{id: id}), do: "#feed-row-#{id}"
    defp entries(view), do: ids(view, "[data-component='feed-row']")
    defp feed_badge, do: "[data-nav-zone='zone-tabs'] a[href='/discovery'] .badge"

    test "empty state names the prerequisites, then the quiet empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Feed")

      # Unready: the copy explains the mechanism and both prerequisites are
      # offered as actions rather than named in prose the reader has to parse.
      assert render(view) =~ "What your friends review and want to watch lands here"
      assert render(view) =~ "Media Centaur reaches your friends over a relay"
      assert has_element?(view, "#feed-empty a[href='/settings?section=social']")
      assert has_element?(view, "#feed-empty a[href='/discovery/friends']")

      {:ok, _relay} = Social.add_relay("wss://relay.example")
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, view, _html} = live(conn, "/discovery")
      assert render(view) =~ "What you and your friends review and want to watch lands here"
      assert render(view) =~ "Each action is one row, newest first."
      refute has_element?(view, "#feed-empty a[href='/settings?section=social']")
    end

    test "a review entry: name, verb, time, title, year, note; no pennant; opens the modal",
         %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, rec} =
        Activities.ingest(friend_event(777, "Watch it.", :love, System.os_time(:second) - 7200))

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(
               view,
               entry(rec) <> "[data-kind='review'] [data-role='who']",
               "Sample Friend"
             )

      assert has_element?(view, entry(rec) <> " [data-role='who']", "reviewed")
      assert has_element?(view, entry(rec) <> " [data-role='time']", "2h ago")
      refute has_element?(view, entry(rec) <> " [data-role='who']", "ago")
      assert has_element?(view, entry(rec) <> " [data-role='who'] [data-sentiment='love']")
      assert has_element?(view, entry(rec) <> " [data-role='title']", "Sample Movie 777")
      assert has_element?(view, entry(rec) <> " [data-role='title']", "2024")
      assert has_element?(view, entry(rec) <> " [data-role='text']", "Watch it.")
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
      assert has_element?(view, "#detail-modal .pennant[data-flag='love']", "Sample Friend")
      assert has_element?(view, "#detail-note", "Watch it.")

      view |> element("#detail-watchlist-toggle") |> render_click()
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
      refute has_element?(view, entry(listing) <> " [data-role='text']")
      refute has_element?(view, entry(listing) <> " [data-sentiment]")
      refute has_element?(view, entry(listing) <> " .pennant")
      await_supervised_tasks()
    end

    test "every sentiment shows its glyph after the verb; a review with none shows nothing", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, liked} = Activities.ingest(friend_event(777, nil, :like))
      {:ok, disliked} = Activities.ingest(friend_event(778, nil, :dislike))
      {:ok, bare} = Activities.ingest(friend_event(779, nil, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, entry(liked) <> " [data-role='who'] [data-sentiment='like']")
      assert has_element?(view, entry(disliked) <> " [data-role='who'] [data-sentiment='dislike']")
      assert has_element?(view, entry(bare) <> " [data-role='who']", "reviewed")
      refute has_element?(view, entry(bare) <> " [data-sentiment]")
      refute has_element?(view, entry(bare) <> " [data-role='text']")
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
               "feed-row-#{listed.id}",
               "feed-row-#{theirs.id}",
               "feed-row-#{mine.id}",
               "feed-row-#{quiet.id}"
             ]

      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "4")
      assert has_element?(view, entry(theirs) <> " [data-role='text']", "Agreed.")
      assert has_element?(view, entry(mine) <> " [data-role='text']", "Watch it.")
      refute has_element?(view, "[data-component='feed-row'] .pennant")

      # The modal speaks for the newest review — its note, attributed —
      # and flies both pennants.
      view |> element(entry(listed)) |> render_click()
      assert has_element?(view, "#detail-modal .pennant[data-flag='love']", "Other Friend")
      assert has_element?(view, "#detail-modal .pennant[data-flag='like']", "Sample Friend")
      assert has_element?(view, "#detail-modal .pennant[data-flag='listing']", "Sample Friend")

      await_supervised_tasks()
    end

    test "watched and a former friend's actions never make a row; own reviews and listings do", %{
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
      {:ok, mine} = Activities.review(title, :like, "mine")
      {:ok, own_listing} = Activities.listing(title)
      {:ok, _own_watched} = Activities.watched(title, nil)

      {:ok, _former} = Activities.ingest(other_event(778, :love))
      :ok = Social.remove_friend(@other_pubkey)

      {:ok, view, _html} = live(conn, "/discovery")
      # Both own acts land in the same second; their order is not this test's claim.
      assert Enum.sort(entries(view)) == Enum.sort(["feed-row-#{own_listing.id}", "feed-row-#{mine.id}"])
      assert has_element?(view, feed_badge(), "2")

      {:ok, view, _html} = live(conn, "/discovery?scope=friends")
      assert entries(view) == []
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=friends']", "Feed")
      refute has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=friends'] .badge")
      assert render(view) =~ "What your friends review and want to watch lands here"

      await_supervised_tasks()
    end

    test "a title the library has reads In library in the toolbar and plays in place from the modal",
         %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")
      assert has_element?(view, entry(rec) <> "[data-download-slot='In library']")
      refute has_element?(view, entry(rec) <> "-download")

      # The owned title shows Play on Discovery (UIDR-043); the factory
      # file has no bytes on disk, so reaching Playback.play/1 answers with
      # the mount flash — the modal is never a waystation (UIDR-027).
      refute has_element?(view, "#detail-download")
      view |> element("#detail-modal button[phx-click='play']") |> render_click()
      assert render(view) =~ "File not available"
      assert has_element?(view, "#detail-modal[data-state='open']")

      await_supervised_tasks()
    end

    test "a received review or listing appears without a reload", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, view, _html} = live(conn, "/discovery")

      {:ok, rec} = Activities.ingest(friend_event(778, "live"))
      render_until(view, fn _html -> has_element?(view, entry(rec)) end)

      {:ok, listing} = Activities.ingest(friend_listing_event(779))
      render_until(view, fn _html -> has_element?(view, entry(listing)) end)
      assert has_element?(view, feed_badge(), "2")

      await_supervised_tasks()
    end

    test "List toggles the bottom rung with the entry's provenance; Tracking is plain state", %{
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

      # Grab onboards the title, which first-contacts its TMDB detail.
      TmdbStubs.stub_get_movie(
        777,
        TmdbStubs.movie_detail(%{"id" => 777, "title" => "Sample Movie", "release_date" => "2005-01-01"})
      )

      {:ok, _intent} = ReleaseTracking.set_rung(released_movie(), :grab)

      render_until(view, fn _html -> has_element?(view, entry(rec) <> "[data-list-slot='following']") end)

      assert has_element?(view, entry(rec) <> " [data-role='toolbar']", "Tracking")
      refute has_element?(view, entry(rec) <> "-list")

      await_supervised_tasks()
    end

    test "Download performs the default planning mode — manual selection opens the board", %{conn: conn} do
      stub_prowlarr()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec) <> "-download") |> render_click()

      # The plan is made under the view's own task; its board opens once
      # the plan exists, so the redirect is the one thing to wait on.
      {path, _flash} = assert_redirect(view, 2_000)
      "/incoming?plan=" <> plan_id = path
      {:ok, plan} = Plans.fetch(plan_id)
      assert plan.approval_policy == "review"
    end

    test "Download under auto-select starts the automatic plan and flashes; the slot then reads the state",
         %{conn: conn} do
      stub_prowlarr()
      PlanningMode.set(:auto_select_best_release)
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))

      {:ok, view, _html} = live(conn, "/discovery")
      view |> element(entry(rec) <> "-download") |> render_click()

      assert render(view) =~ "Finding a release for Sample Movie 777"
      assert_push_event(view, "nav-remember", %{path: "/incoming", url: "/incoming?zone=activity"})
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
      {:ok, _} = list(released_movie(), :list)

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
      assert has_element?(
               view,
               "#detail-watchlist-toggle[aria-pressed='false'][phx-value-choice='list']"
             )

      # No record and, for a friend's snapshot, no dates yet: no card at all.
      refute has_element?(view, "#detail-tracking-controls")
      refute has_element?(view, "[data-nav-zone='detail_tracking'] [data-nav-item]")

      view |> element("#detail-watchlist-toggle") |> render_click()

      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")
      assert has_element?(view, "#detail-tracking-controls[data-rung='list'][data-form='controls']")
      # A friend's snapshot carries no release date, so until the live
      # preview's release window lands the title reads as ahead: both rows.
      assert has_element?(view, "#detail-tracking-controls-track[phx-value-choice='follow']")
      assert has_element?(view, "#detail-tracking-controls-grab[phx-value-choice='grab']")

      # Grabbing fetches the calendar, so the movie is stubbed with a date to come.
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_movie(
        777,
        TmdbStubs.movie_detail(%{"id" => 777, "release_date" => "2999-01-01"})
      )

      view |> element("#detail-tracking-controls-grab") |> render_click()
      await_supervised_tasks()
      assert Discovery.rung(777, :movie) == :grab
      # Auto-grab holds the Track row on, and the bookmark still removes —
      # one act, at any rung.
      assert has_element?(view, "#detail-tracking-controls-track[aria-disabled='true']")
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='false']")
      refute has_element?(view, "#detail-tracking-controls")
    end

    test "an ignored title says so and offers Add to watchlist, which replaces Ignore", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, nil))
      {:ok, _} = list(released_movie(), :ignored)

      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")
      refute has_element?(view, entry(rec))
      assert has_element?(view, "#detail-tracking-controls[data-rung='ignored'][data-form='ignored']")

      assert has_element?(
               view,
               "#detail-watchlist-toggle[aria-pressed='false'][phx-value-choice='list']"
             )

      assert render(view) =~ "Hidden from the Feed"

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, "#detail-tracking-controls-grab")
    end

    test "a watchlist row has no Ignore — Ignore is the Feed card's verb", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _rec} = Activities.ingest(friend_event(777, nil))
      {:ok, _} = list(released_movie(), :list)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "#watchlist-item-movie-777")
      refute has_element?(view, "#watchlist-item-movie-777-ignore")
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

      refute has_element?(view, "#detail-modal #detail-tracking-controls")
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
            Translation.to_event(:review, title, [text: nil], @friend_pubkey)
            | created_at: now - 5
          },
          @friend_secret
        )

      {:ok, rec} = Activities.ingest(event)
      {:ok, listing} = Activities.ingest(friend_listing_event(779, now - 5))

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, entry(rec))
      assert has_element?(view, entry(listing))

      for {kind, row} <- [review: rec, listing: listing] do
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

    test "neither the entry nor the modal offers Review", %{conn: conn} do
      {:ok, _item} =
        list(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}), :list)

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      refute render(view) =~ "Share a review"
      # `show_discovery` is off here, so the modal's Review control is
      # never rendered and nothing can open the flow.
      refute has_element?(view, "#detail-review")
      # The container itself mounts unconditionally, same as every other
      # `ReviewFlow` host (`EntityModal`'s) — only its open state is
      # gated, so absence is asserted on the open state.
      refute has_element?(view, "#review-modal[data-state='open']")
      await_supervised_tasks()
    end

    test "the scope filters by author, lives in the URL, and survives the modal", %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      # A minute older than your review, so the order between them is fixed.
      {:ok, theirs} =
        Activities.ingest(friend_event(777, "Watch it.", :like, System.os_time(:second) - 60))

      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, mine} = Activities.review(title, :love, "Saw it twice.")

      {:ok, view, _html} = live(conn, "/discovery")
      assert entries(view) == ["feed-row-#{mine.id}", "feed-row-#{theirs.id}"]
      assert has_element?(view, "#feed-scope [phx-value-choice='everyone'][aria-pressed='true']")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery']", "Feed")

      view |> element("#feed-scope [phx-value-choice='you']") |> render_click()
      assert_patch(view, "/discovery?scope=you")
      assert entries(view) == ["feed-row-#{mine.id}"]
      assert has_element?(view, "#feed-scope [phx-value-choice='you'][aria-pressed='true']")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=you'] .badge", "1")

      # Opening and closing the modal keeps the scope in the address.
      view |> element(entry(mine)) |> render_click()
      path = assert_patch(view)
      assert path =~ "scope=you"
      assert path =~ "title=movie-999"
      assert has_element?(view, "#detail-activity-delete", "Delete review")
      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery?scope=you")

      view |> element("#feed-scope [phx-value-choice='friends']") |> render_click()
      assert_patch(view, "/discovery?scope=friends")
      assert entries(view) == ["feed-row-#{theirs.id}"]

      # A refresh keeps it; a word the URL does not offer falls back to Everyone.
      {:ok, view, _html} = live(conn, "/discovery?scope=friends")
      assert entries(view) == ["feed-row-#{theirs.id}"]
      {:ok, view, _html} = live(conn, "/discovery?scope=nonsense")
      assert has_element?(view, "#feed-scope [phx-value-choice='everyone'][aria-pressed='true']")

      await_supervised_tasks()
    end

    test "an own row: You in the second person, no Ignore, no Delete; a friend's row keeps Ignore", %{
      conn: conn
    } do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, theirs} = Activities.ingest(friend_listing_event(777))
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, mine} = Activities.listing(title)
      {:ok, review} = Activities.review(title, :dislike, nil)

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, entry(mine) <> "[data-own] [data-role='who']", "You want to watch")
      assert has_element?(view, entry(review) <> "[data-own] [data-role='who']", "You reviewed")
      assert has_element?(view, entry(review) <> " [data-role='who'] [data-sentiment='dislike']")

      assert has_element?(
               view,
               entry(theirs) <> ":not([data-own]) [data-role='who']",
               "Sample Friend wants to watch"
             )

      assert has_element?(view, entry(mine) <> "-list")
      assert has_element?(view, entry(mine) <> "-download")
      refute has_element?(view, entry(mine) <> "-ignore")
      refute has_element?(view, entry(mine) <> " [data-role='toolbar']", "Delete")
      assert has_element?(view, entry(theirs) <> "-ignore")

      await_supervised_tasks()
    end

    test "Listed on your own listing drops the title off your list, which withdraws the listing", %{
      conn: conn
    } do
      # The withdrawal is the Publisher's (ADR-067), which is not a pubsub
      # listener under :test — started by hand, as its own test does.
      start_supervised!(Publisher)
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, _} = list(title, :list)
      {:ok, mine} = Activities.listing(title)

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, entry(mine) <> "[data-list-slot='listed']")

      view |> element(entry(mine) <> "-list") |> render_click()
      refute Discovery.listed?(999, :movie)
      render_until(view, fn _html -> not has_element?(view, entry(mine)) end)
      assert Activities.list_sent() == []

      await_supervised_tasks()
    end

    test "the You scope's empty state speaks of sharing and needs no relay or friend", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery?scope=you")

      assert render(view) =~ "What you review and list lands here"
      assert render(view) =~ "A title you list is shared while Share your watchlist is on."
      assert has_element?(view, "#feed-empty a[href='/settings?section=social']", "Settings → Social")
      refute has_element?(view, "#feed-empty a[href='/discovery/friends']")
      refute render(view) =~ "Media Centaur reaches your friends over a relay"
    end

    test "the Friends scope with a ready roster and nothing shared says so, with no actions", %{
      conn: conn
    } do
      {:ok, _relay} = Social.add_relay("wss://relay.example")
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      title = Title.new!(%{tmdb_id: 999, media_type: :movie, name: "Sample Movie 999"})
      {:ok, _mine} = Activities.review(title, :like, nil)

      {:ok, view, _html} = live(conn, "/discovery?scope=friends")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=friends']", "Feed")
      refute has_element?(view, "[data-nav-zone='zone-tabs'] a[href='/discovery?scope=friends'] .badge")
      assert render(view) =~ "What your friends review and want to watch lands here"
      assert render(view) =~ "Each action is one row, newest first."
      refute has_element?(view, "#feed-empty a")

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

    defp released_show do
      Title.new!(%{
        tmdb_id: 246_810,
        media_type: :tv_series,
        name: "Sample Show",
        year: "2010",
        release_date: ~D[2010-01-01]
      })
    end

    test "the bookmark on a title only you listed leaves the modal open — the toggle is its own undo",
         %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      assert has_element?(
               view,
               "#detail-modal[data-state='open'] #detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']"
             )

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Discovery.rung(777, :movie) == nil

      # No row and no friend activity know the title now: the open detail
      # keeps its own snapshot, so the bookmark is there to click again.
      assert has_element?(
               view,
               "#detail-modal[data-state='open'] #detail-watchlist-toggle[aria-pressed='false'][phx-value-choice='list']"
             )

      refute has_element?(view, "#detail-tracking-controls")

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")
      assert has_element?(view, "#detail-tracking-controls[data-rung='list']")
    end

    test "an import that lands while an unowned title is open turns Download into Play", %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#detail-download")
      refute has_element?(view, "#detail-modal button[phx-click='play']")

      movie = create_standalone_movie(%{name: "Sample Movie", tmdb_id: "777"})
      create_linked_file(%{movie_id: movie.id})
      Library.broadcast_entities_changed([movie.id])

      render_until(view, fn _html -> has_element?(view, "#detail-modal button[phx-click='play']") end)
      refute has_element?(view, "#detail-download")
      await_supervised_tasks()
    end

    test "a deep link to a title no list knows opens the modal from TMDB", %{conn: conn} do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache()

      TmdbStubs.stub_get_movie(
        424_242,
        TmdbStubs.movie_detail(%{
          "id" => 424_242,
          "title" => "Unlisted Movie",
          "tagline" => "Nobody listed this one.",
          "release_date" => "2010-06-15"
        })
      )

      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-424242")

      # No row knows the title, so there is no snapshot to open from: the
      # modal appears when the TMDB detail lands.
      refute html =~ "Unlisted Movie"
      html = render_async(view, 1_000)
      assert has_element?(view, "#detail-modal[data-state='open']")
      assert html =~ "Unlisted Movie"
      # One fetch dresses the detail too — the preview is already there.
      assert html =~ "Nobody listed this one."

      assert has_element?(
               view,
               "#detail-watchlist-toggle[aria-pressed='false'][phx-value-choice='list']"
             )

      refute has_element?(view, "#detail-tracking-controls")

      # Every verb works on it: the bookmark lists it and the modal stays.
      view |> element("#detail-watchlist-toggle") |> render_click()
      await_supervised_tasks()
      assert Discovery.rung(424_242, :movie) == :list

      assert has_element?(
               view,
               "#detail-modal[data-state='open'] #detail-tracking-controls[data-rung='list']"
             )
    end

    test "a deep link to a title no list knows, without TMDB, says what it needs and drops the param",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-424242")

      # The fetch is what needs TMDB, so the answer arrives as its result.
      render_async(view, 1_000)
      assert_patch(view, "/discovery/watchlist")
      assert has_element?(view, "#detail-modal[data-state='closed']")
      assert render(view) =~ "TMDB API key"
    end

    test "a deep link to an id TMDB does not have says so and drops the param", %{conn: conn} do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_tmdb_error("/movie/424242", 404)

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-424242")

      render_async(view, 1_000)
      assert_patch(view, "/discovery/watchlist")
      assert has_element?(view, "#detail-modal[data-state='closed']")
      assert render(view) =~ "TMDB has no movie"
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

      {:ok, _} =
        list(
          released_movie(),
          :list,
          %{},
          TmdbStubs.movie_detail(%{
            "id" => 777,
            "title" => "Sample Movie",
            "tagline" => "Every confirmation counts.",
            "backdrop_path" => "/sample-backdrop.jpg",
            "images" => %{"logos" => [%{"iso_639_1" => "en", "file_path" => "/sample-logo.png"}]}
          })
        )

      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")

      # Snapshot first: the modal is open before the preview is built
      # from the stored detail (ADR-071).
      assert has_element?(view, "#detail-modal #detail-download")
      refute html =~ "Every confirmation counts."

      # The preview build outruns the 100ms default under a loaded suite;
      # the budget matches the other views'.
      html = render_async(view, 1_000)
      assert html =~ "Every confirmation counts."
      # The preview's metadata row takes the hero's type line; no facet
      # strip follows the overview (UIDR-043).
      assert has_element?(view, "#detail-modal .badge", "Movie")
      refute has_element?(view, "#detail-modal", "Director")
      assert html =~ "sample-backdrop.jpg"
      assert html =~ "sample-logo.png"
      await_supervised_tasks()
    end

    test "a watchlist card click opens the modal via the URL; close returns", %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      view |> element("#watchlist-item-movie-777") |> render_click()

      assert_patch(view, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#detail-modal #detail-download")
      assert has_element?(view, "#detail-modal #detail-tracking-controls")

      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery/watchlist")
      await_supervised_tasks()
    end

    test "the Review control follows the friend-network preference", %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, ~p"/discovery/watchlist")

      # Open whatever row this test module's setup put on the watchlist.
      view
      |> element("[data-component='title-row']")
      |> render_click()

      # `show_discovery` is default-off: Discovery is a preview, and
      # Review is the one control on this modal that belongs to it.
      refute has_element?(view, "#detail-review")

      Settings.find_or_create_entry!(%{
        key: DiscoveryVisibility.setting_key(),
        value: %{"enabled" => true}
      })

      render_until(view, fn _html -> has_element?(view, "#detail-review") end)
    end

    test "Download under the default mode plans for manual selection and opens its board on Incoming",
         %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      assert has_element?(view, "#detail-download", "Download")
      # A movie has one scope: no scope select.
      refute has_element?(view, "#detail-scope")

      html = view |> element("#detail-download") |> render_click()
      assert html =~ "Planning…"

      # The plan is made under the view's own task; its board opens once
      # the plan exists, so the redirect is the one thing to wait on.
      {path, _flash} = assert_redirect(view, 2_000)
      "/incoming?plan=" <> plan_id = path
      {:ok, plan} = Plans.fetch(plan_id)
      assert plan.approval_policy == "review"
      assert plan.tmdb_type == "movie"
    end

    test "Download under the auto-select mode creates an automatic plan, closes the modal and flashes",
         %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#detail-download") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      assert render(view) =~ "Finding a release for Sample Movie"
      assert_push_event(view, "nav-remember", %{path: "/incoming", url: "/incoming?zone=activity"})
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      # Nothing found → the plan is ready with a gap → Needs review on the row.
      render_until(view, fn _html -> has_element?(view, "#watchlist-item-movie-777", "Needs review") end)
    end

    test "the menu names the other mode and performs it", %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      refute has_element?(view, "#detail-download-menu")
      view |> element("#detail-download-toggle") |> render_click()

      assert has_element?(
               view,
               "#detail-download-menu #detail-download-other",
               "Auto-select best release"
             )

      view |> element("#detail-download-other") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      await_supervised_tasks()
      assert [%{approval_policy: "automatic"}] = Plans.list_drafts()
    end

    test "with auto-select as the default the menu offers manual selection", %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#detail-download-toggle") |> render_click()
      assert has_element?(view, "#detail-download-other", "Manually select release")

      # Closing the menu is its own event (a click outside, or BACK).
      render_hook(view, "download_menu_close", %{})
      refute has_element?(view, "#detail-download-menu")
    end

    test "a series Download plans season 1 by default; the scope select widens it to all seasons",
         %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      assert has_element?(view, "#detail-download", "Download")
      assert has_element?(view, "#detail-scope", "Season 1")
      refute has_element?(view, "#detail-scope-menu")

      view |> element("#detail-scope") |> render_click()
      assert has_element?(view, "#detail-scope-menu #detail-scope-everything", "All seasons")
      assert has_element?(view, "#detail-scope-first_season.glass-menu-item-active")

      view |> element("#detail-scope-everything") |> render_click()
      refute has_element?(view, "#detail-scope-menu")
      assert has_element?(view, "#detail-scope", "All seasons")

      view |> element("#detail-download") |> render_click()

      {path, _flash} = assert_redirect(view, 2_000)
      "/incoming?plan=" <> plan_id = path
      {:ok, plan} = Plans.fetch(plan_id)
      assert plan.tmdb_type == "tv"
      assert plan.approval_policy == "review"
      assert length(Plans.units_for(plan.id)) == 3

      # Downloading what has aired says nothing about what is to come: the
      # title stays where the person put it, at List.
      refute ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
      assert Discovery.rung(246_810, :tv_series) == :list
    end

    test "Choose episodes sends Download to the picker with the default mode and plans nothing here",
         %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      view |> element("#detail-scope") |> render_click()
      assert has_element?(view, "#detail-scope-menu #detail-scope-choose_episodes", "Choose episodes")

      view |> element("#detail-scope-choose_episodes") |> render_click()
      refute has_element?(view, "#detail-scope-menu")
      assert has_element?(view, "#detail-scope", "Choose episodes")
      # Still a download: the verb names the goal, not the step.
      assert has_element?(view, "#detail-download", "Download")

      view |> element("#detail-download") |> render_click()

      {path, _flash} = assert_redirect(view)
      assert path == PlanQuery.path(PlanQuery.picker(246_810, "tv", :manually_select_release))
      assert Plans.list_drafts() == []
    end

    test "the chevron's other mode rides to the picker with Choose episodes", %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      view |> element("#detail-scope") |> render_click()
      view |> element("#detail-scope-choose_episodes") |> render_click()

      view |> element("#detail-download-toggle") |> render_click()
      view |> element("#detail-download-other") |> render_click()

      {path, _flash} = assert_redirect(view)
      assert path == PlanQuery.path(PlanQuery.picker(246_810, "tv", :auto_select_best_release))
      assert Plans.list_drafts() == []
    end

    test "a scope the select does not offer is ignored", %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      render_hook(view, "download_scope", %{"choice" => "all_of_it"})
      assert has_element?(view, "#detail-scope", "Season 1")
    end

    test "a TMDB failure while planning manually flashes on the modal and leaves no plan",
         %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      view |> element("#detail-download") |> render_click()

      # The apostrophe is escaped in the HTML, so match the parsed flash.
      render_until(view, fn _html -> has_element?(view, "#flash-error", "Couldn't plan Sample Show") end)
      assert has_element?(view, "#detail-download", "Download")
      assert Plans.list_drafts() == []
    end

    test "closing the modal while planning manually abandons the plan: no flash, no board",
         %{conn: conn} do
      {:ok, _} = list(released_show(), :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      # The targeting fetch behind a series Download runs inline in the
      # plan's task; holding it lets the modal close mid-plan.
      test_pid = self()

      Req.Test.stub(:tmdb, fn conn ->
        send(test_pid, {:blocked, self()})

        receive do
          :go -> :ok
        end

        Plug.Conn.send_resp(conn, 500, "")
      end)

      view |> element("#detail-download") |> render_click()
      assert_receive {:blocked, task_pid}

      render_hook(view, "close_title", %{})
      assert_patch(view, "/discovery/watchlist")

      # Closing cancels the plan, which kills its task; the cancel's own
      # exit reaches the view before the render below does.
      ref = Process.monitor(task_pid)
      send(task_pid, :go)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, _reason}

      refute has_element?(view, "#flash-error")
      assert Plans.list_drafts() == []
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

      {:ok, _} = list(upcoming, :list, %{}, TmdbStubs.series_universe_tv())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-246810")

      # Listed but not followed: both rows off, and nothing
      # tracking-shaped shows.
      assert has_element?(view, "#detail-tracking-controls[data-rung='list']")
      assert has_element?(view, "#detail-tracking-controls-track[phx-value-choice='follow']")
      refute has_element?(view, "#detail-release-dates")

      view |> element("#detail-tracking-controls-grab") |> render_click()
      assert render(view) =~ "Tracking Sample Show"

      await_supervised_tasks()
      assert Discovery.rung(246_810, :tv_series) == :grab
      assert ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)

      # The broadcast lands the timeline and the rung on the open modal
      # and the row.
      render_until(view, fn _html ->
        has_element?(view, "#detail-tracking-controls[data-rung='grab']")
      end)

      assert has_element?(view, "#detail-release-dates")
      assert has_element?(view, "#detail-tracking-controls-track[aria-disabled='true']")
      assert has_element?(view, "#watchlist-item-tv_series-246810", "Auto-grab")
    end

    test "moving the rung on a followed title; the bookmark deletes the record and the row", %{
      conn: conn
    } do
      item =
        create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", rung: :follow})

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#detail-tracking-controls[data-rung='follow']")

      view |> element("#detail-tracking-controls-grab") |> render_click()
      assert Discovery.rung(777, :movie) == :grab
      assert has_element?(view, "#detail-tracking-controls[data-rung='grab']")

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title too"
      refute has_element?(view, "#detail-release-dates")
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

      assert has_element?(view, "#watchlist-item-movie-777", "Tracking")
      refute has_element?(view, "#watchlist-item-movie-777 [data-component='intent-control']")

      {:ok, _} = list(released_movie(), :list)

      render_until(view, fn _html ->
        not has_element?(view, "#watchlist-item-movie-777", "Tracking:")
      end)

      await_supervised_tasks()
    end

    test "a watchlist row states its next release date", %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
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
      {:ok, _} = list(released_movie(), :follow)
      item = create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 3),
        title: "Digital",
        release_type: "digital",
        released: false
      })

      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")

      assert has_element?(view, "#detail-release-dates-digital", "Digital")
      refute html =~ "Tracking since"
      await_supervised_tasks()
    end

    test "Off forgets the title and drops both its row and the modal on this page", %{
      conn: conn
    } do
      {:ok, _} = list(released_movie(), :list)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#detail-watchlist-toggle") |> render_click()

      refute Discovery.listed?(777, :movie)
      refute has_element?(view, "#watchlist-item-movie-777")
      # Nothing left to show: this page's titles *are* the list, so once
      # the record is gone the modal has no title to render.
      refute has_element?(view, "#detail-tracking-controls")
      await_supervised_tasks()
    end

    test "acquisition events refresh the row state without a reload", %{conn: conn} do
      {:ok, _} = list(released_movie(), :list)
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

    test "a friend-sourced watchlist row says who reviewed it", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, _} =
        list(rec.title, :list, %{
          source: :friend,
          activity_id: rec.id,
          note: rec.text
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
      {:ok, _} = list(rec.title, :list)

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
      assert has_element?(view, "#detail-modal .pennant[data-flag='love']", "Other Friend")
      await_supervised_tasks()
    end

    test "a friend who watched a listed title flies a watched pennant on the row and the modal", %{
      conn: conn
    } do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      {:ok, _} = list(title, :list)

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
      assert has_element?(view, "#detail-modal .pennant[data-flag='watched']", "Sample Friend")
      refute has_element?(view, "#detail-activity-delete")
      await_supervised_tasks()
    end

    test "your own listing broadcast is not narrated back on the watchlist", %{conn: conn} do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      {:ok, _} = list(title, :follow)
      {:ok, _} = Activities.listing(title)

      {:ok, view, html} = live(conn, "/discovery/watchlist?title=movie-777")
      refute has_element?(view, "#watchlist-item-movie-777 .pennant")
      refute has_element?(view, "#detail-modal .pennant")
      refute has_element?(view, "#detail-activity-delete")
      refute html =~ "wants to watch"
      await_supervised_tasks()
    end

    test "a row whose friend is gone shows no marker", %{conn: conn} do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(777, "Watch it."))

      {:ok, _} =
        list(rec.title, :list, %{
          source: :friend,
          activity_id: rec.id,
          note: rec.text
        })

      :ok = Social.remove_friend(@friend_pubkey)

      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "#watchlist-item-movie-777")
      refute has_element?(view, "#watchlist-item-movie-777 .pennant")
      await_supervised_tasks()
    end
  end
end
