defmodule MediaCentaurWeb.Components.CastGridTest do
  @moduledoc """
  Cast-grid selection: which cast members the More info grid renders for a
  given filter query.

  This used to live in `assets/js/hooks/cast_grid_filter.js`, because the
  whole cast was rendered server-side and hidden with `display: none` so a
  hook could toggle visibility without a round-trip. For a 899-member cast
  that shipped 1.6 MB of HTML to display 24 cards. The selection is now made
  on the server, which is where the cast already is, so it is an ordinary
  pure function and tested as one.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.MoreInfo.CastGrid

  @cast for {name, character} <- [
              {"Actor One", "Role Alpha"},
              {"Actor Two", "Role Beta"},
              {"Actor Three", "Role Gamma"},
              {"Different Name", "Role Delta"},
              {"Actor Five", nil}
            ],
            do: %Person{
              name: name,
              character: character,
              tmdb_person_id: nil,
              profile_path: nil,
              order: 0
            }

  describe "visible_cast/3" do
    test "an empty query returns the first max entries, in billing order" do
      assert names(CastGrid.visible_cast(@cast, "", 3)) ==
               ["Actor One", "Actor Two", "Actor Three"]
    end

    test "nil is treated as an empty query" do
      assert names(CastGrid.visible_cast(@cast, nil, 2)) == ["Actor One", "Actor Two"]
    end

    test "matches a substring of the name" do
      assert names(CastGrid.visible_cast(@cast, "Different", 24)) == ["Different Name"]
    end

    test "matches a substring of the character" do
      assert names(CastGrid.visible_cast(@cast, "Gamma", 24)) == ["Actor Three"]
    end

    test "matching is case-insensitive on both sides" do
      assert names(CastGrid.visible_cast(@cast, "dIfFeReNt", 24)) == ["Different Name"]
      assert names(CastGrid.visible_cast(@cast, "GAMMA", 24)) == ["Actor Three"]
    end

    test "the cap applies to matches, not just to the unfiltered list" do
      assert names(CastGrid.visible_cast(@cast, "Actor", 2)) == ["Actor One", "Actor Two"]
    end

    test "results keep billing order rather than match order" do
      assert names(CastGrid.visible_cast(@cast, "Role", 24)) ==
               ["Actor One", "Actor Two", "Actor Three", "Different Name"]
    end

    test "no matches returns an empty list" do
      assert CastGrid.visible_cast(@cast, "nobody", 24) == []
    end

    test "a nil character is not a match candidate and does not crash" do
      assert names(CastGrid.visible_cast(@cast, "Five", 24)) == ["Actor Five"]
      refute "Actor Five" in names(CastGrid.visible_cast(@cast, "Role", 24))
    end

    test "an empty cast returns an empty list" do
      assert CastGrid.visible_cast([], "anything", 24) == []
    end

    test "a max of zero returns nothing" do
      assert CastGrid.visible_cast(@cast, "", 0) == []
    end

    test "the query is matched literally, not as a pattern" do
      # A user typing a regex metacharacter should get "no matches", not a
      # crash and not every card.
      assert CastGrid.visible_cast(@cast, ".*", 24) == []
    end
  end

  defp names(cast), do: Enum.map(cast, & &1.name)
end
