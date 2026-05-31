defmodule MediaCentaur.TMDB.IncidentContext do
  @moduledoc """
  TMDB's contribution to diagnostics — the first concrete
  `ErrorReports.IncidentContext` implementation (the others roll out
  incrementally per the observability campaign).

  TMDB is a stateless HTTP adapter, so it has no per-incident request history to
  `gather/1`; what it can offer is **cross-subsystem vitals** — the current
  rate-limiter window, which is a common culprit when metadata fetches stall.
  Registered as a contributor via `config :media_centaur,
  :diagnostics_contributors`, so `ErrorReports` reaches it through the runtime
  registry with no compile-time dependency in that direction.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.TMDB.RateLimiter

  @impl true
  def vitals, do: %{"rate_limiter" => RateLimiter.status()}
end
