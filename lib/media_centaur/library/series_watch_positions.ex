defmodule MediaCentaur.Library.SeriesWatchPositions do
  @moduledoc """
  Reads and writes `MediaCentaur.Library.SeriesWatchPosition`.

  `record_finish/3` is the one write, called from
  `MediaCentaur.Library.ProgressRecords.finish/3` inside the finish's
  transaction. Nothing outside `Library` reads a position: a caller that
  wants to know where a profile stands reads the derived
  `MediaCentaur.Library.TitleProgress`
  (`ProgressRecords.title_progress/2`, `title_progresses/2`).
  """
  import Ecto.Query

  alias MediaCentaur.Library.{
    Episode,
    EpisodeOrder,
    Movie,
    MovieOrder,
    PlayableItem,
    Season,
    SeriesWatchPosition
  }

  alias MediaCentaur.Repo

  @doc "`profile_id`'s position in a series, or nil."
  @spec get(Ecto.UUID.t(), Ecto.UUID.t()) :: SeriesWatchPosition.t() | nil
  def get(profile_id, series_id),
    do: Repo.get_by(SeriesWatchPosition, profile_id: profile_id, series_id: series_id)

  @doc "`profile_id`'s positions in `series_ids`, keyed by series id."
  @spec by_series(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => SeriesWatchPosition.t()}
  def by_series(_profile_id, []), do: %{}

  def by_series(profile_id, series_ids) do
    from(position in SeriesWatchPosition,
      where: position.profile_id == ^profile_id and position.series_id in ^series_ids
    )
    |> Repo.all()
    |> Map.new(&{&1.series_id, &1})
  end

  @doc "Every profile holding a position in some series."
  @spec profile_ids() :: [Ecto.UUID.t()]
  def profile_ids,
    do: Repo.all(from(position in SeriesWatchPosition, distinct: true, select: position.profile_id))

  @doc """
  Playback finished `playable_item_id`: moves the profile's position in
  the item's series to that item. `:none` when the item belongs to no
  series (a standalone movie or video).
  """
  @spec record_finish(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, SeriesWatchPosition.t()} | {:error, Ecto.Changeset.t()} | :none
  def record_finish(profile_id, playable_item_id, %DateTime{} = finished_at) do
    case series_and_key(Repo.get(PlayableItem, playable_item_id)) do
      nil ->
        :none

      {series_type, series_id, order_key} ->
        (get(profile_id, series_id) || %SeriesWatchPosition{})
        |> SeriesWatchPosition.changeset(%{
          profile_id: profile_id,
          series_type: series_type,
          series_id: series_id,
          order_key: order_key,
          finished_at: finished_at
        })
        |> Repo.insert_or_update()
    end
  end

  defp series_and_key(%PlayableItem{container_type: :episode, container_id: episode_id}) do
    query =
      from(episode in Episode,
        join: season in Season,
        on: season.id == episode.season_id,
        where: episode.id == ^episode_id,
        select: {season.tv_series_id, season.season_number, episode.episode_number}
      )

    case Repo.one(query) do
      {series_id, season_number, episode_number} ->
        {:tv_series, series_id, EpisodeOrder.order_key(season_number, episode_number)}

      nil ->
        nil
    end
  end

  defp series_and_key(%PlayableItem{container_type: :movie, container_id: movie_id}) do
    case Repo.get(Movie, movie_id) do
      %Movie{movie_series_id: series_id} = movie when not is_nil(series_id) ->
        {:movie_series, series_id, MovieOrder.order_key(movie)}

      _standalone ->
        nil
    end
  end

  defp series_and_key(_other), do: nil
end
