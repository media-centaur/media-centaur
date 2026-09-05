defmodule MediaCentaur.ReleaseTracking.LibraryLinks do
  @moduledoc """
  The link between a tracking item and the library container it follows —
  established by TMDB id, kept current as episodes land, dropped when
  the container is deleted. Database-only; the TMDB side of onboarding
  a library series is `ReleaseTracking.AutoTrack`.
  """
  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Helpers
  alias MediaCentaur.Repo

  defp link_unlinked_items(entity_ids) do
    tmdb_mappings = Library.ExternalIds.tmdb_ids_for_tv_series(entity_ids)

    Enum.each(tmdb_mappings, fn {tv_series_id, tmdb_id_str} ->
      with {:ok, tmdb_id} <- Helpers.parse_tmdb_id(tmdb_id_str) do
        from(i in ReleaseTracking.Item,
          where:
            i.tmdb_id == ^tmdb_id and i.media_type == :tv_series and
              is_nil(i.library_container_id)
        )
        |> Repo.all()
        |> Enum.each(fn item ->
          case ReleaseTracking.update_item(item, %{
                 library_container_type: :tv_series,
                 library_container_id: tv_series_id
               }) do
            {:ok, _} ->
              Log.info(
                :acquisition,
                "linked tracking item #{item.name} to library entity #{tv_series_id}"
              )

            {:error, changeset} ->
              Log.info(
                :acquisition,
                "failed to link tracking item #{item.name}: #{inspect(changeset.errors)}"
              )
          end
        end)
      end
    end)
  end

  @doc """
  Reconciles the tracking items that point at `entity_ids` with the
  library: links unlinked items whose TMDB id now has a library series,
  refreshes each linked item's last library episode (marking releases
  in-library and syncing wants when it moved), and deletes items whose
  container is gone.
  """
  @spec refresh_for([Ecto.UUID.t()]) :: :ok
  def refresh_for(entity_ids) do
    link_unlinked_items(entity_ids)

    items =
      Repo.all(from(i in ReleaseTracking.Item, where: i.library_container_id in ^entity_ids))

    existing_ids = batch_existing_container_ids(items)

    Enum.each(items, fn item ->
      if library_container_exists?(item, existing_ids) do
        if item.media_type == :tv_series do
          {season, episode} = Helpers.find_last_library_episode(item.library_container_id)

          if season != item.last_library_season || episode != item.last_library_episode do
            case ReleaseTracking.update_item(item, %{
                   last_library_season: season,
                   last_library_episode: episode
                 }) do
              {:ok, updated_item} ->
                ReleaseTracking.mark_in_library_releases(updated_item)
                ReleaseTracking.sync_wants(updated_item)

              {:error, changeset} ->
                Log.info(
                  :acquisition,
                  "failed to update tracking item #{item.name}: #{inspect(changeset.errors)}"
                )
            end
          end
        end
      else
        Log.info(:acquisition, "removing tracking item #{item.name} — library container deleted")
        ReleaseTracking.delete_item(item)
      end
    end)
  end

  # One IN-query per relevant table instead of one Repo.get per item.
  defp batch_existing_container_ids(items) do
    {tv_ids, movie_series_ids} =
      Enum.reduce(items, {[], []}, fn
        %{library_container_type: :tv_series, library_container_id: id}, {tvs, movies}
        when not is_nil(id) ->
          {[id | tvs], movies}

        %{library_container_type: :movie_series, library_container_id: id}, {tvs, movies}
        when not is_nil(id) ->
          {tvs, [id | movies]}

        _, acc ->
          acc
      end)

    %{
      tv_series: Library.Containers.existing_ids(:tv_series, tv_ids),
      movie_series: Library.Containers.existing_ids(:movie_series, movie_series_ids)
    }
  end

  defp library_container_exists?(%{library_container_type: :tv_series, library_container_id: id}, %{
         tv_series: set
       }) do
    MapSet.member?(set, id)
  end

  defp library_container_exists?(%{library_container_type: :movie_series, library_container_id: id}, %{
         movie_series: set
       }) do
    MapSet.member?(set, id)
  end

  defp library_container_exists?(_, _), do: true
end
