defmodule MediaCentarr.WatchHistory.Rewatch do
  @moduledoc """
  Pure Ecto queries for per-entity completion counts.

  Used by the Watch History page to badge events with the count of times
  the user has finished that entity. Read-only — no schemas leak past the
  boundary.
  """
  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.WatchHistory.Event

  @type entity_type :: :movie | :episode | :video_object

  @doc """
  Count completion events per entity for the given type.
  Returns a map of `entity_id => count`. Entities with zero events are absent.
  """
  @spec count_per_entity(entity_type()) :: %{Ecto.UUID.t() => pos_integer()}
  def count_per_entity(:movie), do: do_count(:movie_id)
  def count_per_entity(:episode), do: do_count(:episode_id)
  def count_per_entity(:video_object), do: do_count(:video_object_id)

  defp do_count(field) do
    Event
    |> where([event], not is_nil(field(event, ^field)))
    |> group_by([event], field(event, ^field))
    |> select([event], {field(event, ^field), count(event.id)})
    |> Repo.all()
    |> Map.new()
  end
end
