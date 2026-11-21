defmodule MediaCentaur.Downloads.ClientStatus do
  @moduledoc """
  One configured download-client slot as `QueueMonitor` last saw it: which
  client it is (`upstream`, the `MediaCentaur.HttpClient.Upstream` id its driver
  talks to), the address it polls (`url`), the producer-graded `connectivity`
  (`MediaCentaur.Downloads.Connectivity`), and `last_error` — the failed poll's
  cause in plain words (`Connectivity.describe_failure/1`), nil until a poll
  fails and cleared when one succeeds.

  `QueueState.clients` carries one per slot, so a consumer can say which client
  is down and why without re-deriving anything from the driver's raw errors.
  """

  alias MediaCentaur.Downloads.Connectivity

  @type t :: %__MODULE__{
          upstream: atom(),
          url: String.t() | nil,
          connectivity: Connectivity.t(),
          last_error: String.t() | nil
        }

  defstruct [:upstream, :url, connectivity: :initializing, last_error: nil]
end
