defmodule MediaCentaurWeb.IncomingLive.PlanLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.IncomingLive.MoviePreview
  alias MediaCentaurWeb.IncomingLive.PlanLogic

  # S1: E1 in library, E2/E3 pickable. S2: E1 pickable, E2 unaired.
  defp selection do
    %Targeting.Selection{
      tmdb_id: "246810",
      title: "Sample Show",
      tracked?: false,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes: [
            episode(1, 1, aired?: true, in_library?: true),
            episode(1, 2, aired?: true),
            episode(1, 3, aired?: true)
          ]
        },
        %Targeting.Season{
          season_number: 2,
          episodes: [
            episode(2, 1, aired?: true),
            episode(2, 2, aired?: false)
          ]
        }
      ]
    }
  end

  defp episode(season, number, opts) do
    %Targeting.Episode{
      season_number: season,
      episode_number: number,
      label: "Episode #{number}",
      aired?: Keyword.get(opts, :aired?, true),
      in_library?: Keyword.get(opts, :in_library?, false)
    }
  end

  test "pickable_units excludes in-library and unaired" do
    assert PlanLogic.pickable_units(selection()) == [{1, 2}, {1, 3}, {2, 1}]
  end

  test "toggle_unit flips pickable units and ignores unpickable ones" do
    chosen = MapSet.new()

    chosen = PlanLogic.toggle_unit(chosen, selection(), {1, 2})
    assert MapSet.member?(chosen, {1, 2})

    chosen = PlanLogic.toggle_unit(chosen, selection(), {1, 2})
    refute MapSet.member?(chosen, {1, 2})

    # In-library and unaired are no-ops.
    assert PlanLogic.toggle_unit(chosen, selection(), {1, 1}) == chosen
    assert PlanLogic.toggle_unit(chosen, selection(), {2, 2}) == chosen
  end

  test "toggle_season fills, then clears" do
    chosen = PlanLogic.toggle_season(MapSet.new(), selection(), 1)
    assert MapSet.equal?(chosen, MapSet.new([{1, 2}, {1, 3}]))

    assert PlanLogic.toggle_season(chosen, selection(), 1) == MapSet.new()
  end

  test "season_state — the in-library subtraction keeps a full season indeterminate" do
    [season_one, season_two] = selection().seasons

    assert PlanLogic.season_state(MapSet.new(), selection(), season_one) == :unchecked

    partial = MapSet.new([{1, 2}])
    assert PlanLogic.season_state(partial, selection(), season_one) == :indeterminate

    # Every pickable unit chosen, but E1 is in-library → still indeterminate.
    full = MapSet.new([{1, 2}, {1, 3}])
    assert PlanLogic.season_state(full, selection(), season_one) == :indeterminate

    # S2 has one pickable + one unaired → same rule.
    assert PlanLogic.season_state(MapSet.new([{2, 1}]), selection(), season_two) == :indeterminate

    # A season with nothing pickable is disabled.
    empty_season = %Targeting.Season{season_number: 3, episodes: [episode(3, 1, aired?: false)]}
    assert PlanLogic.season_state(MapSet.new(), selection(), empty_season) == :disabled
  end

  test "season_state — checked when everything in the season is pickable and chosen" do
    clean_selection = %Targeting.Selection{
      tmdb_id: "1",
      title: "T",
      tracked?: false,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes: [episode(1, 1, []), episode(1, 2, [])]
        }
      ]
    }

    chosen = MapSet.new([{1, 1}, {1, 2}])
    [season] = clean_selection.seasons
    assert PlanLogic.season_state(chosen, clean_selection, season) == :checked
  end

  test "presets" do
    assert PlanLogic.apply_preset(selection(), :everything_aired) ==
             MapSet.new([{1, 2}, {1, 3}, {2, 1}])

    # Library's last present episode is S01E01 → everything after it.
    assert PlanLogic.apply_preset(selection(), :continue) ==
             MapSet.new([{1, 2}, {1, 3}, {2, 1}])

    assert PlanLogic.apply_preset(selection(), :latest_season) == MapSet.new([{2, 1}])
  end

  test "chosen_in_order returns airing order regardless of set order" do
    chosen = MapSet.new([{2, 1}, {1, 2}])
    assert PlanLogic.chosen_in_order(chosen, selection()) == [{1, 2}, {2, 1}]
  end

  test "toggle_expanded adds a collapsed season and removes an expanded one" do
    expanded = PlanLogic.toggle_expanded(MapSet.new(), 2)
    assert expanded == MapSet.new([2])

    assert PlanLogic.toggle_expanded(expanded, 2) == MapSet.new()
    assert PlanLogic.toggle_expanded(expanded, 1) == MapSet.new([1, 2])
  end

  test "movie_preview builds a detail-shaped preview from a full TMDB payload" do
    tmdb_movie = %{
      "id" => 550,
      "title" => "Sample Movie",
      "tagline" => "Every confirmation counts.",
      "release_date" => "1999-10-15",
      "overview" => "A sample movie overview.",
      "runtime" => 139,
      "genres" => [%{"id" => 18, "name" => "Drama"}, %{"id" => 80, "name" => "Crime"}],
      "vote_average" => 8.4,
      "vote_count" => 26_000,
      "original_language" => "en",
      "production_companies" => [%{"name" => "Sample Studio"}],
      "production_countries" => [%{"iso_3166_1" => "US"}],
      "status" => "Released",
      "poster_path" => "/poster.jpg",
      "backdrop_path" => "/backdrop.jpg",
      "images" => %{"logos" => [%{"iso_639_1" => "en", "file_path" => "/logo.png"}]},
      "release_dates" => %{
        "results" => [
          %{"iso_3166_1" => "US", "release_dates" => [%{"certification" => "R"}]}
        ]
      },
      "credits" => %{
        "cast" => [
          %{
            "name" => "Actor One",
            "character" => "The Narrator",
            "id" => 1,
            "profile_path" => "/a1.jpg",
            "order" => 0
          },
          %{
            "name" => "Actor Two",
            "character" => "Tyler",
            "id" => 2,
            "profile_path" => nil,
            "order" => 1
          }
        ],
        "crew" => [%{"name" => "Jane Director", "job" => "Director", "department" => "Directing"}]
      }
    }

    preview = PlanLogic.movie_preview(tmdb_movie, false)

    assert %MoviePreview{} = preview
    assert preview.tmdb_id == "550"
    assert preview.title == "Sample Movie"
    assert preview.tagline == "Every confirmation counts."
    assert preview.overview == "A sample movie overview."
    assert preview.in_library? == false

    assert preview.backdrop_url == "https://image.tmdb.org/t/p/original/backdrop.jpg"
    assert preview.logo_url == "https://image.tmdb.org/t/p/original/logo.png"
    assert preview.poster_url == "https://image.tmdb.org/t/p/original/poster.jpg"

    # Metadata row items (facet-strip fields intentionally excluded here).
    assert "1999" in preview.metadata_items
    assert "2h 19m" in preview.metadata_items
    assert "R" in preview.metadata_items
    assert "US" in preview.metadata_items

    director = Enum.find(preview.facets, &(&1.label == "Director"))
    assert director.value == "Jane Director"

    rating = Enum.find(preview.facets, &(&1.label == "Rating"))
    assert rating.value.rating == 8.4

    genres = Enum.find(preview.facets, &(&1.label == "Genres"))
    assert genres.value == ["Drama", "Crime"]

    assert [%Person{name: "Actor One", character: "The Narrator"}, %Person{name: "Actor Two"}] =
             preview.cast
  end

  test "movie_preview tolerates a sparse TMDB payload" do
    tmdb_movie = %{"id" => 550, "title" => "Sample Movie", "overview" => ""}

    preview = PlanLogic.movie_preview(tmdb_movie, true)

    assert %MoviePreview{} = preview
    assert preview.tmdb_id == "550"
    assert preview.title == "Sample Movie"
    assert preview.overview == nil
    assert preview.tagline == nil
    assert preview.in_library? == true

    assert preview.backdrop_url == nil
    assert preview.logo_url == nil
    assert preview.poster_url == nil

    assert preview.metadata_items == []
    assert preview.facets == []
    assert preview.cast == []
  end
end
