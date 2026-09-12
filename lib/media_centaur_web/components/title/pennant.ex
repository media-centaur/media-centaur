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
  colour. A review flies its sentiment, or the reviewed flag when it has
  none (`flag/1`). A pennant carries up to two nicknames and then a
  count ("Nick, Sam", "Nick +2"); an own review reads "You". Every
  pennant carries the full sentence as a tooltip.

  Fed the `Activities.friend_activity_for/1` rows for one title; the
  grouping (`mast/1`), the label and the tooltip are pure. The mast
  states, it never acts — no nav item. The host places the mast: a row
  bleeds it into its own right padding under `overflow-hidden` so the
  hoist meets the border; a hero flies it in from its right edge, below the corner.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaurWeb.Components.Title.Sentiment

  @flags [:love, :like, :dislike, :review, :watched, :listing]

  @type flag :: :love | :like | :dislike | :review | :watched | :listing
  @type pennant :: %{flag: flag(), names: [String.t()]}

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
        <.icon name={glyph(pennant.flag)} class="size-3.5" />
        <span>{@label || label(pennant)}</span>
      </span>
    </span>
    """
  end

  defp glyph(sentiment) when sentiment in [:love, :like, :dislike], do: Sentiment.glyph(sentiment)
  defp glyph(:review), do: "hero-chat-bubble-bottom-center-text"
  defp glyph(:watched), do: "hero-eye"
  defp glyph(:listing), do: "hero-bookmark"

  @doc """
  The mast for one title's activity rows: one pennant per flag in mast
  order, the names in the rows' order (newest first) with "You" last.
  """
  @spec pennants([%{activity: Activity.t(), nickname: String.t() | nil, own?: boolean()}]) ::
          [pennant()]
  def mast(rows) do
    by_flag = Enum.group_by(rows, &flag(&1.activity))

    for flag <- @flags, group = Map.get(by_flag, flag, []), group != [] do
      {own, friends} = Enum.split_with(group, & &1.own?)
      names = Enum.map(friends, & &1.nickname) ++ Enum.map(own, fn _row -> "You" end)
      %{flag: flag, names: names}
    end
  end

  @doc "The flag an activity flies: a review by its sentiment, or reviewed when it gives none; the other kinds as themselves."
  @spec flag(Activity.t()) :: flag()
  def flag(%Activity{kind: :review, sentiment: nil}), do: :review
  def flag(%Activity{kind: :review, sentiment: sentiment}), do: sentiment
  def flag(%Activity{kind: kind}), do: kind

  @max_named 2

  @doc ~s(Up to two names, then a count: "Nick, Sam", "Nick +2".)
  @spec label(pennant()) :: String.t()
  def label(%{names: names}) when length(names) <= @max_named, do: Enum.join(names, ", ")
  def label(%{names: [first | rest]}), do: "#{first} +#{length(rest)}"

  @doc ~s(The whole statement: "Nick loves this", "Nick dislikes this", "Nick, Sam and you like this", "Nick reviewed this", "Nick wants to watch this".)
  @spec tooltip(pennant()) :: String.t()
  def tooltip(%{flag: flag, names: names}) do
    subjects = Enum.map(names, &if(&1 == "You" and length(names) > 1, do: "you", else: &1))

    subject =
      case subjects do
        [one] -> one
        many -> Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)
      end

    "#{subject} #{verb(flag, subjects)} this"
  end

  defp verb(:love, [name]) when name != "You", do: "loves"
  defp verb(:like, [name]) when name != "You", do: "likes"
  defp verb(:dislike, [name]) when name != "You", do: "dislikes"
  defp verb(:listing, [_one]), do: "wants to watch"
  defp verb(:love, _plural_or_you), do: "love"
  defp verb(:like, _plural_or_you), do: "like"
  defp verb(:dislike, _plural_or_you), do: "dislike"
  defp verb(:review, _any), do: "reviewed"
  defp verb(:watched, _any), do: "watched"
  defp verb(:listing, _plural), do: "want to watch"
end
