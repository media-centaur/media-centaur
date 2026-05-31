defmodule MediaCentaur.Library.CollectionArtwork do
  @moduledoc """
  Resolves the *effective* artwork for a movie collection (`MovieSeries`).

  A collection's own poster/backdrop come from TMDB's collection record,
  which is sometimes absent, slow to arrive, or lost to a transient fetch
  failure. When the collection has no art of its own for a display role,
  borrow it from a constituent movie so the browse card and the detail hero
  never render blank.

  Only poster and backdrop are borrowable — those read acceptably as "art
  from this franchise". A logo is collection-specific (the franchise
  wordmark, not a single film's), so logos are never borrowed.

  Pure function, no DB. Callers pass the collection's own images and an
  ordered list of candidate fallback images (preferred source first, e.g.
  the earliest movie in the collection). Images may be `Library.Image`
  structs or any map exposing `:role`.
  """

  # Roles a collection may borrow from a constituent movie.
  @borrowable_roles ["poster", "backdrop"]

  @doc """
  Returns `own_images` plus one borrowed image for each borrowable role the
  collection lacks, taken from the first `fallback_images` entry carrying
  that role. Own images always win; the borrow only fills gaps.
  """
  @spec effective_images([map()] | term(), [map()] | term()) :: [map()]
  def effective_images(own_images, fallback_images)
      when is_list(own_images) and is_list(fallback_images) do
    present_roles = MapSet.new(own_images, & &1.role)

    borrowed =
      for role <- @borrowable_roles,
          not MapSet.member?(present_roles, role),
          image = Enum.find(fallback_images, &(&1.role == role)),
          not is_nil(image),
          do: image

    own_images ++ borrowed
  end

  def effective_images(own_images, _fallback) when is_list(own_images), do: own_images
  def effective_images(_own, _fallback), do: []
end
