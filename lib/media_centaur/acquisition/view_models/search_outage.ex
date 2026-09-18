defmodule MediaCentaur.Acquisition.ViewModels.SearchOutage do
  @moduledoc """
  Why a search cannot answer right now, in the half-sentence the board
  reads mid-line — or `nil` while Prowlarr can answer.

  Two surfaces must never report an empty result as knowledge
  (UIDR-016): the gap banner (`ViewModels.GapVerdict`) and the board
  ticker's line for a live search (`IncomingLive.PlanLogic`). Both read
  this, so they cannot disagree, and the sentence outlives the last
  roster read — `MediaCentaur.IntegrationAvailability` stays down until
  a probe says otherwise, where the cached roster observation only ever
  said what someone last happened to see.

  Reads as "Couldn't check availability — Prowlarr is unreachable —
  Season 2".

  Pure (ADR-030) in `reason/1`; `reason/0` is the thin read of the
  published value.
  """

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @doc "The sentence for the currently published Prowlarr availability."
  @spec reason() :: String.t() | nil
  def reason, do: :prowlarr |> IntegrationAvailability.status() |> reason()

  @doc "The sentence for one availability status, or `nil` when a search can still run."
  @spec reason(Status.t()) :: String.t() | nil
  def reason(%Status{state: {:down, _since, reason}}), do: line(reason)
  def reason(%Status{state: :up}), do: nil

  defp line(:unreachable), do: "Prowlarr is unreachable"
  defp line(:rejected), do: "Prowlarr rejected your API key"
  defp line(:blind), do: "no indexers are answering"

  # The hand-off has its own copy, on the pursuit that waits for it — a
  # search is unaffected by a download client Prowlarr cannot reach.
  defp line(:client_unavailable), do: nil

  # Prowlarr does not rate-limit us — its indexers' back-off is `:blind`,
  # and `:rate_limited` is TMDB's.
  defp line(:rate_limited), do: nil
end
