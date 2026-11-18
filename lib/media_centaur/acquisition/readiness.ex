defmodule MediaCentaur.Acquisition.Readiness do
  @moduledoc """
  Whether acquisition may ask Prowlarr anything: the downloads
  feature is on (`MediaCentaur.Features`, ADR-081) and Prowlarr is
  configured and tested (`MediaCentaur.Capabilities`).

  The two facts stay separate everywhere else — a feature is a
  preference, a capability an integration — and meet here because the
  jobs and the drop planner treat them alike: not ready, they wait, and
  nothing queued is lost. A job that returned `:ok` while the feature was
  off would drop the download it was carrying, so off is a wait, the same
  as an unconfigured Prowlarr.
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Features

  @doc "The feature is on and Prowlarr is configured and tested."
  @spec ready?() :: boolean()
  def ready?, do: Features.enabled?(:acquisition) and Capabilities.prowlarr_ready?()
end
