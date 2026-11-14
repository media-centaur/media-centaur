defmodule MediaCentaurWeb.ViewModel.Orientation do
  @moduledoc """
  Title orientation for the detail hero: what the modal does about where
  the viewer stands in the title.

  A projection of the title's `MediaCentaur.Library.TitleProgress` onto
  the detail page's rows, in three parts: the hero hairline (`:fraction`,
  the title progress measure), whether the document opens scrolled to the
  next item's row (`:autoscroll?`), and — TV only — which season the
  accordion opens with (`:season`, read through
  `initial_expanded_seasons/1`). A marquee/subline block was a fourth,
  tried and removed as redundant with the Play button's own label
  (2026-08-05).

  The hairline shows title progress: how far the profile is through the
  current pass. A season header counts watched marks
  (`SeasonView.watched_count`). They are different facts, and on a
  rewatch they differ — every header reads watched while the hairline
  reads the place in the second pass.

  Two constructors, one struct: `for_series/2` over the `SeasonView`
  list, `for_collection/2` over the `MovieRow` list. Leaf titles (a bare
  movie) build no orientation: they are not positions in a set.
  `:future` seasons and `Upcoming` parts carry no rows the next item
  could be.

  Pure — built from `SeriesDetail` / `CollectionDetail` parts, no DB
  access.
  """

  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaurWeb.ViewModel.EpisodeRow
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.ViewModel.SeasonView

  @enforce_keys [:fraction, :autoscroll?]
  defstruct [:season, :fraction, :autoscroll?]

  @type t :: %__MODULE__{
          season: non_neg_integer() | nil,
          fraction: float(),
          autoscroll?: boolean()
        }

  @doc """
  Builds the orientation for a TV series from the detail page's season
  views and the title progress.

  `:season` is the number of the library season holding the next episode,
  nil when there is no next episode (a complete series) or its row is not
  on the page. `:autoscroll?` is true only when the series is in progress
  past its first episode and the next episode has a row: an unstarted
  series has a *first* episode, not a next one, so it opens on the hero
  with that season expanded underneath; a complete series expands nothing
  and so has nothing to scroll to.
  """
  @spec for_series([SeasonView.t()], TitleProgress.t() | nil) :: t()
  def for_series(seasons, title_progress) do
    season = season_of_next(seasons, title_progress)

    %__MODULE__{
      season: season,
      fraction: fraction(title_progress),
      autoscroll?: past_the_first?(title_progress) and season != nil
    }
  end

  @doc """
  Builds the orientation for a movie collection from the detail page's
  typed item list and the title progress. There is no season equivalent,
  so `:season` stays nil; `:autoscroll?` is true only mid-collection
  *and* when the next movie has a library row (the row the scroll
  returns to).
  """
  @spec for_collection([MovieRow.t()], TitleProgress.t() | nil) :: t()
  def for_collection(movie_items, title_progress) do
    %__MODULE__{
      season: nil,
      fraction: fraction(title_progress),
      autoscroll?: past_the_first?(title_progress) and next_listed?(movie_items, title_progress)
    }
  end

  @doc """
  Season numbers the accordion opens with on load — the one holding the
  next episode, or none when there is no next episode (a complete series
  opens as a compact rewatch index; a collection has no accordion at
  all).

  Season expansion and the scroll landing are the same "where am I"
  question the hairline answers, so all three derive from the title
  progress (2026-08-05 auto-orient design; this replaces the blanket
  collapse of 2026-08-04).
  """
  @spec initial_expanded_seasons(t()) :: MapSet.t(non_neg_integer())
  def initial_expanded_seasons(%__MODULE__{season: nil}), do: MapSet.new()
  def initial_expanded_seasons(%__MODULE__{season: number}), do: MapSet.new([number])

  # --- Derivation ---

  defp fraction(title_progress), do: TitleProgress.percent(title_progress) / 100

  defp past_the_first?(%TitleProgress{state: :in_progress, before_next: before_next}),
    do: before_next > 0

  defp past_the_first?(_title_progress), do: false

  defp season_of_next(seasons, %TitleProgress{next: %{item_id: item_id}}) do
    Enum.find_value(seasons, fn
      %SeasonView{kind: :library, season_number: number, items: items} ->
        if Enum.any?(items, &match?(%EpisodeRow.Library{episode: %{id: ^item_id}}, &1)), do: number

      _future ->
        nil
    end)
  end

  defp season_of_next(_seasons, _title_progress), do: nil

  defp next_listed?(movie_items, %TitleProgress{next: %{item_id: item_id}}),
    do: Enum.any?(movie_items, &match?(%MovieRow.Library{movie: %{id: ^item_id}}, &1))

  defp next_listed?(_movie_items, _title_progress), do: false
end
