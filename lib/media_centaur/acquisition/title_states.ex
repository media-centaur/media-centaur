defmodule MediaCentaur.Acquisition.TitleStates do
  @moduledoc """
  The acquisition state of a TMDB title, for surfaces that list titles
  the library does not own yet (Discovery rows and the title detail
  modal; spec 2026-09-05 §20):

  * `:downloading` — a pursuit for the title is in flight
  * `:needs_review` — a draft plan is `ready`, waiting on a person
  * `:planning` — a draft plan is solving

  A pursuit outranks a draft. Titles with nothing in flight are absent
  from the result. One query per table for the whole list, keyed by
  `{tmdb_id, media_type}` the way `Library.ExternalIds.tmdb_owners/1`
  keys library presence.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State}
  alias MediaCentaur.Repo

  @type ref :: {integer(), :movie | :tv_series}
  @type state :: :downloading | :needs_review | :planning

  @spec for_refs([ref()]) :: %{ref() => state()}
  def for_refs([]), do: %{}

  def for_refs(refs) when is_list(refs) do
    ids = refs |> Enum.map(fn {tmdb_id, _type} -> to_string(tmdb_id) end) |> Enum.uniq()

    drafts =
      Plan
      |> where([p], p.status in ["planning", "ready"] and p.tmdb_id in ^ids)
      |> select([p], {p.tmdb_id, p.tmdb_type, p.status})
      |> Repo.all()
      |> Map.new(fn {tmdb_id, tmdb_type, status} ->
        {ref(tmdb_id, tmdb_type), draft_state(status)}
      end)

    pursuits =
      Pursuit
      |> where([p], p.state in ^State.in_flight() and p.tmdb_id in ^ids)
      |> select([p], {p.tmdb_id, p.tmdb_type})
      |> Repo.all()
      |> Map.new(fn {tmdb_id, tmdb_type} -> {ref(tmdb_id, tmdb_type), :downloading} end)

    wanted = MapSet.new(refs)

    drafts
    |> Map.merge(pursuits)
    |> Map.filter(fn {ref, _state} -> MapSet.member?(wanted, ref) end)
  end

  defp draft_state("ready"), do: :needs_review
  defp draft_state("planning"), do: :planning

  # Only TMDB recipes carry a tmdb_id, so the `in ^ids` filter above
  # guarantees these two literal types.
  defp ref(tmdb_id, "movie"), do: {String.to_integer(tmdb_id), :movie}
  defp ref(tmdb_id, "tv"), do: {String.to_integer(tmdb_id), :tv_series}
end
