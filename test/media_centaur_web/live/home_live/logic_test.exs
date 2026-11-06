defmodule MediaCentaurWeb.HomeLive.LogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Marquee
  alias MediaCentaurWeb.HomeLive.Logic

  # Picks then items — what Home does, minus the status lookup between them.
  defp coming_up(releases, today) do
    releases |> Logic.coming_up_picks() |> Logic.coming_up_items(today)
  end

  defp progress_row(id) do
    %{
      entity_id: id,
      entity_name: "Show #{id}",
      progress_pct: 50,
      backdrop_url: "/img/#{id}/backdrop.jpg",
      logo_url: "/img/#{id}/logo.png"
    }
  end

  defp playing_session(state \\ :playing) do
    %{state: state, now_playing: %{}}
  end

  # Releases in the shape ReleaseTracking.list_releases_between/3 returns,
  # with the additional logo_url + entity_id fields this redesign adds.
  defp release(name, air_date, opts \\ []) do
    %{
      item: %{
        id: Keyword.get(opts, :item_id, name),
        entity_id: Keyword.get(opts, :entity_id, "entity-" <> name),
        name: name,
        media_type: Keyword.get(opts, :media_type, :tv_series)
      },
      air_date: air_date,
      season_number: Keyword.get(opts, :season, 1),
      episode_number: Keyword.get(opts, :episode, 1),
      release_type: Keyword.get(opts, :release_type),
      status: Keyword.get(opts, :status, :scheduled),
      backdrop_url: Keyword.get(opts, :backdrop_url, "/img/" <> name <> "/backdrop.jpg"),
      logo_url: Keyword.get(opts, :logo_url, "/img/" <> name <> "/logo.png")
    }
  end

  defp movie_release(name, air_date, opts) do
    release(
      name,
      air_date,
      Keyword.merge([media_type: :movie, season: nil, episode: nil], opts)
    )
  end

  describe "coming_up_window/1" do
    test "returns Mon-Sun of the week containing a Monday" do
      monday = ~D[2026-04-27]
      sunday = ~D[2026-05-03]
      assert Logic.coming_up_window(monday) == {monday, sunday}
    end

    test "from a Wednesday returns the containing Mon-Sun" do
      wed = ~D[2026-04-29]
      assert Logic.coming_up_window(wed) == {~D[2026-04-27], ~D[2026-05-03]}
    end

    test "from a Sunday returns the same week's Mon-Sun" do
      sunday = ~D[2026-05-03]
      assert Logic.coming_up_window(sunday) == {~D[2026-04-27], sunday}
    end

    test "default arg is today" do
      assert {monday, sunday} = Logic.coming_up_window()
      assert Date.day_of_week(monday) == 1
      assert Date.day_of_week(sunday) == 7
    end
  end

  describe "continue_watching_items/1" do
    test "shapes progress rows into the component item map" do
      progress = [
        %{
          entity_id: 1,
          entity_name: "Sample Show",
          progress_pct: 47,
          backdrop_url: "/img/1/backdrop.jpg",
          logo_url: "/img/1/logo.png"
        }
      ]

      [item] = Logic.continue_watching_items(progress)

      assert item.id == 1
      assert item.entity_id == 1
      assert item.name == "Sample Show"
      assert item.progress_pct == 47
      assert item.backdrop_url == "/img/1/backdrop.jpg"
      assert item.logo_url == "/img/1/logo.png"
    end

    test "returns empty list for empty input" do
      assert Logic.continue_watching_items([]) == []
    end
  end

  describe "continue_watching_items/2 (playback-aware ordering)" do
    # The /2 arity pins entities the user is currently playing (any
    # non-stopped state) to the front of Continue Watching. The signal
    # is loud — if mpv is open right now and you tab back to Home, the
    # thing you're watching should be the first card on the row.

    test "empty playback map preserves /1 ordering" do
      progress = [progress_row(1), progress_row(2), progress_row(3)]
      assert Logic.continue_watching_items(progress, %{}) == Logic.continue_watching_items(progress)
    end

    test "active entity in the middle of the list is pinned to front" do
      progress = [progress_row(1), progress_row(2), progress_row(3)]
      playback = %{2 => playing_session()}

      result = Logic.continue_watching_items(progress, playback)
      assert Enum.map(result, & &1.id) == [2, 1, 3]
    end

    test "active entity already at front is a no-op" do
      progress = [progress_row(1), progress_row(2), progress_row(3)]
      playback = %{1 => playing_session()}

      result = Logic.continue_watching_items(progress, playback)
      assert Enum.map(result, & &1.id) == [1, 2, 3]
    end

    test "paused entity is also pinned (any non-stopped state counts)" do
      # Pausing is "still actively watching, just not pressing play right
      # now" — the user expects the card to remain front-of-mind.
      progress = [progress_row(1), progress_row(2)]
      playback = %{2 => playing_session(:paused)}

      result = Logic.continue_watching_items(progress, playback)
      assert Enum.map(result, & &1.id) == [2, 1]
    end

    test "multiple active entities — preserve relative order at the front" do
      # Concurrent sessions are unusual (one mpv instance) but possible
      # in the future / multi-room. The pin order should match the
      # original Continue Watching order, not arbitrary map order.
      progress = [progress_row(1), progress_row(2), progress_row(3), progress_row(4)]
      playback = %{4 => playing_session(), 2 => playing_session()}

      result = Logic.continue_watching_items(progress, playback)
      assert Enum.map(result, & &1.id) == [2, 4, 1, 3]
    end

    test "active entity not in continue list — no promotion, list unchanged" do
      # The user might be watching a brand-new entity that hasn't yet
      # propagated into the Continue Watching query result. Don't
      # invent a row; just leave the list alone.
      progress = [progress_row(1), progress_row(2)]
      playback = %{99 => playing_session()}

      result = Logic.continue_watching_items(progress, playback)
      assert Enum.map(result, & &1.id) == [1, 2]
    end
  end

  describe "coming_up_picks/1 + coming_up_items/2" do
    test "single release in window → a lead tile, no tiles" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, season: 5, episode: 4, status: :grabbed)]

      [lead | tiles] = coming_up(releases, today)

      assert lead != nil
      assert lead.name == "Sample Show A"
      assert tiles == []
    end

    test "empty input → no items" do
      assert coming_up([], ~D[2026-04-27]) == []
    end

    test "at most seven shows, soonest first — the eighth waits behind See all" do
      today = ~D[2026-04-27]

      releases =
        for day <- 1..9 do
          release("Sample Show #{day}", Date.add(today, day))
        end

      [lead | tiles] = coming_up(releases, today)

      assert lead.name == "Sample Show 1"
      assert Enum.map(tiles, & &1.name) == Enum.map(2..7, &"Sample Show #{&1}")
    end

    test "a show's count covers every release it has in the window" do
      today = ~D[2026-04-27]

      weekly =
        for week <- 0..12 do
          release("Sample Show A", Date.add(today, week * 7), season: 2, episode: 1 + week)
        end

      [pick] = Logic.coming_up_picks(weekly)

      assert pick.count == 13
      assert pick.release.air_date == today
    end

    test "every item is a Marquee.Item" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today), release("Sample Show B", Date.add(today, 1))]

      assert Enum.all?(coming_up(releases, today), &match?(%Marquee.Item{}, &1))
    end

    test "deduplicates by series, the lead has the rollup, tiles are distinct shows" do
      today = ~D[2026-04-27]

      show_a_releases =
        for week <- 0..6 do
          release("Sample Show A", Date.add(today, week * 7), season: 5, episode: 4 + week)
        end

      other_releases = [
        release("Sample Show B", Date.add(today, 1), season: 2, episode: 8),
        release("Sample Show C", Date.add(today, 5), season: 4, episode: 1),
        release("Sample Show D", Date.add(today, 8), season: 1, episode: 3)
      ]

      [lead | tiles] = coming_up(show_a_releases ++ other_releases, today)

      assert lead.name == "Sample Show A"
      assert lead.line =~ "6 more"

      assert length(tiles) == 3
      tile_names = Enum.map(tiles, & &1.name)
      assert "Sample Show B" in tile_names
      assert "Sample Show C" in tile_names
      assert "Sample Show D" in tile_names
      refute "Sample Show A" in tile_names
    end

    test "tiles ordered by air_date ascending" do
      today = ~D[2026-04-27]

      releases = [
        release("Late Show", Date.add(today, 10)),
        release("Early Show", Date.add(today, 2)),
        release("Mid Show", Date.add(today, 5)),
        release("Hero Show", today)
      ]

      [lead | tiles] = coming_up(releases, today)

      assert lead.name == "Hero Show"
      assert Enum.map(tiles, & &1.name) == ["Early Show", "Mid Show", "Late Show"]
    end

    test "today's release → lead eyebrow says 'Tonight' and contains S0xE0y" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, season: 5, episode: 4)]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow =~ "Tonight"
      assert lead.eyebrow =~ "S05E04"
    end

    test "tomorrow's release → lead eyebrow says 'Tomorrow'" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", Date.add(today, 1), season: 5, episode: 4)]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow =~ "Tomorrow"
      assert lead.eyebrow =~ "S05E04"
    end

    test "release within 6 days → eyebrow uses weekday name, no 'Tonight'/'Tomorrow'" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", Date.add(today, 4), season: 5, episode: 4)]

      [lead | _tiles] = coming_up(releases, today)

      refute lead.eyebrow =~ "Tonight"
      refute lead.eyebrow =~ "Tomorrow"
      # Friday May 1 2026 — confirms a weekday name is used
      assert lead.eyebrow =~ "Fri"
      assert lead.eyebrow =~ "S05E04"
    end

    test "release more than 6 days out → eyebrow uses absolute date" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", Date.add(today, 14), season: 5, episode: 4)]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow =~ "May 11"
    end

    test "mixed status — lead acquired badge, scheduled tiles have nil badge" do
      today = ~D[2026-04-27]

      releases = [
        release("Sample Show A", today, status: :acquired),
        release("Sample Show B", Date.add(today, 1), status: :scheduled),
        release("Sample Show C", Date.add(today, 2), status: :scheduled)
      ]

      [lead | tiles] = coming_up(releases, today)

      assert lead.badge.variant == :success
      assert lead.badge.label == "Acquired"
      # "Scheduled" is the default state of every Coming Up item; carrying
      # a "SCHEDULED" badge on every tile is noise. nil here is signal.
      assert Enum.all?(tiles, &(&1.badge == nil))
    end

    test "actionable statuses (downloading, seeking) still surface a badge" do
      today = ~D[2026-04-27]

      releases = [
        release("Sample Show B", today, status: :downloading),
        release("Sample Show C", Date.add(today, 1), status: :seeking)
      ]

      [lead | tiles] = coming_up(releases, today)

      assert lead.badge.label == "Downloading"
      assert lead.badge.variant == :info
      [tile] = tiles
      assert tile.badge.label == "Seeking"
      assert tile.badge.variant == :info
    end

    test "a release whose chosen release is being grabbed reads Grabbing" do
      today = ~D[2026-04-27]

      [lead | _tiles] = coming_up([release("Sample Show B", today, status: :grabbing)], today)

      assert lead.badge.label == "Grabbing"
      assert lead.badge.variant == :info
    end

    test "release with no logo_url → item logo_url is nil (component falls back to typography)" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, logo_url: nil)]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.logo_url == nil
      # Backdrop still present so the card has visual content.
      assert lead.backdrop_url != nil
    end

    test "season premiere (episode 1) → line mentions 'season premiere'" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show C", today, season: 4, episode: 1)]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.line =~ "season premiere"
    end

    test "single release with no upcoming siblings → no rollup line" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show B", today, season: 2, episode: 8)]

      [lead | _tiles] = coming_up(releases, today)

      # nil is the canonical "no line" value; the component
      # uses :if={@item.line} to avoid rendering an empty line.
      assert lead.line == nil
    end

    test "a tile with multiple upcoming → its line mentions the count" do
      today = ~D[2026-04-27]

      show_a = release("Sample Show A", today)

      show_d_releases =
        for week <- 0..2 do
          release("Sample Show D", Date.add(today, 1 + week * 7),
            season: 1,
            episode: 3 + week
          )
        end

      [_lead | tiles] = coming_up([show_a | show_d_releases], today)

      [tile] = tiles
      assert tile.name == "Sample Show D"
      # 3 Sample Show D releases total; the tile represents the soonest, so 2 more.
      assert tile.line =~ "2 more"
    end

    test "entity_id passes through for click target" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, entity_id: "library-uuid-sample-a")]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.entity_id == "library-uuid-sample-a"
    end
  end

  describe "coming_up_items/2 — movie and theatrical labeling" do
    # A bare "Tonight" on a movie tile is ambiguous: it reads as "expect
    # the download tonight" even when the date is a theatrical premiere
    # that will never be grabbed. The eyebrow carries the venue instead
    # of adding any new element to the tile.

    test "movie releasing today → eyebrow says 'Today', never 'Tonight'" do
      today = ~D[2026-04-27]
      releases = [movie_release("Sample Movie A", today, release_type: "digital")]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow == "Today"
    end

    test "theatrical date today → eyebrow 'In theaters · Today'" do
      today = ~D[2026-04-27]
      releases = [movie_release("Sample Movie A", today, release_type: "theatrical")]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow == "In theaters · Today"
    end

    test "theatrical date tomorrow → eyebrow 'In theaters · Tomorrow'" do
      today = ~D[2026-04-27]

      releases = [
        movie_release("Sample Movie A", Date.add(today, 1), release_type: "theatrical")
      ]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow == "In theaters · Tomorrow"
    end

    test "theatrical date within the week → 'In theaters · <weekday>'" do
      today = ~D[2026-04-27]

      releases = [
        movie_release("Sample Movie A", Date.add(today, 4), release_type: "theatrical")
      ]

      [lead | _tiles] = coming_up(releases, today)

      # Friday May 1 2026
      assert lead.eyebrow == "In theaters · Fri"
    end

    test "theatrical date beyond a week → 'In theaters · <Mon DD>'" do
      today = ~D[2026-04-27]

      releases = [
        movie_release("Sample Movie A", Date.add(today, 14), release_type: "theatrical")
      ]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.eyebrow == "In theaters · May 11"
    end

    test "theatrical labeling applies on tiles too" do
      today = ~D[2026-04-27]

      releases = [
        release("Sample Show A", today),
        movie_release("Sample Movie A", Date.add(today, 2), release_type: "theatrical")
      ]

      [_lead | tiles] = coming_up(releases, today)

      [tile] = tiles
      assert tile.eyebrow == "In theaters · Wed"
    end

    test "a movie's later second date never yields a 'more this season' rollup" do
      today = ~D[2026-04-27]

      releases = [
        movie_release("Sample Movie A", today,
          release_type: "theatrical",
          item_id: "movie-a"
        ),
        movie_release("Sample Movie A", Date.add(today, 60),
          release_type: "digital",
          item_id: "movie-a"
        )
      ]

      [lead | _tiles] = coming_up(releases, today)

      assert lead.line == nil
    end

    test "a movie tile with a later second date keeps its line nil" do
      today = ~D[2026-04-27]

      releases = [
        release("Sample Show A", today),
        movie_release("Sample Movie A", Date.add(today, 3),
          release_type: "theatrical",
          item_id: "movie-a"
        ),
        movie_release("Sample Movie A", Date.add(today, 60),
          release_type: "digital",
          item_id: "movie-a"
        )
      ]

      [_lead | tiles] = coming_up(releases, today)

      [tile] = tiles
      assert tile.line == nil
    end
  end

  describe "recently_added_items/1" do
    test "shapes Library entities into poster items" do
      entities = [%{id: 1, name: "Sample Movie", year: 2023, poster_url: "/img/1/poster.jpg"}]

      [item] = Logic.recently_added_items(entities)

      assert item.id == 1
      assert item.entity_id == 1
      assert item.name == "Sample Movie"
      assert item.year == "2023"
      assert item.poster_url == "/img/1/poster.jpg"
    end
  end

  describe "hero_card_item/1" do
    test "shapes a Library entity into the hero item map" do
      entity = %{
        id: 1,
        name: "Sample Movie",
        year: 2024,
        runtime_minutes: 165,
        genres: ["Sci-Fi", "Adventure"],
        overview: "Sample overview.",
        backdrop_url: "/img/1/backdrop.jpg",
        logo_url: "/img/1/logo.png"
      }

      item = Logic.hero_card_item(entity)

      assert item.id == 1
      assert item.entity_id == 1
      assert item.name == "Sample Movie"
      assert item.year == "2024"
      assert item.runtime == "2h 45m"
      assert item.genre_label == "Sci-Fi · Adventure"
      assert item.overview == "Sample overview."
      assert item.backdrop_url == "/img/1/backdrop.jpg"
      assert item.logo_url == "/img/1/logo.png"
    end

    test "passes through nil logo_url when entity has no logo image" do
      entity = %{
        id: 1,
        name: "Sample Movie",
        year: 2024,
        runtime_minutes: 100,
        genres: nil,
        overview: nil,
        backdrop_url: "/img/1/backdrop.jpg",
        logo_url: nil
      }

      item = Logic.hero_card_item(entity)

      assert item.logo_url == nil
    end

    test "returns nil for nil input" do
      assert Logic.hero_card_item(nil) == nil
    end
  end

  describe "section_reloaders/1" do
    test "raw source events no longer reload anything directly" do
      # Source events (`:entities_changed`, `:watch_event_created`,
      # `:entity_progress_updated`, `:releases_updated`, `:item_removed`)
      # now flow into the Library.Views and
      # ReleaseTracking.Views projections, which broadcast
      # `:library_view_updated` / `:release_tracking_view_updated`
      # after each ETS rebuild. The LiveView reacts only to those
      # projection events (ADR-041 encapsulation rule).
      assert Logic.section_reloaders(
               {:entities_changed,
                %MediaCentaur.Library.Events.EntitiesChanged{entity_ids: ["abc", "def"]}}
             ) == []

      assert Logic.section_reloaders({:releases_updated, ["item-1"]}) == []
      assert Logic.section_reloaders({:item_removed, "12345", "movie"}) == []
      assert Logic.section_reloaders({:watch_event_created, %{id: "event-1"}}) == []

      msg =
        {:entity_progress_updated,
         %{entity_id: "abc", summary: %{}, resume_target: nil, changed_record: nil}}

      assert Logic.section_reloaders(msg) == []
    end

    test "library_view_updated :continue_watching reloads continue_watching only" do
      assert Logic.section_reloaders({:library_view_updated, :continue_watching}) ==
               [:continue_watching]
    end

    test "library_view_updated :hero_candidates reloads hero only" do
      assert Logic.section_reloaders({:library_view_updated, :hero_candidates}) == [:hero]
    end

    test "library_view_updated :recently_added reloads recently_added only" do
      assert Logic.section_reloaders({:library_view_updated, :recently_added}) ==
               [:recently_added]
    end

    test "release_tracking_view_updated :coming_up reloads coming_up only" do
      assert Logic.section_reloaders({:release_tracking_view_updated, :coming_up}) ==
               [:coming_up]
    end

    test "playback_state_changed reloads continue_watching only" do
      # Play/pause from another device must reorder Continue Watching so
      # the now-playing item floats to the front of the row.
      msg =
        {:playback_state_changed,
         %MediaCentaur.Playback.Events.PlaybackStateChanged{
           player: :host,
           entity_id: "abc",
           profile_id: "p-1",
           state: :playing,
           now_playing: %{},
           started_at: System.monotonic_time(:millisecond)
         }}

      assert Logic.section_reloaders(msg) == [:continue_watching]
    end

    test "availability_changed drives no direct section reloads" do
      # Every Library / ReleaseTracking projection that reads file-presence-
      # gated data subscribes to library:availability directly, re-resolves
      # each row's availability and artwork, and broadcasts a
      # :library_view_updated event after refresh. The LiveView reacts only
      # to those derived broadcasts and never hears the source event.
      assert Logic.section_reloaders({:availability_changed, "/mnt/movies", :available}) == []

      assert Logic.section_reloaders({:availability_changed, "/mnt/movies", :unavailable}) == []
    end

    test "unknown messages route to nothing" do
      assert Logic.section_reloaders({:something_else, :data}) == []
      assert Logic.section_reloaders(:bare_atom) == []
    end
  end

  describe "availability on the shaped items" do
    # `available?` and the artwork URLs arrive together from the projection;
    # Logic carries the flag through so the cards render the offline
    # treatment without re-deciding anything.
    test "continue_watching_items/2 carries available? from the row" do
      rows = [
        %{
          entity_id: 1,
          entity_name: "Offline Show",
          progress_pct: 47,
          backdrop_url: nil,
          logo_url: nil,
          available?: false
        },
        %{
          entity_id: 2,
          entity_name: "Online Show",
          progress_pct: 10,
          backdrop_url: "/media-images/2/backdrop.jpg",
          available?: true
        }
      ]

      assert [%{entity_id: 1, available?: false}, %{entity_id: 2, available?: true}] =
               Logic.continue_watching_items(rows, %{})
    end

    test "recently_added_items/1 carries available? from the row" do
      rows = [%{id: 1, name: "Offline Movie", year: 2023, poster_url: nil, available?: false}]

      assert [%{available?: false, poster_url: nil}] = Logic.recently_added_items(rows)
    end

    test "a row without the flag is available" do
      rows = [%{entity_id: 1, entity_name: "Sample Show", progress_pct: 1, backdrop_url: nil}]

      assert [%{available?: true}] = Logic.continue_watching_items(rows, %{})
    end
  end

  describe "empty_reason/1" do
    test "no media directory configured is the only reason that blames configuration" do
      assert Logic.empty_reason(%{media_dirs_configured?: false, pipeline_queue_depth: 0}) ==
               :no_media_dirs

      assert Logic.empty_reason(%{media_dirs_configured?: false, pipeline_queue_depth: 7}) ==
               :no_media_dirs
    end

    test "directories configured with an import in flight reads as importing" do
      assert Logic.empty_reason(%{media_dirs_configured?: true, pipeline_queue_depth: 7}) ==
               :importing
    end

    test "directories configured with nothing in flight reads as nothing imported" do
      assert Logic.empty_reason(%{media_dirs_configured?: true, pipeline_queue_depth: 0}) ==
               :nothing_imported
    end
  end
end
