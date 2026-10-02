defmodule MediaCentaurWeb.Components.Title.SocialTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, own_person: 0]
  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaurWeb.Components.Title.Social

  defp row(author, pubkey, attrs) do
    activity =
      attrs
      |> Map.new()
      |> Map.put(:author_pubkey, pubkey)
      |> Map.put_new(:sentiment, nil)
      |> build_activity()

    %{activity: activity, author: author}
  end

  defp nick(attrs), do: row(person("Nick"), "nick", attrs)
  defp sam(attrs), do: row(person("Sam"), "sam", attrs)
  defp cleo(attrs), do: row(person("Cleo"), "cleo", attrs)
  defp you(attrs), do: row(own_person(), "you", attrs)

  describe "panel/1" do
    test "every review in the rows' order, each with its flag at its grade and its words" do
      rows = [
        nick(kind: :review, sentiment: :love, text: "Watch it.", id: "n"),
        you(kind: :review, sentiment: :love, text: "Yes.", id: "y"),
        sam(kind: :review, sentiment: :like, id: "s"),
        cleo(kind: :review, sentiment: nil, text: "Hmm.", id: "c")
      ]

      assert %{reviews: reviews} = Social.panel(rows)

      assert Enum.map(reviews, &{&1.id, &1.flag, &1.grade, &1.text}) == [
               {"n", :love, :silver, "Watch it."},
               {"y", :love, :silver, "Yes."},
               {"s", :like, :plain, nil},
               {"c", :review, :plain, "Hmm."}
             ]

      assert Enum.map(reviews, & &1.author.own?) == [false, true, false, false]
    end

    test "then one sentence per drawn flag that carries no words, in order, at its grade" do
      rows = [
        cleo(kind: :listing),
        nick(kind: :watched),
        sam(kind: :watched),
        you(kind: :watched),
        nick(kind: :review, sentiment: :love, text: "Watch it.")
      ]

      assert %{acts: acts} = Social.panel(rows)

      assert acts == [
               %{flag: :watched, grade: :gold, sentence: "Nick, Sam and you watched this"},
               %{flag: :listing, grade: :plain, sentence: "Cleo wants to watch this"}
             ]
    end

    test "the reader's lone watch or listing is no sentence — nothing a friend did" do
      rows = [you(kind: :watched), you(kind: :listing), nick(kind: :review, sentiment: :like)]

      assert Social.panel(rows).acts == []
    end
  end

  describe "capsule?/1" do
    test "a capsule when a friend did anything; none for the reader alone or no one" do
      assert Social.capsule?([nick(kind: :watched)])
      refute Social.capsule?([you(kind: :review, sentiment: :love, text: "Mine.")])
      refute Social.capsule?([])
    end
  end
end
