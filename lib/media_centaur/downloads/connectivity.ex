defmodule MediaCentaur.Downloads.Connectivity do
  @moduledoc """
  Pure download-client connectivity grading — owned by the producer.

  `QueueMonitor` is the only process that observes poll outcomes, so it
  grades connectivity itself and publishes the grade on each
  `QueueState` snapshot; consumers render the grade and never re-derive
  health. (A previous design had each consumer infer "offline" from
  snapshot *age* relative to the poll cadence — which forced every
  consumer to mirror the monitor's schedule, and mis-graded healthy
  snapshots as outages when the mirrored constants drifted.)

  The grade is a fold over poll outcomes:

  - `:initializing` — no poll outcome observed yet (startup, or right
    after a settings change restarted the conversation).
  - `:live` — the last poll succeeded.
  - `{:transient_failure, since}` — exactly one failed poll. A single
    blip between healthy polls is not an outage; UI renders this as
    healthy and the incident assessor ignores it.
  - `{:offline, since}` — two or more consecutive failed polls. `since`
    is the **first** failure: the outage onset, suitable for "offline
    for 3m" copy and for the incident grace window.
  - `:auth_failed` — the client rejected our credentials. Deterministic,
    not a blip — graded immediately so the UI can offer a reconfigure
    affordance.
  - `:not_configured` — no download client configured; set by the
    monitor directly, not via a poll outcome.

  Any successful poll recovers to `:live` from any grade.
  """

  @type t ::
          :initializing
          | :live
          | {:transient_failure, DateTime.t()}
          | {:offline, DateTime.t()}
          | :auth_failed
          | :not_configured

  @type failure_reason :: :unreachable | :auth_failed

  @doc "Grade before any poll outcome has been observed."
  @spec initial() :: t()
  def initial, do: :initializing

  @doc "A successful poll recovers to `:live` from any grade."
  @spec poll_succeeded(t()) :: t()
  def poll_succeeded(_previous), do: :live

  @doc """
  Folds a failed poll into the grade. One unreachable poll is a
  transient blip; the second consecutive one is an outage dated from
  the first. Auth rejection grades immediately.
  """
  @spec poll_failed(t(), failure_reason(), DateTime.t()) :: t()
  def poll_failed(previous, reason, now \\ DateTime.utc_now())
  def poll_failed(_previous, :auth_failed, _now), do: :auth_failed
  def poll_failed({:transient_failure, since}, :unreachable, _now), do: {:offline, since}
  def poll_failed({:offline, since}, :unreachable, _now), do: {:offline, since}
  def poll_failed(_previous, :unreachable, now), do: {:transient_failure, now}

  @doc """
  A failed poll's cause in plain words, for the Status board's evidence
  (`ClientStatus.last_error`). Takes the driver's raw `{:error, reason}` term.

  A 404 is singled out: a client's API never answers it on its own paths, so
  the address is reaching some other program — typically one that took the
  port first.
  """
  @spec describe_failure(term()) :: String.t()
  def describe_failure(%Req.TransportError{reason: :econnrefused}),
    do: "connection refused — nothing is listening at this address"

  def describe_failure(%Req.TransportError{reason: :timeout}), do: "timed out"
  def describe_failure(%Req.TransportError{reason: :nxdomain}), do: "host name not found"
  def describe_failure(%Req.TransportError{reason: reason}), do: "network error (#{inspect(reason)})"

  def describe_failure({:http_error, 404, _body}),
    do: "HTTP 404 — something else answers at this address; another program may be using the port"

  def describe_failure({:http_error, status, _body}), do: "HTTP #{status}"
  def describe_failure({:http_error, status}), do: "HTTP #{status}"
  def describe_failure(:auth_failed), do: "credentials rejected"
  def describe_failure({:auth_failed, _detail}), do: "credentials rejected"
  def describe_failure({:api_error, message}) when is_binary(message), do: message
  def describe_failure(reason), do: inspect(reason)
end
