defmodule MediaCentarr.Acquisition.Pursuits.IdentityVerifier do
  @moduledoc """
  Post-download orchestrator confirming file identity.

  Triggered by the `Pursuits.InboundListener` when a file lands for an
  active pursuit. Compares the filename to the pursuit's latest grab via
  the existing `Acquisition.TitleMatcher`:

    * **Match** → record `:identity_verified` and dispatch
      `Commands.Satisfy` to close the pursuit successfully.
    * **Mismatch** → record `:identity_mismatch` and dispatch
      `Commands.Cancel` (cancelled_by: `:system`, reason
      `"identity_mismatch"`); the file remains on disk for the user to
      review through the existing Review surface.

  The worker exits silently when:
    * the pursuit no longer exists or is already terminal,
    * no grab is linked to the pursuit (we have nothing to match against),
    * the file path is missing or unparseable.

  These cases are not errors — the pursuit just doesn't need verification.
  """

  use Oban.Worker, queue: :acquisition, unique: [period: 60, keys: [:pursuit_id, :file_path]]

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit, State}
  alias MediaCentarr.Acquisition.Pursuits.Commands.{Cancel, Satisfy}
  alias MediaCentarr.Acquisition.Pursuits.Events.{IdentityMismatch, IdentityVerified}
  alias MediaCentarr.Acquisition.{SearchResult, TitleMatcher}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pursuit_id" => pursuit_id, "file_path" => file_path}}) do
    with {:ok, pursuit} <- load_active_pursuit(pursuit_id),
         {:ok, grab} <- Pursuits.latest_grab(pursuit_id) do
      basename = Path.basename(file_path)
      synthetic = %SearchResult{title: basename, guid: "", indexer_id: 0, quality: nil}

      if TitleMatcher.matches?(synthetic, grab) do
        verify(pursuit, grab, file_path)
      else
        reject(pursuit, grab, file_path, basename)
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

  defp verify(pursuit, grab, file_path) do
    Log.info(:acquisition, "identity verified — #{pursuit.title} (#{Path.basename(file_path)})")

    {:ok, _event} =
      Events.record(%IdentityVerified{
        pursuit_id: pursuit.id,
        pursuit_title: pursuit.title,
        occurred_at: DateTime.utc_now(:second),
        file_path: file_path
      })

    Satisfy.execute(%{
      pursuit_id: pursuit.id,
      final_grab_id: grab.id,
      final_release_title: grab.release_title || pursuit.title
    })
  end

  defp reject(pursuit, grab, file_path, basename) do
    Log.warning(
      :acquisition,
      "identity mismatch — pursuit expected #{describe(grab)}, file is #{basename}"
    )

    {:ok, _event} =
      Events.record(%IdentityMismatch{
        pursuit_id: pursuit.id,
        pursuit_title: pursuit.title,
        occurred_at: DateTime.utc_now(:second),
        expected: describe(grab),
        observed: basename,
        file_path: file_path
      })

    Cancel.execute(%{
      pursuit_id: pursuit.id,
      cancelled_by: :system,
      reason: "identity_mismatch"
    })
  end

  defp describe(%{tmdb_type: "tv", title: title, season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    "#{title} S#{pad2(season)}E#{pad2(episode)}"
  end

  defp describe(%{title: title, year: year}) when is_integer(year) do
    "#{title} (#{year})"
  end

  defp describe(%{title: title}), do: title

  defp pad2(n) when n < 10, do: "0" <> Integer.to_string(n)
  defp pad2(n), do: Integer.to_string(n)
end
