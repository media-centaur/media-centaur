defmodule MediaCentaurWeb.ViewModel.Orientation do
  @moduledoc """
  Series orientation for the TV detail hero: which episode is next, how
  far through the current season, how far through the series.

  One value, computed once, rendered by the hero (marquee + hairline +
  subline). Season and series counts derive from the same
  `SeasonView.watched_count`/`total_count` the accordion headers render,
  so the hero and the season rows can never disagree. `:future` seasons
  (TMDB-known, no library files) are excluded from all counts — you
  can't be "through" what you can't watch.

  `MediaCentaur.Library.ProgressSummary` remains the progress source for
  playback labels and library cards; within the detail page, the
  `SeasonView` list is the single representation and this module is its
  hero-facing projection.

  Pure — built from `SeriesDetail`'s parts, no DB access.
  """

  import MediaCentaurWeb.LibraryFormatters, only: [format_human_duration: 1]

  alias MediaCentaurWeb.ViewModel.EpisodeListItem
  alias MediaCentaurWeb.ViewModel.SeasonView

  @enforce_keys [:state, :series]
  defstruct [:state, :next, :season, :series]

  @type next :: %{
          season_number: non_neg_integer(),
          episode_number: non_neg_integer(),
          runtime_seconds: number() | nil
        }

  @type season :: %{number: non_neg_integer(), watched: non_neg_integer(), total: non_neg_integer()}

  @type series :: %{
          watched: non_neg_integer(),
          total: non_neg_integer(),
          percent: non_neg_integer(),
          season_count: non_neg_integer()
        }

  @type t :: %__MODULE__{
          state: :unstarted | :in_progress | :complete,
          next: next() | nil,
          season: season() | nil,
          series: series()
        }

  @doc """
  Builds the orientation from the detail page's season views and the
  playback resume hint (`MediaCentaur.Playback.ResumeTarget.compute/2`
  output — string-keyed, `"seasonNumber"`/`"episodeNumber"`).

  The resume hint names the next episode when present; otherwise the
  first `:unwatched`/`:current` library item is the next episode. A
  series with every library episode watched has no next episode and no
  current season.
  """
  @spec build([SeasonView.t()], map() | nil) :: t()
  def build(seasons, resume_hint) do
    library_seasons = Enum.filter(seasons, &(&1.kind == :library))
    series = series_counts(library_seasons)

    if series.total > 0 and series.watched >= series.total do
      %__MODULE__{state: :complete, next: nil, season: nil, series: series}
    else
      next = next_episode(library_seasons, resume_hint)
      state = if series.watched == 0, do: :unstarted, else: :in_progress

      %__MODULE__{
        state: state,
        next: next,
        season: current_season(library_seasons, next),
        series: series
      }
    end
  end

  @doc """
  Fraction (0.0–1.0) of the current season watched — drives the hero
  hairline. Zero when there is no current season.
  """
  @spec season_fraction(t()) :: float()
  def season_fraction(%__MODULE__{season: %{watched: watched, total: total}}) when total > 0,
    do: watched / total

  def season_fraction(%__MODULE__{}), do: 0.0

  @doc """
  Marquee text for the next episode as a `{"S4", "E10"}` pair, or `nil`
  when there is nothing to play next.
  """
  @spec marquee(t()) :: {String.t(), String.t()} | nil
  def marquee(%__MODULE__{next: %{season_number: season, episode_number: episode}}),
    do: {"S#{season}", "E#{episode}"}

  def marquee(%__MODULE__{}), do: nil

  @doc """
  Overline copy above the marquee, keyed to the orientation state.
  """
  @spec overline(t()) :: String.t()
  def overline(%__MODULE__{state: :unstarted}), do: "Start here"
  def overline(%__MODULE__{state: :complete}), do: "Series complete"
  def overline(%__MODULE__{}), do: "Up next"

  @doc """
  The whispered orientation sentence under the marquee, or `nil` when
  there is nothing to say (no library episodes at all).

  Formats: mid-series `"21m · 9 of 22 this season · 49% of the series"`,
  unstarted `"21m · 21 episodes this season · 138 in the series"`,
  complete `"138 episodes watched"`. Single-season series drop the
  series clause (the season is the series).
  """
  @spec subline(t()) :: String.t() | nil
  def subline(%__MODULE__{series: %{total: 0}}), do: nil

  def subline(%__MODULE__{state: :complete, series: series}), do: "#{series.total} episodes watched"

  def subline(%__MODULE__{state: state, next: next, season: season, series: series}) do
    [runtime_segment(next), season_segment(state, season), series_segment(state, series)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # --- Segments ---

  defp runtime_segment(%{runtime_seconds: seconds}) when is_number(seconds) and seconds > 0,
    do: format_human_duration(trunc(seconds))

  defp runtime_segment(_), do: nil

  defp season_segment(_state, nil), do: nil
  defp season_segment(:unstarted, season), do: "#{season.total} episodes this season"
  defp season_segment(_state, season), do: "#{season.watched} of #{season.total} this season"

  defp series_segment(_state, %{season_count: count}) when count <= 1, do: nil
  defp series_segment(:unstarted, series), do: "#{series.total} in the series"
  defp series_segment(_state, series), do: "#{series.percent}% of the series"

  # --- Derivation ---

  defp series_counts(library_seasons) do
    watched = library_seasons |> Enum.map(&(&1.watched_count || 0)) |> Enum.sum()
    total = library_seasons |> Enum.map(&(&1.total_count || 0)) |> Enum.sum()
    percent = if total > 0, do: round(watched / total * 100), else: 0

    %{watched: watched, total: total, percent: percent, season_count: length(library_seasons)}
  end

  defp next_episode(library_seasons, %{
         "seasonNumber" => season_number,
         "episodeNumber" => episode_number
       })
       when is_integer(season_number) and is_integer(episode_number) do
    %{
      season_number: season_number,
      episode_number: episode_number,
      runtime_seconds: runtime_for(library_seasons, season_number, episode_number)
    }
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
          episode_number: item.episode.episode_number,
          runtime_seconds: item.episode.duration_seconds
        }
    end
  end

  defp runtime_for(library_seasons, season_number, episode_number) do
    library_seasons
    |> library_items()
    |> Enum.find(&(&1.season_number == season_number and &1.episode.episode_number == episode_number))
    |> case do
      nil -> nil
      item -> item.episode.duration_seconds
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
