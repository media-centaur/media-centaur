defmodule MediaCentaurWeb.DiscoveryLive.Grade do
  @moduledoc """
  The grade (UIDR-046): how many of the people you know did one act on
  one title, drawn as the act glyph's material on a person card — plain
  (a white line drawing), silver, or gold.

  Progressive by count, for every flag alike: one person is plain, two
  silver, three or more gold. Every person counts once per flag on a
  title, the reader included. An act is never weighed against another —
  a thumbs down does not lower a thumbs up. Pure; `People` counts the
  people per title and flag from the rows it already holds.
  """

  @type t :: :plain | :silver | :gold

  @doc "The grade for a flag flown by `people` distinct people on one title."
  @spec grade(pos_integer()) :: t()
  def grade(people) when people >= 3, do: :gold
  def grade(2), do: :silver
  def grade(_one), do: :plain
end
