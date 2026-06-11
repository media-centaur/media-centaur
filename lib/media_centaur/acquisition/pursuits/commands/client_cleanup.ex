defmodule MediaCentaur.Acquisition.Pursuits.Commands.ClientCleanup do
  @moduledoc """
  Post-transaction removal of abandoned downloads from the download
  client — the shared tail of every command that withdraws intent from
  a release (`Cancel`, `AutoCancel`, `ChangeTarget`).

  Removal tracks intent, never lifecycle (campaign
  pursuit-identity-and-lifecycle): when MC stops wanting a release,
  its download leaves the client in the same gesture, partial data
  included — the content never reached the library. Completed-and-
  imported releases are out of scope by construction (their targets
  are `succeeded`, not cancellable, so they never land here).

  Best-effort and driver-neutral via `Acquisition.cancel_download/1`:
  an unconfigured client or a failed call is logged and never blocks
  the command — the Other-downloads zone remains the safety net.
  Callers must invoke this *after* their Repo transaction commits
  (client I/O never belongs inside `Runner.run/3`).
  """

  require MediaCentaur.Log, as: Log

  @spec stop_downloads(String.t(), [String.t()]) :: :ok
  def stop_downloads(_title, []), do: :ok

  def stop_downloads(title, hashes) when is_list(hashes) do
    Enum.each(hashes, fn hash ->
      case MediaCentaur.Acquisition.cancel_download(hash) do
        :ok ->
          Log.info(
            :acquisition,
            "removed abandoned download — #{title} (#{String.slice(hash, 0, 10)})"
          )

        {:error, reason} ->
          Log.warning(
            :acquisition,
            "could not remove an abandoned download — " <>
              "#{title} (#{String.slice(hash, 0, 10)}): #{inspect(reason)}"
          )
      end
    end)
  end
end
