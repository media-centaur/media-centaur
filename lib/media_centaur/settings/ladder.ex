defmodule MediaCentaur.Settings.Ladder do
  @moduledoc """
  Neighbours on a fixed list of stepper values (UIDR-041 §2). A stepper
  is a dumb renderer carrying absolute targets; the value's owner picks
  them here. Off-ladder values step from the nearest rung; the ends
  clamp to themselves so a bound is a no-op rather than an error.
  """

  @doc "The integers from `first` to `last` in steps of `step`, as a ladder."
  @spec range(integer(), integer(), pos_integer()) :: [integer()]
  def range(first, last, step), do: Enum.to_list(first..last//step)

  @doc "The rung below `value`, or the lowest rung when there is none."
  @spec down([number()], number()) :: number()
  def down(ladder, value) do
    case Enum.filter(ladder, &(&1 < value)) do
      [] -> List.first(ladder)
      lower -> List.last(lower)
    end
  end

  @doc "The rung above `value`, or the highest rung when there is none."
  @spec up([number()], number()) :: number()
  def up(ladder, value) do
    case Enum.filter(ladder, &(&1 > value)) do
      [] -> List.last(ladder)
      higher -> List.first(higher)
    end
  end
end
