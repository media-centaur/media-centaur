defmodule MediaCentaur.ReleaseTracking.Identity do
  @moduledoc """
  The `TMDB.TitleIdentity` a tracked title — or one of its wants — names.

  Lives here rather than in TMDB because it reads this context's schemas,
  and TMDB must not depend on its consumers.

  ## Why a want needs its own answer

  A tracked movie's want is usually the film itself, and then the item's
  identity *is* the want's: same TMDB id, so the item's IMDb id and
  original title describe it correctly.

  A want for a **collection part** is a different film. We hold the part's
  TMDB id and title and nothing else — claiming the item's IMDb id there
  would assert the wrong identity, which is worse than asserting none
  (`TitleMatcher` rejects a mismatching id outright). So a part's identity
  carries its own ids only, and the match degrades to the name heuristic.

  That distinction used to live as two `if solo_movie?` helpers in the
  drop planner, applied on one of its two movie paths and absent from the
  other. One place now.
  """

  alias MediaCentaur.ReleaseTracking.{Item, Want}
  alias MediaCentaur.TMDB.TitleIdentity

  @doc """
  The identity of the tracked title itself — what a TV plan searches for,
  and the starting point for a movie want.
  """
  @spec for_item(Item.t()) :: TitleIdentity.t()
  def for_item(%Item{} = item) do
    TitleIdentity.new(%{
      tmdb_type: item.media_type,
      tmdb_id: item.tmdb_id,
      title: item.name,
      imdb_id: item.imdb_id,
      tvdb_id: item.tvdb_id,
      original_title: item.original_title,
      year: item.year,
      origin_country: item.origin_country || []
    })
  end

  @doc """
  The identity of the film one movie want names.

  The want *is* the tracked film when their TMDB ids agree — it inherits
  the item's full identity, under the want's own title. Otherwise it is a
  collection part: its own id and title, and no borrowed ids.

  ## Where a movie's year comes from

  For the tracked film, the year is the title's own — TMDB's answer,
  carried on the item. While that is still nil (an item refreshed before
  the column existed), the want's acquirable date is the best available
  stand-in.

  For a collection part it is the *only* source: we hold no TMDB detail
  for a part, and its want's `air_date` is that film's release date. So
  the want is not scope answering an identity question here — for a part,
  the want row is where the part's identity lives.
  """
  @spec for_want(Item.t(), Want.t()) :: TitleIdentity.t()
  def for_want(%Item{} = item, %Want{part_tmdb_id: part_tmdb_id} = want) do
    if solo_movie?(item, want) do
      identity = for_item(item)
      %{identity | title: want.title || item.name, year: identity.year || want_year(want)}
    else
      TitleIdentity.new(%{
        tmdb_type: :movie,
        tmdb_id: part_tmdb_id,
        title: want.title || item.name,
        year: want_year(want)
      })
    end
  end

  defp want_year(%Want{air_date: %Date{year: year}}), do: year
  defp want_year(%Want{}), do: nil

  defp solo_movie?(%Item{} = item, %Want{} = want),
    do: to_string(want.part_tmdb_id) == to_string(item.tmdb_id)
end
