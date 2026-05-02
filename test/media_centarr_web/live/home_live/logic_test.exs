defmodule MediaCentarrWeb.HomeLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.HomeLive.Logic

  # Releases in the shape ReleaseTracking.list_releases_between/3 returns,
  # with the additional logo_url + entity_id fields this redesign adds.
  defp release(name, air_date, opts \\ []) do
    %{
      item: %{
        id: Keyword.get(opts, :item_id, name),
        entity_id: Keyword.get(opts, :entity_id, "entity-" <> name),
        name: name
      },
      air_date: air_date,
      season_number: Keyword.get(opts, :season, 1),
      episode_number: Keyword.get(opts, :episode, 1),
      status: Keyword.get(opts, :status, :scheduled),
      backdrop_url: Keyword.get(opts, :backdrop_url, "/img/" <> name <> "/backdrop.jpg"),
      logo_url: Keyword.get(opts, :logo_url, "/img/" <> name <> "/logo.png")
    }
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

  describe "select_hero/2" do
    test "returns nil for an empty candidate list" do
      assert Logic.select_hero([], ~D[2026-04-27]) == nil
    end

    test "returns a candidate from the list" do
      candidates = [%{id: 1}, %{id: 2}, %{id: 3}]
      assert Logic.select_hero(candidates, ~D[2026-04-27]) in candidates
    end

    test "is stable across calls on the same day" do
      candidates = for i <- 1..10, do: %{id: i}
      a = Logic.select_hero(candidates, ~D[2026-04-27])
      b = Logic.select_hero(candidates, ~D[2026-04-27])
      assert a == b
    end

    test "different dates can produce different picks" do
      candidates = for i <- 1..10, do: %{id: i}
      picks = for d <- 0..9, do: Logic.select_hero(candidates, Date.add(~D[2026-04-27], d))
      assert length(Enum.uniq(picks)) > 1
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
      # Modal opens on click; user explicitly hits Play to resume.
      assert item.autoplay == false
    end

    test "returns empty list for empty input" do
      assert Logic.continue_watching_items([]) == []
    end
  end

  describe "coming_up_marquee/2" do
    test "single release in window → hero populated, no secondaries" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, season: 5, episode: 4, status: :grabbed)]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero != nil
      assert marquee.hero.name == "Sample Show A"
      assert marquee.secondaries == []
    end

    test "empty input → hero is nil and secondaries is empty" do
      marquee = Logic.coming_up_marquee([], ~D[2026-04-27])
      assert marquee.hero == nil
      assert marquee.secondaries == []
    end

    test "deduplicates by series, hero has rollup, secondaries are distinct shows" do
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

      marquee = Logic.coming_up_marquee(show_a_releases ++ other_releases, today)

      assert marquee.hero.name == "Sample Show A"
      assert marquee.hero.rollup =~ "6 more"

      assert length(marquee.secondaries) == 3
      secondary_names = Enum.map(marquee.secondaries, & &1.name)
      assert "Sample Show B" in secondary_names
      assert "Sample Show C" in secondary_names
      assert "Sample Show D" in secondary_names
      refute "Sample Show A" in secondary_names
    end

    test "secondaries ordered by air_date ascending" do
      today = ~D[2026-04-27]

      releases = [
        release("Late Show", Date.add(today, 10)),
        release("Early Show", Date.add(today, 2)),
        release("Mid Show", Date.add(today, 5)),
        release("Hero Show", today)
      ]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.name == "Hero Show"
      assert Enum.map(marquee.secondaries, & &1.name) == ["Early Show", "Mid Show", "Late Show"]
    end

    test "today's release → hero eyebrow says 'Tonight' and contains S0xE0y" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, season: 5, episode: 4)]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.eyebrow =~ "Tonight"
      assert marquee.hero.eyebrow =~ "S05E04"
    end

    test "tomorrow's release → hero eyebrow says 'Tomorrow'" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", Date.add(today, 1), season: 5, episode: 4)]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.eyebrow =~ "Tomorrow"
      assert marquee.hero.eyebrow =~ "S05E04"
    end

    test "release within 6 days → eyebrow uses weekday name, no 'Tonight'/'Tomorrow'" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", Date.add(today, 4), season: 5, episode: 4)]

      marquee = Logic.coming_up_marquee(releases, today)

      refute marquee.hero.eyebrow =~ "Tonight"
      refute marquee.hero.eyebrow =~ "Tomorrow"
      # Friday May 1 2026 — confirms a weekday name is used
      assert marquee.hero.eyebrow =~ "Fri"
      assert marquee.hero.eyebrow =~ "S05E04"
    end

    test "release more than 6 days out → eyebrow uses absolute date" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", Date.add(today, 14), season: 5, episode: 4)]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.eyebrow =~ "May 11"
    end

    test "mixed status — hero grabbed badge, scheduled secondaries have nil badge" do
      today = ~D[2026-04-27]

      releases = [
        release("Sample Show A", today, status: :grabbed),
        release("Sample Show B", Date.add(today, 1), status: :scheduled),
        release("Sample Show C", Date.add(today, 2), status: :scheduled)
      ]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.badge.variant == :success
      assert marquee.hero.badge.label == "Grabbed"
      # "Scheduled" is the default state of every Coming Up item; carrying
      # a "SCHEDULED" badge on every tile is noise. nil here is signal.
      assert Enum.all?(marquee.secondaries, &(&1.badge == nil))
    end

    test "actionable statuses (downloading, pending) still surface a badge" do
      today = ~D[2026-04-27]

      releases = [
        release("Sample Show B", today, status: :downloading),
        release("Sample Show C", Date.add(today, 1), status: :pending)
      ]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.badge.label == "Downloading"
      assert marquee.hero.badge.variant == :info
      [secondary] = marquee.secondaries
      assert secondary.badge.label == "Pending"
      assert secondary.badge.variant == :info
    end

    test "release with no logo_url → item logo_url is nil (component falls back to typography)" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, logo_url: nil)]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.logo_url == nil
      # Backdrop still present so the card has visual content.
      assert marquee.hero.backdrop_url != nil
    end

    test "season premiere (episode 1) → rollup mentions 'season premiere'" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show C", today, season: 4, episode: 1)]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.rollup =~ "season premiere"
    end

    test "single release with no upcoming siblings → no rollup count" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show B", today, season: 2, episode: 8)]

      marquee = Logic.coming_up_marquee(releases, today)

      # nil rollup is the canonical "no rollup" value; the component
      # uses :if={@item.rollup} to avoid rendering an empty line.
      assert marquee.hero.rollup == nil
    end

    test "secondary tile with multiple upcoming → sub mentions count" do
      today = ~D[2026-04-27]

      show_a = release("Sample Show A", today)

      pitt_releases =
        for week <- 0..2 do
          release("Sample Show D", Date.add(today, 1 + week * 7),
            season: 1,
            episode: 3 + week
          )
        end

      marquee = Logic.coming_up_marquee([show_a | pitt_releases], today)

      [secondary] = marquee.secondaries
      assert secondary.name == "Sample Show D"
      # 3 Pitt releases total; the secondary represents the soonest, so 2 more.
      assert secondary.sub =~ "2 more"
    end

    test "entity_id passes through for click target" do
      today = ~D[2026-04-27]
      releases = [release("Sample Show A", today, entity_id: "library-uuid-sample-a")]

      marquee = Logic.coming_up_marquee(releases, today)

      assert marquee.hero.entity_id == "library-uuid-sample-a"
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
    test "entities_changed reloads recently_added only" do
      assert Logic.section_reloaders({:entities_changed, ["abc", "def"]}) == [:recently_added]
    end

    test "releases_updated reloads coming_up only" do
      assert Logic.section_reloaders({:releases_updated, ["item-1"]}) == [:coming_up]
    end

    test "item_removed reloads coming_up only" do
      assert Logic.section_reloaders({:item_removed, "12345", "movie"}) == [:coming_up]
    end

    test "release_ready reloads coming_up only" do
      assert Logic.section_reloaders({:release_ready, %{id: "item"}, %{id: "release"}}) ==
               [:coming_up]
    end

    test "watch_event_created reloads continue_watching only" do
      assert Logic.section_reloaders({:watch_event_created, %{id: "event-1"}}) ==
               [:continue_watching]
    end

    test "entity_progress_updated reloads continue_watching only" do
      # Without this, the Continue Watching row freezes mid-playback because
      # progress messages from Playback.ProgressBroadcaster only flow while
      # MpvSession is reporting position. The 500ms debounce on
      # :continue_watching reload coalesces the high-frequency stream.
      msg =
        {:entity_progress_updated,
         %{entity_id: "abc", summary: %{}, resume_target: nil, changed_record: nil}}

      assert Logic.section_reloaders(msg) == [:continue_watching]
    end

    test "playback_state_changed reloads continue_watching only" do
      # Play/pause from another device must reorder Continue Watching so
      # the now-playing item floats to the front of the row.
      msg = {:playback_state_changed, "abc", :playing, %{}, DateTime.utc_now()}
      assert Logic.section_reloaders(msg) == [:continue_watching]
    end

    test "unknown messages route to nothing" do
      assert Logic.section_reloaders({:something_else, :data}) == []
      assert Logic.section_reloaders(:bare_atom) == []
    end
  end
end
