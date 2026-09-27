defmodule MediaCentaurWeb.Components.Title.Pennant do
  @moduledoc """
  The pennant: what friends did with a title, as flags flying inward
  from the right edge of the surface the title is on — the mast. It is
  the one place friend provenance shows, on every title surface
  (UIDR-037): a list row, a search result, the library detail's hero,
  the title detail's hero.

  One pennant per flag, top to bottom: love (a filled heart on the rose
  fill), like (a thumbs up), dislike (a thumbs down), reviewed (a speech
  bubble — a review that gives no verdict), watched (an eye), listing (a
  bookmark) — all but love on a neutral tint, since only love is a
  colour. Which flag an activity flies, the glyph and the order are
  `Title.Flag`'s, the vocabulary the person card's act slots share. A
  pennant carries up to two names and then a
  count ("Nick, Sam", "Nick +2"); the words are `Format.person_name/1`'s,
  so an own review reads "You". Every pennant carries the full sentence
  as a tooltip.

  Fed the `Activities.friend_activity_for/1` rows for one title; the
  grouping (`mast/1`), the label and the tooltip are pure. The mast
  states, it never acts — no nav item. The host places the mast: a row
  bleeds it into its own right padding under `overflow-hidden` so the
  hoist meets the border; a hero flies it in from its right edge, below the corner.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Title.Flag

  @type pennant :: %{flag: Flag.flag(), people: [Person.t()]}

  attr :activity, :list,
    required: true,
    doc: "`Activities.activity_row/0` rows for one title; empty renders nothing"

  attr :label, :string,
    default: nil,
    doc: "replaces the names on every pennant — the Review modal's choice reads Dislike / Like / Love"

  attr :on_image, :boolean, default: false, doc: "over imagery the neutral tint is dark glass"
  attr :class, :string, default: nil

  def pennants(assigns) do
    assigns = assign(assigns, :pennants, mast(assigns.activity))

    ~H"""
    <span :if={@pennants != []} class={["pennant-mast", @class]} data-component="pennants">
      <span
        :for={pennant <- @pennants}
        class={["pennant", "pennant-#{pennant.flag}", @on_image && "pennant-on-image"]}
        title={tooltip(pennant)}
        data-flag={pennant.flag}
      >
        <.icon name={Flag.glyph(pennant.flag)} class="size-3.5" />
        <span>{@label || label(pennant)}</span>
      </span>
    </span>
    """
  end

  @doc """
  The mast for one title's activity rows: one pennant per flag in mast
  order, the people in the rows' order (newest first) with the reader
  last.
  """
  @spec mast([%{activity: Activity.t(), author: Person.t()}]) :: [pennant()]
  def mast(rows) do
    by_flag = Enum.group_by(rows, &Flag.flag(&1.activity))

    for flag <- Flag.mast_order(), group = Map.get(by_flag, flag, []), group != [] do
      {own, friends} = Enum.split_with(group, & &1.author.own?)
      %{flag: flag, people: Enum.map(friends ++ own, & &1.author)}
    end
  end

  @max_named 2

  @doc ~s(Up to two names, then a count: "Nick, Sam", "Nick +2".)
  @spec label(pennant()) :: String.t()
  def label(%{people: people}) do
    names = Enum.map(people, &Format.person_name/1)

    if length(names) <= @max_named,
      do: Enum.join(names, ", "),
      else: "#{hd(names)} +#{length(names) - 1}"
  end

  @doc ~s(The whole statement: "Nick loves this", "Nick dislikes this", "Nick, Sam and you like this", "Nick reviewed this", "Nick wants to watch this".)
  @spec tooltip(pennant()) :: String.t()
  def tooltip(%{flag: flag, people: people}) do
    plural? = length(people) > 1
    subjects = Enum.map(people, &subject_word(&1, plural?))

    subject =
      case subjects do
        [one] -> one
        many -> Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)
      end

    "#{subject} #{verb(flag, people)} this"
  end

  # The reader is "you" mid-sentence and "You" alone.
  defp subject_word(%Person{own?: true}, true), do: "you"
  defp subject_word(person, _plural?), do: Format.person_name(person)

  defp verb(:love, [%Person{own?: false}]), do: "loves"
  defp verb(:like, [%Person{own?: false}]), do: "likes"
  defp verb(:dislike, [%Person{own?: false}]), do: "dislikes"
  defp verb(:listing, [_one]), do: "wants to watch"
  defp verb(:love, _plural_or_you), do: "love"
  defp verb(:like, _plural_or_you), do: "like"
  defp verb(:dislike, _plural_or_you), do: "dislike"
  defp verb(:review, _any), do: "reviewed"
  defp verb(:watched, _any), do: "watched"
  defp verb(:listing, _plural), do: "want to watch"
end
