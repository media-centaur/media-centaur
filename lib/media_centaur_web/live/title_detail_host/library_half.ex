defmodule MediaCentaurWeb.Live.TitleDetailHost.LibraryHalf do
  @moduledoc """
  Loads the library half of a title detail by identity: the owner the
  library has for a TMDB ref (`Library.ExternalIds.tmdb_owners/1`),
  resolved to its presentable container (`Library.Presentable.resolve/1`)
  and composed by kind — a `SeriesDetail`, a `CollectionDetail` or a
  `LeafDetail` — into a `Title.Detail.Library`. A collection speaks of
  the member the ref names. Nil when the library does not own the
  title, or owns it without a present file.

  Projection reads, milliseconds (ADR-051): the half loads
  synchronously on open, like every other local fact.
  """

  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Library.Presentable
  alias MediaCentaurWeb.Components.Title.Detail.Library
  alias MediaCentaurWeb.TitleRef
  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.LeafDetail
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  @spec load(TitleRef.ref()) :: Library.t() | nil
  def load({tmdb_id, _media_type} = ref) do
    with owner_id when is_binary(owner_id) <- Map.get(ExternalIds.tmdb_owners([ref]), ref),
         {kind, id} <- Presentable.resolve(owner_id),
         {:ok, entry} <- compose(kind, id) do
      Library.new(entry, member_id(entry, tmdb_id))
    else
      _unowned -> nil
    end
  end

  defp compose(:tv_series, id), do: SeriesDetail.compose(id)
  defp compose(:movie_series, id), do: CollectionDetail.compose(id)
  defp compose(kind, id), do: LeafDetail.compose(kind, id)

  # The member the ref names, so a collection opened on a member's title
  # address speaks of that member (UIDR-023); nil lets the collection
  # pick its default.
  defp member_id(%CollectionDetail{movies: movies}, tmdb_id) do
    Enum.find_value(movies, fn
      %MovieRow.Library{movie: %{tmdb_id: ^tmdb_id, id: id}} -> id
      _other -> nil
    end)
  end

  defp member_id(_entry, _tmdb_id), do: nil
end
