defmodule MediaCentaurWeb.Components.Detail.CastSelectionTest do
  @moduledoc """
  Cast selection rules: which cast members the Cast view renders, in
  what order and section, for a given filter query and page limit.

  This used to live in `assets/js/hooks/cast_grid_filter.js`, because the
  whole cast was rendered server-side and hidden with `display: none` so a
  hook could toggle visibility without a round-trip. For a 899-member cast
  that shipped 1.6 MB of HTML to display 24 cards. The selection is now made
  on the server, which is where the cast already is, so it is an ordinary
  pure function and tested as one.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.CastSelection

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
      assert names(CastSelection.visible_cast(@cast, "", 3)) ==
               ["Actor One", "Actor Two", "Actor Three"]
    end

    test "nil is treated as an empty query" do
      assert names(CastSelection.visible_cast(@cast, nil, 2)) == ["Actor One", "Actor Two"]
    end

    test "matches a substring of the name" do
      assert names(CastSelection.visible_cast(@cast, "Different", 24)) == ["Different Name"]
    end

    test "matches a substring of the character" do
      assert names(CastSelection.visible_cast(@cast, "Gamma", 24)) == ["Actor Three"]
    end

    test "matching is case-insensitive on both sides" do
      assert names(CastSelection.visible_cast(@cast, "dIfFeReNt", 24)) == ["Different Name"]
      assert names(CastSelection.visible_cast(@cast, "GAMMA", 24)) == ["Actor Three"]
    end

    test "the cap applies to matches, not just to the unfiltered list" do
      assert names(CastSelection.visible_cast(@cast, "Actor", 2)) == ["Actor One", "Actor Two"]
    end

    test "results keep billing order rather than match order" do
      assert names(CastSelection.visible_cast(@cast, "Role", 24)) ==
               ["Actor One", "Actor Two", "Actor Three", "Different Name"]
    end

    test "no matches returns an empty list" do
      assert CastSelection.visible_cast(@cast, "nobody", 24) == []
    end

    test "a nil character is not a match candidate and does not crash" do
      assert names(CastSelection.visible_cast(@cast, "Five", 24)) == ["Actor Five"]
      refute "Actor Five" in names(CastSelection.visible_cast(@cast, "Role", 24))
    end

    test "an empty cast returns an empty list" do
      assert CastSelection.visible_cast([], "anything", 24) == []
    end

    test "a max of zero returns nothing" do
      assert CastSelection.visible_cast(@cast, "", 0) == []
    end

    test "the query is matched literally, not as a pattern" do
      # A user typing a regex metacharacter should get "no matches", not a
      # crash and not every card.
      assert CastSelection.visible_cast(@cast, ".*", 24) == []
    end
  end

  describe "match_count/2" do
    test "an empty query counts the whole cast" do
      assert CastSelection.match_count(@cast, "") == 5
      assert CastSelection.match_count(@cast, nil) == 5
    end

    test "a query counts every match, not just the visible page" do
      assert CastSelection.match_count(@cast, "Actor") == 4
    end

    test "no matches counts zero" do
      assert CastSelection.match_count(@cast, "nobody") == 0
    end
  end

  describe "order_by_appearances/1" do
    test "most episodes first, billing order breaks ties" do
      cast = [
        %Person{name: "Billed First", order: 0, total_episode_count: 10},
        %Person{name: "Carried The Show", order: 3, total_episode_count: 60},
        %Person{name: "Tied Later Billing", order: 2, total_episode_count: 10}
      ]

      assert names(CastSelection.order_by_appearances(cast)) ==
               ["Carried The Show", "Billed First", "Tied Later Billing"]
    end

    test "uncounted members sort after counted ones, by billing order" do
      cast = [
        %Person{name: "Uncounted B", order: 5, total_episode_count: nil},
        %Person{name: "Counted", order: 9, total_episode_count: 1},
        %Person{name: "Uncounted A", order: 1, total_episode_count: nil}
      ]

      assert names(CastSelection.order_by_appearances(cast)) ==
               ["Counted", "Uncounted A", "Uncounted B"]
    end

    test "a movie cast (no counts anywhere) keeps billing order" do
      cast = [
        %Person{name: "Second", order: 1},
        %Person{name: "First", order: 0}
      ]

      assert names(CastSelection.order_by_appearances(cast)) == ["First", "Second"]
    end
  end

  describe "partition_by_membership/2" do
    test "members lead, the rest follow, both ordered by appearances" do
      cast = [
        %Person{name: "Guest", order: 9, tmdb_person_id: 30, total_episode_count: 1},
        %Person{name: "Lead", order: 0, tmdb_person_id: 10, total_episode_count: 60},
        %Person{name: "Era Regular", order: 1, tmdb_person_id: 20, total_episode_count: 40},
        %Person{name: "Co-Lead", order: 2, tmdb_person_id: 11, total_episode_count: 55}
      ]

      {lead, rest} = CastSelection.partition_by_membership(cast, [30, 11, 10])

      assert names(lead) == ["Lead", "Co-Lead", "Guest"]
      assert names(rest) == ["Era Regular"]
    end

    test "a member without a tmdb id can never match the membership set" do
      cast = [
        %Person{name: "No Id", order: 0, tmdb_person_id: nil},
        %Person{name: "Has Id", order: 1, tmdb_person_id: 10}
      ]

      {lead, rest} = CastSelection.partition_by_membership(cast, [10])

      assert names(lead) == ["Has Id"]
      assert names(rest) == ["No Id"]
    end

    test "an empty membership set leads with nobody" do
      cast = [%Person{name: "Anyone", order: 0, tmdb_person_id: 10}]

      assert {[], rest} = CastSelection.partition_by_membership(cast, [])
      assert names(rest) == ["Anyone"]
    end
  end

  defp names(cast), do: Enum.map(cast, & &1.name)
end
