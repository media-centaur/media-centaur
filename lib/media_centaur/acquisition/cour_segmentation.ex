defmodule MediaCentaur.Acquisition.CourSegmentation do
  @moduledoc """
  Segments a show's episodes into **broadcast runs** (cours) from their
  air dates alone — the derived fact behind cour-aware acquisition.

  TMDB folds multiple broadcast runs into one continuous "season"; the
  release world packages them separately ("Season 01 COMPLETE" for the
  first run, encoded before the later run aired). Comparing those two
  views episode-by-episode is what lets the planner stop crediting a
  first-run pack with episodes it cannot physically contain, and lets
  the query side search the right way for a later run.

  A **run** is a contiguous range of episodes (in `{season, episode}`
  order) whose consecutive air dates never gap by more than `gap_days`.
  A gap larger than the threshold starts a new run. `@default_gap_days`
  is 8 weeks — wide enough to keep a back-to-back split-cour (a one- or
  two-week new-year break) in a single run, narrow enough to split a
  genuine production gap of several months.

  Episodes with a `nil` air date attach to the current run — missing
  data never forces a split. The module is pure: `gap_days` defaults to
  the constant but is a parameter, so callers (and tests) can pass their
  own. Runs are recomputed on demand; nothing is persisted (the project
  deriver model).
  """

  @default_gap_days 56

  @type episode :: %{
          required(:season) => integer(),
          required(:episode) => integer(),
          optional(:air_date) => Date.t() | nil
        }

  @type unit :: {integer(), integer()}

  @type run :: %{
          index: non_neg_integer(),
          first_ep: unit(),
          last_ep: unit(),
          date_span: {Date.t(), Date.t()} | nil
        }

  @doc "The default broadcast-gap threshold, in days (8 weeks)."
  @spec default_gap_days() :: pos_integer()
  def default_gap_days, do: @default_gap_days

  @doc """
  Segments `episodes` into ordered broadcast runs. `episodes` is a list
  of `%{season:, episode:, air_date:}` maps (`air_date` may be `nil` or
  absent). Returns runs in episode order, each
  `%{index:, first_ep:, last_ep:, date_span:}`.
  """
  @spec runs([episode()], pos_integer()) :: [run()]
  def runs(episodes, gap_days \\ @default_gap_days) when is_list(episodes) do
    episodes
    |> Enum.sort_by(&{&1.season, &1.episode})
    |> chunk_runs(gap_days)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} -> build_run(chunk, index) end)
  end

  @doc """
  The index of the run containing `{season, episode}`, or `nil` if the
  unit is not among `episodes`. The query side asks "which run is this
  residual unit in?" to decide whether a later-run search is warranted.
  """
  @spec run_index_for([episode()], unit(), pos_integer()) :: non_neg_integer() | nil
  def run_index_for(episodes, {season, episode}, gap_days \\ @default_gap_days) do
    episodes
    |> runs(gap_days)
    |> Enum.find_value(fn run ->
      if within_run?(run, season, episode), do: run.index
    end)
  end

  # Groups the (already sorted) episodes into contiguous chunks, breaking
  # whenever the gap between two consecutive *known* air dates exceeds the
  # threshold. A nil air date never breaks a chunk and never advances the
  # last-known date (so the gap is always measured between real dates).
  defp chunk_runs([], _gap_days), do: []

  defp chunk_runs([first | rest], gap_days) do
    {chunks, current, _last_date} =
      Enum.reduce(rest, {[], [first], air_date(first)}, fn episode, {chunks, current, last_date} ->
        date = air_date(episode)

        cond do
          is_nil(date) ->
            {chunks, [episode | current], last_date}

          is_nil(last_date) ->
            {chunks, [episode | current], date}

          Date.diff(date, last_date) > gap_days ->
            {[Enum.reverse(current) | chunks], [episode], date}

          true ->
            {chunks, [episode | current], date}
        end
      end)

    Enum.reverse([Enum.reverse(current) | chunks])
  end

  defp build_run(chunk, index) do
    first = List.first(chunk)
    last = List.last(chunk)

    dates =
      chunk
      |> Enum.map(&air_date/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort(Date)

    %{
      index: index,
      first_ep: {first.season, first.episode},
      last_ep: {last.season, last.episode},
      date_span: if(dates != [], do: {List.first(dates), List.last(dates)})
    }
  end

  defp within_run?(run, season, episode) do
    {first_season, first_episode} = run.first_ep
    {last_season, last_episode} = run.last_ep

    {first_season, first_episode} <= {season, episode} and
      {season, episode} <= {last_season, last_episode}
  end

  defp air_date(episode), do: Map.get(episode, :air_date)
end
