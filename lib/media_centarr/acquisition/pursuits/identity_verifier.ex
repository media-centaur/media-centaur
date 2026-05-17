defmodule MediaCentarr.Acquisition.Pursuits.IdentityVerifier do
  @moduledoc """
  Post-download orchestrator confirming file identity.

  Triggered by the `Pursuits.InboundListener` when a file lands for an
  active pursuit. Compares the filename to the pursuit's recipe via the
  existing `Acquisition.TitleMatcher` (which now matches against
  `Pursuit` directly — see ADR notes on recipe-typed matching):

    * **Match** → record `:identity_verified` and dispatch
      `Commands.Satisfy` to close the pursuit successfully.
    * **Mismatch** → record `:identity_mismatch` and dispatch
      `Commands.Cancel` (cancelled_by: `:system`, reason
      `"identity_mismatch"`); the file remains on disk for the user to
      review through the existing Review surface.

  The worker exits silently when:
    * the pursuit no longer exists or is already terminal,
    * the file path is missing or unparseable.

  These cases are not errors — the pursuit just doesn't need verification.
  """

  use Oban.Worker, queue: :acquisition, unique: [period: 60, keys: [:pursuit_id, :file_path]]

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit, Recipe, State}
  alias MediaCentarr.Acquisition.Pursuits.Commands.{Cancel, Satisfy}
  alias MediaCentarr.Acquisition.Pursuits.Events.{IdentityMismatch, IdentityVerified}
  alias MediaCentarr.Search.{SearchResult, TitleMatcher}
  alias MediaCentarr.Format

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pursuit_id" => pursuit_id, "file_path" => file_path}}) do
    with {:ok, pursuit} <- load_active_pursuit(pursuit_id) do
      basename = Path.basename(file_path)
      synthetic = %SearchResult{title: basename, guid: "", indexer_id: 0, quality: nil}
      criteria = pursuit |> Recipe.from() |> Recipe.to_criteria()

      if criteria && TitleMatcher.matches?(synthetic, criteria) do
        verify(pursuit, file_path)
      else
        reject(pursuit, file_path, basename)
      end
    end

    :ok
  end

  defp load_active_pursuit(pursuit_id) do
    case Pursuits.get(pursuit_id) do
      {:ok, %Pursuit{state: state} = pursuit} ->
        if State.terminal?(state), do: :skip, else: {:ok, pursuit}

      {:error, :not_found} ->
        :skip
    end
  end

  defp verify(pursuit, file_path) do
    Log.info(:acquisition, "identity verified — #{pursuit.title} (#{Path.basename(file_path)})")

    target = Pursuits.current_target(pursuit)

    {:ok, _event} =
      Events.record(%IdentityVerified{
        pursuit_id: pursuit.id,
        pursuit_title: pursuit.title,
        occurred_at: DateTime.utc_now(:second),
        file_path: file_path
      })

    Satisfy.execute(%{
      pursuit_id: pursuit.id,
      final_target_id: target && target.id,
      final_release_title: (target && target.release_title) || pursuit.title
    })
  end

  defp reject(pursuit, file_path, basename) do
    Log.warning(
      :acquisition,
      "identity mismatch — pursuit expected #{describe(pursuit)}, file is #{basename}"
    )

    {:ok, _event} =
      Events.record(%IdentityMismatch{
        pursuit_id: pursuit.id,
        pursuit_title: pursuit.title,
        occurred_at: DateTime.utc_now(:second),
        expected: describe(pursuit),
        observed: basename,
        file_path: file_path
      })

    Cancel.execute(%{
      pursuit_id: pursuit.id,
      cancelled_by: :system,
      reason: "identity_mismatch"
    })
  end

  defp describe(%Pursuit{tmdb_type: "tv", title: title, season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    "#{title} #{Format.episode_label(season, episode)}"
  end

  defp describe(%Pursuit{title: title, year: year}) when is_integer(year) do
    "#{title} (#{year})"
  end

  defp describe(%Pursuit{title: title}), do: title
end
