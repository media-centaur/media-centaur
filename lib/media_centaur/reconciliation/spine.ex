defmodule MediaCentaur.Reconciliation.Spine do
  @moduledoc """
  Assembles a show's **canonical episode spine** from TMDB (reconciliation
  campaign) — the one impure step the pure engine depends on. The spine is
  always TMDB's ordered episodes (never the library's possibly-incomplete
  season rows), so it is the same source the correct detail view reads.

  `assemble/2` fetches the show's season list, then each season's episodes,
  and marks each node `present?` from a caller-supplied present-set (the
  `{season, episode}` pairs the library already has linked — see
  `Library.ExternalIds.present_episode_keys/1`). It **degrades to an empty spine** on a
  show-fetch error and **skips** any individual season that fails to fetch,
  mirroring `Acquisition.Cours.runs_for_season/2` — a missing spine yields
  no proposals rather than a crash.
  """

  alias MediaCentaur.Reconciliation.SpineNode
  alias MediaCentaur.TMDB
  require MediaCentaur.Log, as: Log

  @spec assemble(integer() | String.t(), MapSet.t({integer(), integer()})) :: [SpineNode.t()]
  def assemble(tmdb_id, present_keys) do
    case TMDB.Client.get_tv(to_string(tmdb_id)) do
      {:ok, data} ->
        data
        |> Map.get("seasons", [])
        |> Enum.map(& &1["season_number"])
        |> Enum.reject(&is_nil/1)
        |> Enum.sort()
        |> Enum.flat_map(&season_nodes(tmdb_id, &1, present_keys))

      {:error, reason} ->
        log_tmdb_failure(reason, "show #{tmdb_id}")
        []
    end
  end

  defp season_nodes(tmdb_id, season_number, present_keys) do
    case TMDB.Client.get_season(to_string(tmdb_id), season_number) do
      {:ok, season_data} ->
        season_data
        |> Map.get("episodes", [])
        |> Enum.map(&node(season_number, &1, present_keys))

      {:error, reason} ->
        log_tmdb_failure(reason, "show #{tmdb_id} season #{season_number}")
        []
    end
  end

  # A silent `[]` here read as "no proposals" to the user; a rejected key
  # is the case that must not hide (the same routing as Discovery's).
  defp log_tmdb_failure(reason, what) do
    if TMDB.Client.auth_failure?(reason) do
      {:http_error, status, _} = reason

      Log.error(
        :pipeline,
        "TMDB API key rejected (HTTP #{status}) — reconciliation spine for #{what} is empty; " <>
          "fix Settings → TMDB"
      )
    else
      Log.warning(:pipeline, "reconciliation — TMDB fetch failed for #{what}: #{inspect(reason)}")
    end
  end

  defp node(season_number, episode, present_keys) do
    number = episode["episode_number"]

    %SpineNode{
      season: season_number,
      episode: number,
      title: episode["name"],
      present?: MapSet.member?(present_keys, {season_number, number})
    }
  end
end
