defmodule MediaCentarr.Acquisition.AutoGrabPolicy do
  @moduledoc """
  Pure decision module: given context about a release that just became
  available, returns whether to enqueue, skip, or cancel an auto-grab.

  Takes primitive inputs (booleans and the current grab status string)
  rather than ReleaseTracking schemas. Callers translate their structs
  into these primitives at the boundary — keeping inter-context coupling
  to nothing more than the primitive shapes here.

  The capability gate (`prowlarr_ready`) is evaluated first — when Prowlarr
  is not configured or its last connection test failed, the policy refuses
  to enqueue regardless of every other input. This keeps the auto-grab
  domain inert as long as the integration is unavailable, even if the
  surrounding GenServer or callers forget to gate.

  Phase 2 will add per-item mode and quality bounds. Phase 1 only knows
  about library presence and existing-grab idempotency.
  """

  @type skip_reason ::
          :acquisition_unavailable
          | :already_in_library
          | :already_active
  @type cancel_reason :: atom()
  @type decision :: :enqueue | {:skip, skip_reason()} | {:cancel, cancel_reason()}
  @type opt :: {:prowlarr_ready, boolean()}

  @active_statuses ["searching", "snoozed", "grabbed"]

  @doc """
  Decides what to do for a release that just became available.

  Inputs:
  - `in_library?` — has the file already arrived via watcher / library scan?
  - `existing_grab_status` — current status string of an existing
    `acquisition_grabs` row for this release, or `nil` if none exists.
    Active statuses (`searching`, `snoozed`, `grabbed`) cause a skip;
    terminal-but-resumable statuses (`cancelled`, `abandoned`) re-arm.
  - `opts` — `[prowlarr_ready: boolean()]`. Required.
  """
  @spec decide(boolean(), String.t() | nil, [opt()]) :: decision()
  def decide(in_library?, existing_grab_status, opts) do
    cond do
      not Keyword.fetch!(opts, :prowlarr_ready) -> {:skip, :acquisition_unavailable}
      in_library? -> {:skip, :already_in_library}
      existing_grab_status in @active_statuses -> {:skip, :already_active}
      true -> :enqueue
    end
  end
end
