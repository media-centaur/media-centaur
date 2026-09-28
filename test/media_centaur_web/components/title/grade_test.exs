defmodule MediaCentaurWeb.Components.Title.GradeTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaurWeb.Components.Title.Grade

  test "the grade rises with the people who did the act: one is plain, two silver, three or more gold" do
    assert Grade.grade(1) == :plain
    assert Grade.grade(2) == :silver
    assert Grade.grade(3) == :gold
    assert Grade.grade(12) == :gold
  end

  describe "grades/1" do
    test "grades every title and flag by the distinct people who flew it" do
      rows = [
        row(author: "a", kind: :review, sentiment: :love),
        row(author: "b", kind: :review, sentiment: :love),
        row(author: "a", kind: :watched),
        row(author: "b", kind: :watched),
        row(author: "c", kind: :watched),
        row(author: "c", kind: :listing, tmdb_id: 12)
      ]

      assert Grade.grades(rows) == %{
               {{777, :movie}, :love} => :silver,
               {{777, :movie}, :watched} => :gold,
               {{12, :movie}, :listing} => :plain
             }
    end

    test "a person counts once per flag on a title, however many rows carry it" do
      rows = [
        row(author: "a", kind: :watched, id: "one"),
        row(author: "a", kind: :watched, id: "two")
      ]

      assert Grade.grades(rows) == %{{{777, :movie}, :watched} => :plain}
    end

    test "a flag is never weighed against another: a like and a dislike each grade alone" do
      rows = [
        row(author: "a", kind: :review, sentiment: :like),
        row(author: "b", kind: :review, sentiment: :dislike)
      ]

      assert Grade.grades(rows) == %{
               {{777, :movie}, :like} => :plain,
               {{777, :movie}, :dislike} => :plain
             }
    end
  end

  defp row(opts) do
    attrs =
      then(
        %{
          author_pubkey: Keyword.fetch!(opts, :author),
          kind: Keyword.fetch!(opts, :kind),
          sentiment: Keyword.get(opts, :sentiment),
          tmdb_id: Keyword.get(opts, :tmdb_id, 777)
        },
        fn attrs -> if id = opts[:id], do: Map.put(attrs, :id, id), else: attrs end
      )

    %{activity: build_activity(attrs)}
  end

  describe "for_title/1" do
    test "one title's rows graded by flag" do
      rows = [
        row(author: "a", kind: :review, sentiment: :love),
        row(author: "b", kind: :review, sentiment: :love),
        row(author: "a", kind: :watched)
      ]

      assert Grade.for_title(rows) == %{love: :silver, watched: :plain}
    end

    test "nothing for no rows" do
      assert Grade.for_title([]) == %{}
    end
  end
end
