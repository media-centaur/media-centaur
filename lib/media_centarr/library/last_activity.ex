defmodule MediaCentarr.Library.LastActivity do
  @moduledoc """
  Computes the most recent activity timestamp for an entity.
  Activity is the newest of: when the entity or any child was added, or when anything was last watched.
  Pure function — no DB or side effects.
  """

  @doc """
  Returns the most recent activity timestamp for the given entity, or `nil` if none exist.
  The entity must have `watch_progress`, `movies`, `seasons`, and `extras` already loaded.
  """
  @spec compute(map()) :: DateTime.t() | nil
  def compute(entity) do
    timestamps = [entity.inserted_at]
    watch_timestamps = Enum.map(entity.watch_progress || [], & &1.last_watched_at)
    child_timestamps = child_timestamps(entity)

    (timestamps ++ watch_timestamps ++ child_timestamps)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp child_timestamps(%{type: :movie_series} = entity) do
    Enum.map(entity.movies, & &1.inserted_at) ++
      Enum.map(entity.extras, & &1.inserted_at)
  end

  defp child_timestamps(%{type: :tv_series} = entity) do
    episode_timestamps =
      entity.seasons
      |> Enum.flat_map(& &1.episodes)
      |> Enum.map(& &1.inserted_at)

    season_extra_timestamps =
      entity.seasons
      |> Enum.flat_map(& &1.extras)
      |> Enum.map(& &1.inserted_at)

    entity_extra_timestamps = Enum.map(entity.extras, & &1.inserted_at)

    episode_timestamps ++ season_extra_timestamps ++ entity_extra_timestamps
  end

  defp child_timestamps(entity) do
    Enum.map(entity.extras, & &1.inserted_at)
  end
end
