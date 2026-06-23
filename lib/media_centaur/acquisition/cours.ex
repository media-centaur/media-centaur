defmodule MediaCentaur.Acquisition.Cours do
  @moduledoc """
  Bridges the air-date run model into acquisition: fetches a TMDB tv
  season and segments it into broadcast runs (cours), and answers "which
  *later* run does this unit belong to?".

  Run derivation needs the **whole** season's air dates — the gap that
  marks a later run is invisible from the wanted (late) units alone — so
  the season fetch lives here, in Acquisition (Search stays I/O-free and
  Acquisition-independent). Degrades to no cour-awareness (empty runs) on
  a TMDB error rather than failing the plan.

  The pure run math is `CourSegmentation`; the query/coverage shaping of
  a run is `Search.CourQueries` / `Search.CourCoverage`. Recomputed on
  demand — nothing persisted.
  """

  alias MediaCentaur.Acquisition.CourSegmentation
  alias MediaCentaur.TMDB

  @doc """
  The broadcast runs of a TMDB tv season, segmented from episode air
  dates. `[]` on a TMDB fetch error (degrade — no cour-awareness rather
  than a crashed plan).
  """
  @spec runs_for_season(String.t() | integer(), integer()) :: [CourSegmentation.run()]
  def runs_for_season(tmdb_id, season_number) do
    case TMDB.Client.get_season(to_string(tmdb_id), season_number) do
      {:ok, season_data} ->
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
  The later run (index > 0) a `{season, episode}` unit belongs to, given
  the season's pre-segmented `runs`. `nil` when the season is a single
  run or the unit is in the first run — the cases where the regular
  ladder already searches correctly.
  """
  @spec later_run([CourSegmentation.run()], CourSegmentation.unit()) ::
          CourSegmentation.run() | nil
  def later_run(runs, unit) when length(runs) > 1 do
    Enum.find(runs, fn run -> run.index > 0 and within?(run, unit) end)
  end

  def later_run(_runs, _unit), do: nil

  defp within?(%{first_ep: first, last_ep: last}, unit), do: first <= unit and unit <= last
end
