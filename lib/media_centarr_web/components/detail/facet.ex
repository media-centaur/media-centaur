defmodule MediaCentarrWeb.Components.Detail.Facet do
  @moduledoc """
  One column of the entity detail facet strip.

  A facet has a `label` (small uppercase header) and a typed `value`. The
  `kind` discriminator selects how `Detail.FacetStrip` renders the value:

    * `:text` — `value` is a string, rendered plain
    * `:chips` — `value` is a list of strings, rendered with `·` separators
    * `:rating` — `value` is `%{rating: float, vote_count: integer | nil}`,
      rendered as a coloured numeric value plus optional vote subtext

  Construct via the `text/2`, `chips/2`, and `rating/3` helpers — they
  encode each kind's expected value shape so callers don't have to.
  """

  @type kind :: :text | :chips | :rating
  @type rating_value :: %{rating: float(), vote_count: integer() | nil}
  @type value :: String.t() | [String.t()] | rating_value()

  @type t :: %__MODULE__{
          label: String.t(),
          kind: kind(),
          value: value()
        }

  @enforce_keys [:label, :kind, :value]
  defstruct [:label, :kind, :value]

  @spec text(String.t(), String.t() | nil) :: t()
  def text(label, value), do: %__MODULE__{label: label, kind: :text, value: value}

  @spec chips(String.t(), [String.t()] | nil) :: t()
  def chips(label, items), do: %__MODULE__{label: label, kind: :chips, value: items}

  @spec rating(String.t(), float() | nil, integer() | nil) :: t()
  def rating(label, rating, vote_count) do
    %__MODULE__{label: label, kind: :rating, value: %{rating: rating, vote_count: vote_count}}
  end
end
