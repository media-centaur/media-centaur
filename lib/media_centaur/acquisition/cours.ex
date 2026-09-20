defmodule MediaCentaur.Acquisition.Cours do
  @moduledoc """
  Bridges the air-date run model into acquisition: reads a tv season
  from the TMDB store and segments it into broadcast runs (cours), and
  answers "which *later* run does this unit belong to?".

  Run derivation needs the **whole** season's air dates — the gap that
  marks a later run is invisible from the wanted (late) units alone — so
  the season read lives here, in Acquisition (Search stays I/O-free and
  Acquisition-independent). The store answers without a request once
  the season has been held (ADR-071); degrades to no cour-awareness
  (empty runs) on a first-contact error rather than failing the plan.

  The pure run math is `CourSegmentation`; the query/coverage shaping of
  a run is `Search.CourQueries` / `Search.CourCoverage`.
  """

  alias MediaCentaur.Acquisition.CourSegmentation
  alias MediaCentaur.Search.Criteria
  alias MediaCentaur.TMDB

  @doc """
  The broadcast runs of a TMDB tv season, segmented from episode air
  dates. `[]` when the store cannot answer (degrade — no cour-awareness
  rather than a crashed plan).
  """
  @spec runs_for_season(String.t() | integer(), integer()) :: [CourSegmentation.run()]
  def runs_for_season(tmdb_id, season_number) do
    case TMDB.Store.ensure_season(tmdb_id, season_number) do
      {:ok, %{payload: season_data}} ->
        season_data
        |> Map.get("episodes", [])
        |> Enum.map(fn episode ->
          %{
            season: season_number,
            episode: episode["episode_number"],
            air_date: TMDB.Mapper.parse_date(episode["air_date"])
          }
        end)
        |> CourSegmentation.runs()

      {:error, _reason} ->
        []
    end
  end

  @doc """
  The criteria with its later broadcast run set, when the wanted episode
  belongs to one — so `Search.QueryBuilder` emits run-shaped queries
  ("Title 2nd Season") instead of the first-run "Season N" that would
  surface the pack the coverage guard already refused. One season fetch
  per call (the caller is a retry attempt or an opened decision card, both
  low-frequency); degrades to the regular queries on a TMDB error. A
  criteria without an episode, or without a TMDB id, is returned as-is.
  """
  @spec with_run(Criteria.t(), String.t() | nil) :: Criteria.t()
  def with_run(
        %Criteria{tmdb_type: :tv, season_number: season, episode_number: episode} = criteria,
        tmdb_id
      )
      when is_integer(season) and is_integer(episode) and is_binary(tmdb_id) do
    runs = runs_for_season(tmdb_id, season)
    %{criteria | run: later_run(runs, {season, episode})}
  end

  def with_run(%Criteria{} = criteria, _tmdb_id), do: criteria

  @doc """
  The later run (index > 0) a `{season, episode}` unit belongs to, given
  the season's pre-segmented `runs`. `nil` when the season is a single
  run or the unit is in the first run — the cases where the regular
  search terms already cover.
  """
  @spec later_run([CourSegmentation.run()], CourSegmentation.unit()) ::
          CourSegmentation.run() | nil
  def later_run(runs, unit) when length(runs) > 1 do
    Enum.find(runs, fn run -> run.index > 0 and within?(run, unit) end)
  end

  def later_run(_runs, _unit), do: nil

  defp within?(%{first_ep: first, last_ep: last}, unit), do: first <= unit and unit <= last
end
