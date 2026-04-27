defmodule MediaCentarr.WatchHistory.Rewatch do
  @moduledoc """
  Pure Ecto queries for re-watch detection.

  A "re-watch" is any completion event beyond the first for the same entity.
  All functions here are read-only and return plain maps/lists — no Ecto
  schemas leak past the boundary.
  """
  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.WatchHistory.Event

  @type entity_type :: :movie | :episode | :video_object
  @type rewatch_row :: %{
          entity_type: entity_type(),
          entity_id: Ecto.UUID.t(),
          count: pos_integer(),
          last_watched_at: DateTime.t()
        }

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

  @doc """
  Top N entities by completion count, descending.

  Options:
  - `:limit` — max rows (default 25)
  - `:min` — minimum completion count to include (default 1)
  - `:entity_type` — filter to one type, or `:all` (default)
  """
  @spec top_rewatches(keyword()) :: [rewatch_row()]
  def top_rewatches(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    min = Keyword.get(opts, :min, 1)
    type_filter = Keyword.get(opts, :entity_type, :all)

    [:movie, :episode, :video_object]
    |> Enum.filter(&(type_filter == :all or type_filter == &1))
    |> Enum.flat_map(&top_for_type(&1, min))
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  defp top_for_type(type, min) do
    field = type_field(type)

    Event
    |> where([event], not is_nil(field(event, ^field)))
    |> group_by([event], field(event, ^field))
    |> having([event], count(event.id) >= ^min)
    |> select([event], %{
      entity_id: field(event, ^field),
      count: count(event.id),
      last_watched_at: max(event.completed_at)
    })
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :entity_type, type))
  end

  defp type_field(:movie), do: :movie_id
  defp type_field(:episode), do: :episode_id
  defp type_field(:video_object), do: :video_object_id
end
