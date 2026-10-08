defmodule MediaCentaur.WatchHistory.Rewatch do
  @moduledoc """
  Pure Ecto queries for per-entity completion counts.

  Used by the Watch History page to badge events with the count of times
  the user has finished that entity. Read-only — no schemas leak past the
  boundary.
  """
  import Ecto.Query

  alias MediaCentaur.{Repo, WatchHistory}
  alias MediaCentaur.WatchHistory.Event

  @type entity_type :: :movie | :episode | :video_object

  @doc """
  Count completion events per entity for the given type within `scope`.
  Returns a map of `entity_id => count`. Entities with zero events are absent.
  """
  @spec count_per_entity(WatchHistory.scope(), entity_type()) :: %{Ecto.UUID.t() => pos_integer()}
  def count_per_entity(scope, :movie), do: do_count(scope, :movie_id)
  def count_per_entity(scope, :episode), do: do_count(scope, :episode_id)
  def count_per_entity(scope, :video_object), do: do_count(scope, :video_object_id)

  defp do_count(scope, field) do
    Event
    |> WatchHistory.scoped(scope)
    |> where([event], not is_nil(field(event, ^field)))
    |> group_by([event], field(event, ^field))
    |> select([event], {field(event, ^field), count(event.id)})
    |> Repo.all()
    |> Map.new()
  end
end
