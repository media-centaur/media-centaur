defmodule MediaCentaurWeb.Components.Title.PennantTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [person: 1, own_person: 0]
  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Title.Pennant

  defp friend(name, attrs), do: %{activity: build_activity(Map.new(attrs)), author: person(name)}

  defp own(sentiment), do: %{activity: build_activity(%{sentiment: sentiment}), author: own_person()}

  describe "mast/1" do
    test "nothing for no activity" do
      assert Pennant.mast([]) == []
    end

    test "one pennant per flag in mast order, people in the rows' order with the reader last" do
      rows = [
        friend("Pat", kind: :listing),
        own(:like),
        friend("Sam", sentiment: :like),
        friend("Kim", sentiment: nil),
        friend("Nick", sentiment: :love),
        friend("Alex", sentiment: :like),
        friend("Jo", sentiment: :dislike),
        friend("Nick", kind: :watched)
      ]

      assert [love, like, dislike, review, watched, listing] = Pennant.mast(rows)

      assert %{flag: :love, people: people} = love
      assert Enum.map(people, &Format.person_name/1) == ["Nick"]

      assert %{flag: :like, people: people} = like
      assert Enum.map(people, &Format.person_name/1) == ["Sam", "Alex", "You"]

      assert %{flag: :dislike, people: people} = dislike
      assert Enum.map(people, &Format.person_name/1) == ["Jo"]

      assert %{flag: :review, people: people} = review
      assert Enum.map(people, &Format.person_name/1) == ["Kim"]

      assert %{flag: :watched, people: people} = watched
      assert Enum.map(people, &Format.person_name/1) == ["Nick"]

      assert %{flag: :listing, people: people} = listing
      assert Enum.map(people, &Format.person_name/1) == ["Pat"]
    end
  end

  describe "label/1" do
    test "up to two names, then a count" do
      assert Pennant.label(%{flag: :love, people: [person("Nick")]}) == "Nick"
      assert Pennant.label(%{flag: :love, people: [person("Nick"), person("Sam")]}) == "Nick, Sam"

      assert Pennant.label(%{flag: :like, people: [person("Nick"), person("Sam"), own_person()]}) ==
               "Nick +2"
    end
  end

  describe "tooltip/1" do
    test "reads as a sentence" do
      assert Pennant.tooltip(%{flag: :love, people: [person("Nick")]}) == "Nick loves this"
      assert Pennant.tooltip(%{flag: :like, people: [person("Nick")]}) == "Nick likes this"
      assert Pennant.tooltip(%{flag: :like, people: [own_person()]}) == "You like this"
      assert Pennant.tooltip(%{flag: :dislike, people: [person("Nick")]}) == "Nick dislikes this"

      assert Pennant.tooltip(%{flag: :dislike, people: [person("Nick"), own_person()]}) ==
               "Nick and you dislike this"

      assert Pennant.tooltip(%{flag: :review, people: [person("Nick")]}) == "Nick reviewed this"

      assert Pennant.tooltip(%{flag: :review, people: [person("Nick"), person("Sam")]}) ==
               "Nick and Sam reviewed this"

      assert Pennant.tooltip(%{flag: :love, people: [person("Nick"), person("Sam"), own_person()]}) ==
               "Nick, Sam and you love this"

      assert Pennant.tooltip(%{flag: :watched, people: [person("Nick")]}) == "Nick watched this"

      assert Pennant.tooltip(%{flag: :watched, people: [person("Nick"), person("Sam")]}) ==
               "Nick and Sam watched this"

      assert Pennant.tooltip(%{flag: :listing, people: [person("Nick")]}) == "Nick wants to watch this"

      assert Pennant.tooltip(%{flag: :listing, people: [person("Nick"), person("Sam")]}) ==
               "Nick and Sam want to watch this"
    end
  end
end
