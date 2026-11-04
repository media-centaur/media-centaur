defmodule MediaCentaurWeb.Components.Title.SocialWords do
  @moduledoc """
  The words for what people did with one title: the title's activity
  rows grouped by flag (`by_flag/1`, in `Flag.order/0`, each flag's
  people newest first with the reader last) and each group as a
  sentence — "Nick loves this", "Nick, Sam and you watched this",
  "Cleo wants to watch this" (`sentence/1`). A social glyph's hover
  text and the social panel's lines for the acts that carry no words.
  The names are `Format.person_name/1`'s: the reader is "You" alone and
  "you" mid-sentence. The Review modal's words come from here too: the
  reader's own verb for its headline (`own_verb/1`) and the line naming
  who will see a review (`audience/1`).

  Pure vocabulary, not a function component — no story.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Pure vocabulary, not a function component"

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Title.Flag

  @type group :: %{flag: Flag.flag(), people: [Person.t()]}

  @doc """
  One title's activity rows as one group per flag in order, the people
  in the rows' order (newest first) with the reader last.
  """
  @spec by_flag([%{activity: Activity.t(), author: Person.t()}]) :: [group()]
  def by_flag(rows) do
    grouped = Enum.group_by(rows, &Flag.flag(&1.activity))

    for flag <- Flag.order(), group = Map.get(grouped, flag, []), group != [] do
      {own, friends} = Enum.split_with(group, & &1.author.own?)
      %{flag: flag, people: Enum.map(friends ++ own, & &1.author)}
    end
  end

  @doc """
  The flags a title surface draws, in order: those at least one friend
  flew. The reader counts toward a flag's grade but never draws one
  alone — the bookmark, the watched state and the Review control
  already say what the reader did.
  """
  @spec drawn_flags([%{activity: Activity.t(), author: Person.t()}]) :: [Flag.flag()]
  def drawn_flags(rows) do
    for %{flag: flag, people: people} <- by_flag(rows),
        Enum.any?(people, &(not &1.own?)),
        do: flag
  end

  @doc "Each flag's sentence for one title's rows, keyed by flag."
  @spec sentences([%{activity: Activity.t(), author: Person.t()}]) :: %{Flag.flag() => String.t()}
  def sentences(rows), do: Map.new(by_flag(rows), &{&1.flag, sentence(&1)})

  @doc ~s(The whole statement: "Nick loves this", "Nick dislikes this", "Nick, Sam and you like this", "Nick reviewed this", "Nick wants to watch this".)
  @spec sentence(group()) :: String.t()
  def sentence(%{flag: flag, people: people}) do
    plural? = length(people) > 1
    subject = people |> Enum.map(&subject_word(&1, plural?)) |> join_names()
    "#{subject} #{verb(flag, people)} this"
  end

  @doc ~s(The reader's own verb for a flag — "love", "like", "dislike", "reviewed" — the clause sentence/1 uses for the reader. The Review modal's headline.)
  @spec own_verb(Flag.flag()) :: String.t()
  def own_verb(flag), do: verb(flag, [%Person{own?: true}])

  @doc ~s(Who will see a review: "Nick will see it", "Nick, Sam and Cleo will see it", "Nick, Sam and 3 others will see it" for four or more.)
  @spec audience([Person.t()]) :: String.t()
  def audience(people) when is_list(people) and people != [] do
    names = Enum.map(people, &Format.person_name/1)

    subject =
      case names do
        [first, second | rest] when length(rest) > 1 -> "#{first}, #{second} and #{length(rest)} others"
        few -> join_names(few)
      end

    subject <> " will see it"
  end

  # "Nick", "Nick and Sam", "Nick, Sam and Cleo".
  defp join_names([one]), do: one
  defp join_names(many), do: Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)

  # The reader is "you" mid-sentence and "You" alone.
  defp subject_word(%Person{own?: true}, true), do: "you"
  defp subject_word(person, _plural?), do: Format.person_name(person)

  defp verb(:love, [%Person{own?: false}]), do: "loves"
  defp verb(:like, [%Person{own?: false}]), do: "likes"
  defp verb(:dislike, [%Person{own?: false}]), do: "dislikes"
  defp verb(:listing, [%Person{own?: false}]), do: "wants to watch"
  defp verb(:love, _plural_or_you), do: "love"
  defp verb(:like, _plural_or_you), do: "like"
  defp verb(:dislike, _plural_or_you), do: "dislike"
  defp verb(:review, _any), do: "reviewed"
  defp verb(:watched, _any), do: "watched"
  defp verb(:listing, _plural_or_you), do: "want to watch"
end
