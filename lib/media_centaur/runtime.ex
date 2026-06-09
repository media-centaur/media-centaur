defmodule MediaCentaur.Runtime do
  use Boundary, deps: [MediaCentaur.ErrorReports], exports: [Vitals]

  @moduledoc """
  Application-runtime introspection for the System status tile: BEAM/VM vitals,
  uptime, host/build facts, and datastore footprint. Read-only snapshots — no
  processes, no persistence. Named `Runtime` (not `System`) to avoid clashing
  with Elixir's `System` module.
  """
end
