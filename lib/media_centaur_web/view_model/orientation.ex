defmodule MediaCentaurWeb.ViewModel.Orientation do
  @moduledoc """
  Title orientation for the detail hero: where the viewer stands in the
  title's ordered playable set, and what the modal does about it.

  One value, three projections: the hero hairline (`:fraction`), whether
  the document opens scrolled to the resume row (`:autoscroll?`), and —
  TV only — which season the accordion opens with
  (`initial_expanded_seasons/1`). A marquee/subline block was a fourth,
  tried and removed as redundant with the Play button's own label
  (2026-08-05).

  Two constructors, one struct. `for_series/2` derives from the
  `SeasonView` list — the hairline reads the *whole series*' watched
  fraction, and season/series counts come from the same
  `SeasonView.watched_count`/`total_count` the accordion headers render,
  so the hero and the season rows can never disagree. `for_collection/1`
  derives from the `MovieListItem` list — the hairline reads the whole
  collection's fraction, the same unit.
  Leaf titles (a bare movie) build no orientation: they are not
  positions in a set, and their PlayCard keeps the percent/remaining row
  instead. `:future` seasons and `Upcoming` parts are excluded from all
  counts — you can't be "through" what you can't watch.

  `MediaCentaur.Library.ProgressSummary` remains the progress source for
  playback labels and library cards; within the detail page, the typed
  item list is the single representation and this module is its
  hero-facing projection.

  Pure — built from `SeriesDetail` / `CollectionDetail` parts, no DB
  access.
  """

  alias MediaCentaurWeb.ViewModel.EpisodeListItem
  alias MediaCentaurWeb.ViewModel.MovieListItem
  alias MediaCentaurWeb.ViewModel.SeasonView

  @enforce_keys [:state, :series, :fraction, :autoscroll?]
  defstruct [:state, :next, :season, :series, :fraction, :autoscroll?]

  @type next :: %{
          season_number: non_neg_integer(),
          episode_number: non_neg_integer()
        }

  @type season :: %{number: non_neg_integer(), watched: non_neg_integer(), total: non_neg_integer()}

  @type series :: %{
          watched: non_neg_integer(),
          total: non_neg_integer(),
          percent: non_neg_integer()
        }

  @type t :: %__MODULE__{
          state: :unstarted | :in_progress | :complete,
          next: next() | nil,
          season: season() | nil,
          series: series(),
          fraction: float(),
          autoscroll?: boolean()
        }

  @doc """
  Builds the orientation for a TV series from the detail page's season
  views and the playback resume hint
  (`MediaCentaur.Playback.ResumeTarget.compute/2` output — string-keyed,
  `"seasonNumber"`/`"episodeNumber"`).

  The resume hint names the next episode when present; otherwise the
  first `:unwatched`/`:current` library item is the next episode. A
  series with every library episode watched has no next episode and no
  current season.

  `:fraction` is the series' watched share across all library seasons —
  full for a completed series (finished, not empty), zero when the
  library holds no episodes yet. `:autoscroll?` is true only mid-series: an
  unstarted series has a *first* episode, not a next one — there is no
  position to return to, so it opens on the hero with season 1 expanded
  underneath; a completed series expands nothing and so has nothing to
  scroll to.
  """
  @spec for_series([SeasonView.t()], map() | nil) :: t()
  def for_series(seasons, resume_hint) do
    library_seasons = Enum.filter(seasons, &(&1.kind == :library))
    series = series_counts(library_seasons)

    if series.total > 0 and series.watched >= series.total do
      %__MODULE__{
        state: :complete,
        next: nil,
        season: nil,
        series: series,
        fraction: 1.0,
        autoscroll?: false
      }
    else
      next = next_episode(library_seasons, resume_hint)
      season = current_season(library_seasons, next)
      state = if series.watched == 0, do: :unstarted, else: :in_progress

      %__MODULE__{
        state: state,
        next: next,
        season: season,
        series: series,
        fraction: series_fraction(series),
        autoscroll?: state == :in_progress and season != nil
      }
    end
  end

  @doc """
  Builds the orientation for a movie collection from the detail page's
  typed item list.

  `:fraction` is the collection's watched share — the collection is the
  unit, there is no season equivalent, so `:season` and `:next` stay
  nil. `:autoscroll?` is true only mid-collection *and* when a library
  row carries the resume-target flag (the row the scroll returns to).
  """
  @spec for_collection([MovieListItem.t()]) :: t()
  def for_collection(movie_items) do
    library_items = Enum.filter(movie_items, &match?(%MovieListItem.Library{}, &1))
    watched = Enum.count(library_items, &(&1.state == :watched))
    total = length(library_items)
    percent = if total > 0, do: round(watched / total * 100), else: 0
    series = %{watched: watched, total: total, percent: percent}

    if total > 0 and watched >= total do
      %__MODULE__{
        state: :complete,
        next: nil,
        season: nil,
        series: series,
        fraction: 1.0,
        autoscroll?: false
      }
    else
      state = if watched == 0, do: :unstarted, else: :in_progress

      %__MODULE__{
        state: state,
        next: nil,
        season: nil,
        series: series,
        fraction: if(total > 0, do: watched / total, else: 0.0),
        autoscroll?: state == :in_progress and Enum.any?(library_items, & &1.is_resume_target)
      }
    end
  end

  @doc """
  Season numbers the accordion opens with on load — the one holding the
  next episode, or none when there is no next episode (a completed
  series opens as a compact rewatch index; a collection has no
  accordion at all).

  Season expansion and the scroll landing are the same "where am I"
  question the hairline answers, so both derive from here rather than
  re-reading the resume target (2026-08-05 auto-orient design; this
  replaces the blanket collapse of 2026-08-04).
  """
  @spec initial_expanded_seasons(t()) :: MapSet.t(non_neg_integer())
  def initial_expanded_seasons(%__MODULE__{season: %{number: number}}), do: MapSet.new([number])
  def initial_expanded_seasons(%__MODULE__{}), do: MapSet.new()

  # --- Derivation ---

  defp series_fraction(%{watched: watched, total: total}) when total > 0, do: watched / total
  defp series_fraction(_series), do: 0.0

  defp series_counts(library_seasons) do
    watched = library_seasons |> Enum.map(&(&1.watched_count || 0)) |> Enum.sum()
    total = library_seasons |> Enum.map(&(&1.total_count || 0)) |> Enum.sum()
    percent = if total > 0, do: round(watched / total * 100), else: 0

    %{watched: watched, total: total, percent: percent}
  end

  defp next_episode(_library_seasons, %{
         "seasonNumber" => season_number,
         "episodeNumber" => episode_number
       })
       when is_integer(season_number) and is_integer(episode_number) do
    %{season_number: season_number, episode_number: episode_number}
  end

  defp next_episode(library_seasons, _hint) do
    library_seasons
    |> library_items()
    |> Enum.find(&(&1.state in [:unwatched, :current]))
    |> case do
      nil ->
        nil

      item ->
        %{
          season_number: item.season_number,
          episode_number: item.episode.episode_number
        }
    end
  end

  defp library_items(library_seasons) do
    library_seasons
    |> Enum.flat_map(& &1.items)
    |> Enum.filter(&match?(%EpisodeListItem.Library{}, &1))
  end

  defp current_season(library_seasons, next) do
    found =
      case next do
        %{season_number: season_number} ->
          Enum.find(library_seasons, &(&1.season_number == season_number))

        nil ->
          nil
      end

    case found do
      nil ->
        nil

      season ->
        %{
          number: season.season_number,
          watched: season.watched_count || 0,
          total: season.total_count || 0
        }
    end
  end
end
