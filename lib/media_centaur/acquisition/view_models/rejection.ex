defmodule MediaCentaur.Acquisition.ViewModels.Rejection do
  @moduledoc """
  The words for why a candidate release was left out — one place for
  every `Search.Assessment` reason, so the plan board's rejected list
  and the decision card say the same thing.

  `label/1` is the phrase beside one release. `breakdown/1` counts
  rejected releases by reason. `summary/1` is the sentence under a list
  that counts what it left out, by reason.
  """

  alias MediaCentaur.Search.Assessment

  @doc "The phrase beside one rejected release."
  @spec label(Assessment.reason()) :: String.t()
  def label(:red_flag), do: "flagged suspicious"
  def label(:excluded), do: "you excluded this earlier"
  def label(:identity), do: "didn't match this title"
  def label(:coverage), do: "has other episodes"
  def label(:published_early), do: "posted before the title was released"
  def label(:quality), do: "outside your quality range"

  @doc """
  The count of rejected releases by reason, from `[{reason, count}]` in
  the order given: "9 didn't match this title, 3 had other episodes."
  `nil` when there are none.
  """
  @spec breakdown([{Assessment.reason(), pos_integer()}]) :: String.t() | nil
  def breakdown([]), do: nil

  def breakdown(counts),
    do: Enum.map_join(counts, ", ", fn {reason, count} -> "#{count} #{counted(reason)}" end) <> "."

  @doc """
  One sentence counting the releases left out, from `[{reason, count}]`
  in the order given. `nil` when nothing was left out.
  """
  @spec summary([{Assessment.reason(), pos_integer()}]) :: String.t() | nil
  def summary([]), do: nil

  def summary([{reason, count}]), do: "#{found(count)}: #{sole(reason, count)}."

  def summary(counts) do
    total = counts |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    "#{found(total)}: #{breakdown(counts)}"
  end

  defp found(1), do: "1 other release was found and left out"
  defp found(count), do: "#{count} other releases were found and left out"

  defp sole(:red_flag, 1), do: "it was flagged suspicious"
  defp sole(:red_flag, _count), do: "they were flagged suspicious"
  defp sole(:excluded, 1), do: "you already tried it"
  defp sole(:excluded, _count), do: "you already tried them"
  defp sole(:identity, 1), do: "it didn't match this title"
  defp sole(:identity, _count), do: "they didn't match this title"
  defp sole(:coverage, 1), do: "it has other episodes"
  defp sole(:coverage, _count), do: "they have other episodes"
  defp sole(:published_early, 1), do: "it was posted before the title was released"
  defp sole(:published_early, _count), do: "they were posted before the title was released"
  defp sole(:quality, 1), do: "it is outside your quality range"
  defp sole(:quality, _count), do: "they are outside your quality range"

  defp counted(:red_flag), do: "flagged suspicious"
  defp counted(:excluded), do: "you already tried"
  defp counted(:identity), do: "didn't match this title"
  defp counted(:coverage), do: "had other episodes"
  defp counted(:published_early), do: "posted before it was released"
  defp counted(:quality), do: "outside your quality range"
end
