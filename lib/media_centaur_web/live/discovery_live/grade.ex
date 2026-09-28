defmodule MediaCentaurWeb.DiscoveryLive.Grade do
  @moduledoc """
  The grade (UIDR-046): how strongly the people you know agree on one
  act on one title, drawn as the act glyph's material on a person card —
  plain (a white line drawing), silver, or gold.

  A flag's **share** is the people who flew it over a denominator that
  depends on the flag:

    * love, like, dislike — the people who gave the title a verdict, so
      someone who only watched or listed it does not dilute an opinion;
    * watched — everyone who engaged with the title, any act at all;
    * reviewed without a verdict, and listing — never graded.

  Under two people a flag is plain whatever its share. From two, half
  the share is silver and two-thirds is gold. Every person counts once
  per flag, the reader included. Pure; `People` feeds it the counts per
  title from the rows it already holds.
  """

  alias MediaCentaurWeb.Components.Title.Flag

  @type t :: :plain | :silver | :gold

  @floor 2
  @verdicts [:love, :like, :dislike]

  @doc """
  The grade of `flag` on a title, from how many distinct people flew each
  flag there (`flown`) and how many distinct people engaged with it at
  all (`engaged`).
  """
  @spec grade(Flag.flag(), %{optional(Flag.flag()) => non_neg_integer()}, non_neg_integer()) :: t()
  def grade(flag, flown, engaged) do
    count = Map.get(flown, flag, 0)

    case denominator(flag, flown, engaged) do
      nil -> :plain
      _of when count < @floor -> :plain
      of when count * 3 >= of * 2 -> :gold
      of when count * 2 >= of -> :silver
      _of -> :plain
    end
  end

  defp denominator(flag, flown, _engaged) when flag in @verdicts,
    do: flown |> Map.take(@verdicts) |> Map.values() |> Enum.sum()

  defp denominator(:watched, _flown, engaged), do: engaged
  defp denominator(_ungraded, _flown, _engaged), do: nil
end
