defmodule MediaCentaurWeb.Components.Title.SocialWordsTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [person: 1, own_person: 0]
  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Title.SocialWords

  defp friend(name, attrs), do: %{activity: build_activity(Map.new(attrs)), author: person(name)}

  defp own(sentiment), do: %{activity: build_activity(%{sentiment: sentiment}), author: own_person()}

  describe "by_flag/1" do
    test "nothing for no activity" do
      assert SocialWords.by_flag([]) == []
    end

    test "one entry per flag in order, people in the rows' order with the reader last" do
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

      assert [love, like, dislike, review, watched, listing] = SocialWords.by_flag(rows)

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

  describe "sentence/1" do
    test "reads as a sentence" do
      assert SocialWords.sentence(%{flag: :love, people: [person("Nick")]}) == "Nick loves this"
      assert SocialWords.sentence(%{flag: :like, people: [person("Nick")]}) == "Nick likes this"
      assert SocialWords.sentence(%{flag: :like, people: [own_person()]}) == "You like this"
      assert SocialWords.sentence(%{flag: :dislike, people: [person("Nick")]}) == "Nick dislikes this"

      assert SocialWords.sentence(%{flag: :dislike, people: [person("Nick"), own_person()]}) ==
               "Nick and you dislike this"

      assert SocialWords.sentence(%{flag: :review, people: [person("Nick")]}) == "Nick reviewed this"

      assert SocialWords.sentence(%{flag: :review, people: [person("Nick"), person("Sam")]}) ==
               "Nick and Sam reviewed this"

      assert SocialWords.sentence(%{flag: :love, people: [person("Nick"), person("Sam"), own_person()]}) ==
               "Nick, Sam and you love this"

      assert SocialWords.sentence(%{flag: :watched, people: [person("Nick")]}) == "Nick watched this"

      assert SocialWords.sentence(%{flag: :watched, people: [person("Nick"), person("Sam")]}) ==
               "Nick and Sam watched this"

      assert SocialWords.sentence(%{flag: :listing, people: [person("Nick")]}) ==
               "Nick wants to watch this"

      assert SocialWords.sentence(%{flag: :listing, people: [person("Nick"), person("Sam")]}) ==
               "Nick and Sam want to watch this"
    end
  end

  describe "sentences/1" do
    test "each flag's sentence, keyed by flag" do
      rows = [friend("Nick", sentiment: :love), own(:love), friend("Sam", kind: :watched)]

      assert SocialWords.sentences(rows) == %{
               love: "Nick and you love this",
               watched: "Sam watched this"
             }
    end
  end

  describe "drawn_flags/1" do
    test "a flag is drawn when a friend flew it, in order; the reader's lone acts draw nothing" do
      rows = [
        own(:love),
        friend("Nick", kind: :watched),
        %{activity: build_activity(%{kind: :watched, sentiment: nil}), author: own_person()},
        %{activity: build_activity(%{kind: :listing, sentiment: nil}), author: own_person()},
        friend("Sam", sentiment: :like)
      ]

      assert SocialWords.drawn_flags(rows) == [:like, :watched]
    end
  end
end
