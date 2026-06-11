defmodule MediaCentaurWeb.AcquisitionLive.PlanLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaurWeb.AcquisitionLive.PlanLogic

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
end
