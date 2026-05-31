defmodule MediaCentaur.ErrorReports.IncidentContext do
  @moduledoc """
  Behaviour each subsystem implements to participate in diagnostics — the
  boundary-clean inversion of control at the heart of Phase 2.

  A subsystem *depends on `ErrorReports`* to implement this behaviour; the
  reverse never holds. `ErrorReports` discovers and invokes implementations
  through a **runtime registry** (`ErrorReports.Contributors`, config-driven),
  so it has no compile-time dependency on any subsystem.

  Two independent halves — a module may implement either or both:

  - **Detect** (`assess/0`) — a cheap, side-effect-free health check the
    periodic evaluator polls for duration/trend faults. Returns `:ok` when
    healthy, or `{:fault, kind, severity, ids}` to raise/keep a `:subsystem`
    incident (grouped by `{component, kind}`). Subsystems may also raise/resolve
    acute faults directly via the `ErrorReports` API the instant they happen,
    independent of this poll.
  - **Contribute** (`gather/1`) — given the triggering ids of an incident,
    return a map of the structured context that subsystem deems relevant. Must
    be defensive: it runs while something is already wrong. The registry wraps
    it so a raised/slow contributor degrades to `%{}` rather than breaking
    capture.

  A subsystem with no implementation still produces the full baseline report;
  contributors are enrichment, rolled out incrementally.
  """

  @type kind :: atom()
  @type severity :: :warning | :error | :critical
  @type ids :: %{optional(atom()) => term()}

  @doc "Health probe polled by the evaluator. Side-effect-free and cheap."
  @callback assess() :: :ok | {:fault, kind(), severity(), ids()}

  @doc "Structured context for an incident with the given triggering ids."
  @callback gather(ids()) :: map()

  @optional_callbacks assess: 0, gather: 1
end
