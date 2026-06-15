defmodule MediaCentaur.Acquisition.ViewModels.Formatting do
  @moduledoc """
  Shared text helpers for the acquisition view-models (DescentNarrative,
  PlanBoard). Pure — no DB, no I/O.
  """

  @doc ~S'''
  Pluralizes `noun` by `quantity`.

      iex> count(1, "episode")
      "1 episode"
      iex> count(3, "episode")
      "3 episodes"
  '''
  @spec count(non_neg_integer(), String.t()) :: String.t()
  def count(1, noun), do: "1 #{noun}"
  def count(quantity, noun), do: "#{quantity} #{noun}s"
end
