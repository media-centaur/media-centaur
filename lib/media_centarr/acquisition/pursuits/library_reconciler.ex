defmodule MediaCentarr.Acquisition.Pursuits.LibraryReconciler do
  @moduledoc """
  Safety-net for active TMDB-recipe pursuits whose target file is
  already in the library.

  The primary completion path is the PubSub-driven chain:

      Pipeline.Ingest.broadcast → Pursuits.InboundListener →
        Pursuits.IdentityVerifier (Oban) → Commands.Satisfy

  Every link in that chain is in-memory and best-effort. If any step
  drops the message (supervisor restart between broadcast and Oban
  insert, listener crash before `dispatch/1` runs, etc.) the pursuit is
  orphaned indefinitely — active, with the file it was chasing already
  on disk.

  This reconciler closes the gap. For every active pursuit with a TMDB
  recipe, it queries the library by `(tmdb_id, season, episode)` for
  TV or `tmdb_id` for movies. If the matching entity exists and its
  `content_url` is set (file ingested), it dispatches `Commands.Satisfy`
  directly — no title-matching is needed because the TMDB-id match is
  authoritative (the library only sets `content_url` when the file was
  parsed and matched to that TMDB id).

  Invoked by `Pursuits.Watcher` once per tick (15-min cron). Worst-case
  satisfaction latency for the safety-net path is one tick; the primary
  PubSub path remains the seconds-latency happy case.

  Prowlarr-query (non-TMDB) pursuits are skipped — there's no library
  binding to match against.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.Commands.Satisfy
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Library

  @spec reconcile_active() :: :ok
  def reconcile_active do
    Pursuits.list_active()
    |> Enum.filter(&(&1.recipe_type == "tmdb"))
    |> Enum.each(&maybe_satisfy/1)
  end

  defp maybe_satisfy(%Pursuit{} = pursuit) do
    case library_match(pursuit) do
      {:ok, content_url} ->
        Log.info(
          :acquisition,
          "library reconciler — file present, satisfying #{pursuit.title} (#{pursuit.id})"
        )

        Satisfy.execute(%{
          pursuit_id: pursuit.id,
          final_target_id: pursuit.current_target_id,
          final_release_title: Path.basename(content_url)
        })

      :not_found ->
        :ok
    end
  end

  defp library_match(%Pursuit{
         tmdb_type: "tv",
         tmdb_id: tmdb_id,
         season_number: season,
         episode_number: episode
       })
       when is_binary(tmdb_id) and is_integer(season) and is_integer(episode) do
    Library.find_present_episode(tmdb_id, season, episode)
  end

  defp library_match(%Pursuit{tmdb_type: "movie", tmdb_id: tmdb_id}) when is_binary(tmdb_id) do
    Library.find_present_movie(tmdb_id)
  end

  defp library_match(_), do: :not_found
end
