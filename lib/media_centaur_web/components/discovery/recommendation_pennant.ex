defmodule MediaCentaurWeb.Components.Discovery.RecommendationPennant do
  @moduledoc """
  The recommendation pennant: who recommended a title and how much, as
  flags flying inward from the right edge of the surface the title is on
  — the mast. One pennant per sentiment, love (a filled heart on the rose
  fill) above like (a thumbs up on a neutral tint). A named pennant
  carries up to two nicknames and then a count ("Nick, Sam", "Nick +2");
  an own recommendation reads "You". Icon-only where the surface already
  says who (the Feed lead). Every pennant carries the full sentence as a
  tooltip.

  Fed the `Activities.recommendations_for/1` rows for one title; the
  grouping (`pennants/1`), the label and the tooltip are pure. The mast
  states, it never acts — no nav item. The host places the mast: a row
  bleeds it into its own right padding under `overflow-hidden` so the
  hoist meets the border; a hero pins it to its right edge.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Activities.Activity

  @type pennant :: %{sentiment: Activity.sentiment(), names: [String.t()]}

  attr :recommendations, :list,
    required: true,
    doc: "`Activities.feed_row/0` rows of kind recommendation for one title; empty renders nothing"

  attr :named?, :boolean, default: true, doc: "false drops the names — the surface already says who"

  attr :label, :string,
    default: nil,
    doc: "replaces the names on every pennant — the Recommend modal's choice reads Like / Love"

  attr :on_image, :boolean, default: false, doc: "over imagery the like body is dark glass"
  attr :class, :string, default: nil

  def recommendation_pennants(assigns) do
    assigns = assign(assigns, :pennants, pennants(assigns.recommendations))

    ~H"""
    <span
      :if={@pennants != []}
      class={["pennant-mast", @class]}
      data-component="recommendation-pennants"
    >
      <span
        :for={pennant <- @pennants}
        class={[
          "pennant",
          "pennant-#{pennant.sentiment}",
          !@named? && "pennant-icon-only",
          @on_image && "pennant-on-image"
        ]}
        title={tooltip(pennant)}
        data-sentiment={pennant.sentiment}
      >
        <.icon name={glyph(pennant.sentiment)} class="size-3.5" />
        <span :if={@named?}>{@label || label(pennant)}</span>
      </span>
    </span>
    """
  end

  defp glyph(:love), do: "hero-heart-solid"
  defp glyph(:like), do: "hero-hand-thumb-up"

  @doc """
  The pennants for one title's recommendation rows: one per sentiment,
  love first, the names in the rows' order (newest first) with "You"
  last.
  """
  @spec pennants([%{activity: Activity.t(), nickname: String.t() | nil, own?: boolean()}]) ::
          [pennant()]
  def pennants(rows) do
    by_sentiment = Enum.group_by(rows, & &1.activity.sentiment)

    for sentiment <- Enum.reverse(Activity.sentiments()),
        group = Map.get(by_sentiment, sentiment, []),
        group != [] do
      {own, friends} = Enum.split_with(group, & &1.own?)
      names = Enum.map(friends, & &1.nickname) ++ Enum.map(own, fn _row -> "You" end)
      %{sentiment: sentiment, names: names}
    end
  end

  @max_named 2

  @doc ~s(Up to two names, then a count: "Nick, Sam", "Nick +2".)
  @spec label(pennant()) :: String.t()
  def label(%{names: names}) when length(names) <= @max_named, do: Enum.join(names, ", ")
  def label(%{names: [first | rest]}), do: "#{first} +#{length(rest)}"

  @doc ~s(The whole statement: "Nick loves this", "Nick, Sam and you like this".)
  @spec tooltip(pennant()) :: String.t()
  def tooltip(%{sentiment: sentiment, names: names}) do
    subjects = Enum.map(names, &if(&1 == "You" and length(names) > 1, do: "you", else: &1))

    subject =
      case subjects do
        [one] -> one
        many -> Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)
      end

    "#{subject} #{verb(sentiment, subjects)} this"
  end

  defp verb(:love, [name]) when name != "You", do: "loves"
  defp verb(:like, [name]) when name != "You", do: "likes"
  defp verb(:love, _plural_or_you), do: "love"
  defp verb(:like, _plural_or_you), do: "like"
end
