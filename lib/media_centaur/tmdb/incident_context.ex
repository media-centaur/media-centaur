defmodule MediaCentaur.TMDB.IncidentContext do
  @moduledoc """
  TMDB's contribution to diagnostics, an `ErrorReports.IncidentContext`.

  TMDB is a stateless HTTP adapter, so it has no per-incident request history to
  `gather/1`; what it can offer is **cross-subsystem vitals** — the current
  rate-limiter window, which is a common culprit when metadata fetches stall.
  Registered as a contributor via `config :media_centaur,
  :diagnostics_contributors`, so `ErrorReports` reaches it through the runtime
  registry with no compile-time dependency in that direction.

  ## No `assess/0` here — TMDB's condition lives on the `:http` subsystem

  A sustained TMDB outage does raise a `:subsystem` condition, but
  `MediaCentaur.HttpClient.IncidentContext` is what raises it, so it
  surfaces on the Connections tile beside the *down since* row rather
  than on Metadata. That assessor reads
  `MediaCentaur.IntegrationAvailability` for `:tmdb`: since the
  recurring-traffic audit, work that needs TMDB is held while it is
  down, so there is almost no failing traffic left to grade by, and the
  value a probe keeps current is the evidence instead. Adding a second
  `assess/0` here would mint two incidents for one outage — the rule
  that already keeps Prowlarr, the download clients and GitHub out of
  the `:http` assessor.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.TMDB.RateLimiter

  @impl true
  def vitals, do: %{"rate_limiter" => RateLimiter.status()}
end
