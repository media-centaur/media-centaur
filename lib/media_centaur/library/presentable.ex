defmodule MediaCentaur.Library.Presentable do
  @moduledoc """
  Resolves any entity id to the identity the user actually sees — a
  `{kind, id}` pair — by applying the movie-vs-collection hoist rule.

  This is the single authority every read surface consults (browse grid,
  detail modal, now-playing), which is the point: without one, the
  surfaces would eventually disagree about whether a given title is a
  movie or a collection.

  The rule turns on how many child movies of a collection are
  *currently present on disk*, so the same id can legitimately resolve
  differently before and after a drive is mounted:

    * standalone movie, present -> `{:movie, id}`
    * collection with exactly one present movie -> `{:movie, child_id}`
      (the collection is hoisted away; the child carries a collection
      reference for the badge)
    * collection with two or more present movies -> `{:movie_series, id}`
    * a movie inside a 2+-present collection -> `{:movie_series, ms_id}`
      (it is not a top-level entity; its collection is)
    * tv series with a present episode -> `{:tv_series, id}`
    * present video object -> `{:video_object, id}`
    * anything absent or unknown -> `:not_found`

  Pairs with `Library.PresentableQueries`, which holds the composable
  query fragments this rule is expressed in.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{
    Episode,
    Movie,
    MovieSeries,
    PlayableItem,
    PresentableQueries,
    Season,
    WatchedFile
  }

  alias MediaCentaur.Repo

  @doc """
  Resolves any entity id + current possession to a **presentable
  identity** — a `{kind, id}` pair — applying the single movie-vs-collection
  hoist rule. This is the one authority every read surface consults
  (browse grid, detail modal, now-playing), so the surfaces can never
  disagree about whether something is a movie or a collection.

  Rules:

    * standalone movie (present) → `{:movie, id}`
    * collection with exactly one present movie → `{:movie, sole_child_id}`
      (the collection is hoisted away; the child carries a collection
      reference for the badge)
    * collection with two or more present movies → `{:movie_series, id}`
    * a movie inside a 2+-present collection → `{:movie_series, ms_id}`
      (it isn't a top-level entity; its collection is — matches the grid)
    * tv series with a present episode → `{:tv_series, id}`
    * present video object → `{:video_object, id}`
    * anything absent / unknown → `:not_found`
  """
  @spec resolve(Ecto.UUID.t()) ::
          {:tv_series | :movie_series | :movie | :video_object, Ecto.UUID.t()} | :not_found
  def resolve(id) when is_binary(id) do
    cond do
      tv_series_present?(id) -> {:tv_series, id}
      Repo.exists?(from(ms in MovieSeries, where: ms.id == ^id)) -> resolve_collection(id)
      movie = Repo.get(Movie, id) -> resolve_movie(movie)
      video_object_present?(id) -> {:video_object, id}
      true -> :not_found
    end
  end

  defp resolve_collection(movie_series_id) do
    case Repo.all(PresentableQueries.present_movie_ids(movie_series_id)) do
      [] -> :not_found
      [sole_child_id] -> {:movie, sole_child_id}
      _multiple -> {:movie_series, movie_series_id}
    end
  end

  defp resolve_movie(%Movie{id: id, movie_series_id: nil}) do
    if movie_present?(id), do: {:movie, id}, else: :not_found
  end

  defp resolve_movie(%Movie{id: id, movie_series_id: movie_series_id}) do
    case Repo.all(PresentableQueries.present_movie_ids(movie_series_id)) do
      [_, _ | _] = _multiple -> {:movie_series, movie_series_id}
      _zero_or_one -> if movie_present?(id), do: {:movie, id}, else: :not_found
    end
  end

  defp tv_series_present?(tv_series_id) do
    Repo.exists?(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on: pi.id == wf.playable_item_id and pi.container_type == :episode,
        join: e in Episode,
        on: e.id == pi.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id == ^tv_series_id
      )
    )
  end

  defp movie_present?(movie_id), do: container_present?(:movie, movie_id)
  defp video_object_present?(video_object_id), do: container_present?(:video_object, video_object_id)

  defp container_present?(container_type, container_id) do
    Repo.exists?(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on: pi.id == wf.playable_item_id and pi.container_type == ^container_type,
        where: pi.container_id == ^container_id
      )
    )
  end
end
