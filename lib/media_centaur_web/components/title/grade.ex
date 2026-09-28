defmodule MediaCentaurWeb.Components.Title.Grade do
  @moduledoc """
  The grade (UIDR-046): how many of the people you know did one act on
  one title, drawn as the social glyph's material — plain (a white line
  drawing), silver, or gold — on every surface that shows one: a person
  card, a title row, the title detail's social capsule.

  Progressive by count, for every flag alike: one person is plain, two
  silver, three or more gold. Every person counts once per flag on a
  title, the reader included. An act is never weighed against another —
  a thumbs down does not lower a thumbs up. Pure.

  Pure vocabulary, not a function component — no story.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Pure vocabulary, not a function component"

  alias MediaCentaur.Activities.Activity
  alias MediaCentaurWeb.Components.Title.Flag

  @type t :: :plain | :silver | :gold
  @type ref :: {integer(), atom()}

  @doc "The grade for a flag flown by `people` distinct people on one title."
  @spec grade(pos_integer()) :: t()
  def grade(people) when people >= 3, do: :gold
  def grade(2), do: :silver
  def grade(_one), do: :plain

  @doc """
  Every (title, flag) pair's grade over activity rows (anything carrying
  an `activity`): one count per person per title and flag.
  """
  @spec grades([%{activity: Activity.t()}]) :: %{{ref(), Flag.flag()} => t()}
  def grades(rows) do
    rows
    |> Enum.map(fn %{activity: activity} ->
      {{activity.tmdb_id, activity.media_type}, Flag.flag(activity), activity.author_pubkey}
    end)
    |> Enum.uniq()
    |> Enum.frequencies_by(fn {ref, flag, _author} -> {ref, flag} end)
    |> Map.new(fn {pair, people} -> {pair, grade(people)} end)
  end
end
