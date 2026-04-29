defmodule MediaCentarrWeb.HomeLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.HomeLive.Logic

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
          last_episode_label: "S03 · E10",
          progress_pct: 47,
          backdrop_url: "/img/1/backdrop.jpg"
        }
      ]

      [item] = Logic.continue_watching_items(progress)

      assert item.id == 1
      assert item.name == "Sample Show"
      assert item.subtitle == "S03 · E10"
      assert item.progress_pct == 47
      assert item.backdrop_url == "/img/1/backdrop.jpg"
    end

    test "returns empty list for empty input" do
      assert Logic.continue_watching_items([]) == []
    end
  end

  describe "coming_up_items/2" do
    test "shapes releases with a relative day subtitle" do
      today = ~D[2026-04-27]

      releases = [
        %{
          item: %{id: 1, name: "Sample Show"},
          air_date: ~D[2026-04-27],
          season_number: 4,
          episode_number: 1,
          status: :grabbed,
          backdrop_url: nil
        }
      ]

      [item] = Logic.coming_up_items(releases, today)

      assert item.id == 1
      assert item.name == "Sample Show"
      assert item.subtitle =~ "S04E01"
      assert item.badge.label == "Grabbed"
      assert item.badge.variant == :success
    end

    test "returns empty for empty input" do
      assert Logic.coming_up_items([], ~D[2026-04-27]) == []
    end
  end

  describe "recently_added_items/1" do
    test "shapes Library entities into poster items" do
      entities = [%{id: 1, name: "Sample Movie", year: 2023, poster_url: "/img/1/poster.jpg"}]

      [item] = Logic.recently_added_items(entities)

      assert item.id == 1
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
        backdrop_url: "/img/1/backdrop.jpg"
      }

      item = Logic.hero_card_item(entity)

      assert item.id == 1
      assert item.name == "Sample Movie"
      assert item.year == "2024"
      assert item.runtime == "2h 45m"
      assert item.genre_label == "Sci-Fi · Adventure"
      assert item.overview == "Sample overview."
      assert item.backdrop_url == "/img/1/backdrop.jpg"
      assert item.play_url =~ "/library?selected=1"
      assert item.detail_url =~ "/library?selected=1"
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

    test "unknown messages route to nothing" do
      assert Logic.section_reloaders({:something_else, :data}) == []
      assert Logic.section_reloaders(:bare_atom) == []
    end
  end
end
