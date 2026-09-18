defmodule MediaCentaur.TMDB.IncidentContext do
  @moduledoc """
  TMDB's contribution to diagnostics, an `ErrorReports.IncidentContext`.

  TMDB is a stateless HTTP adapter, so it has no per-incident request history to
  `gather/1`; what it can offer is **cross-subsystem vitals** — the current
  rate-limiter window, which is a common culprit when metadata fetches stall.
  Registered as a contributor via `config :media_centaur,
  :diagnostics_contributors`, so `ErrorReports` reaches it through the runtime
  registry with no compile-time dependency in that direction.

  ## No `assess/0`, deliberately — and an open question

  TMDB has no `:subsystem` condition: a sustained TMDB outage raises
  nothing on the Status board the way a Prowlarr one does
  (`Search.IncidentContext`). Until 2026-09-18 there was no continuous
  signal to raise one from; now there is —
  `MediaCentaur.IntegrationAvailability` holds `:tmdb`, kept current
  while down by `TMDB.ProbeJob`, and the Connections tile shows *down
  since* from it. Whether that should also become a condition here is an
  open design question left with the owner when
  `campaigns/recurring-traffic-audit.md` closed; the shape, if it is
  taken, is `Search.IncidentContext`'s: `decide/3` over the availability
  status plus a grace window.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.TMDB.RateLimiter

  @impl true
  def vitals, do: %{"rate_limiter" => RateLimiter.status()}
end
