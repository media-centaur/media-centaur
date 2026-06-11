defmodule MediaCentaur.Retention.Policy do
  @moduledoc """
  Declares one data-retention policy: what data a subsystem keeps, for
  how long, and how the excess is removed.

  ## Modes

    * `:sweep` — pruned by the daily `MediaCentaur.Retention.SweepJob`.
      `run` is a zero-arity function returning the number of rows/files
      removed; it must be idempotent (a retried sweep re-runs it).
    * `:external` — pruned outside the sweep on its own cadence (an Oban
      plugin, a 15-minute tick, an inline cap). The policy exists so the
      behavior is *described* on the Status page; the external pruner may
      report counts via `MediaCentaur.Retention.record_run/2`.
    * `:forever` — retained permanently by design (e.g. watch history).
      Declared so the decision is visible, not implicit.

  `subsystem` must be one of the Status-page health-board subsystem keys
  (`:watcher`, `:pipeline`, `:tmdb`, `:playback`, `:library`,
  `:acquisition`, `:self_update`, `:system`) — it routes the policy onto
  that subsystem's drill-in.
  """

  @enforce_keys [:key, :subsystem, :label, :description, :mode]
  defstruct [:key, :subsystem, :label, :description, :mode, :run]

  @type mode :: :sweep | :external | :forever

  @type t :: %__MODULE__{
          key: atom(),
          subsystem: atom(),
          label: String.t(),
          description: String.t(),
          mode: mode(),
          run: (-> non_neg_integer()) | nil
        }
end
