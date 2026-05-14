defmodule MediaCentarr.Acquisition.TargetStatus do
  @moduledoc """
  The Acquisition target lifecycle as a typed enum, with bucket
  predicates for the three categories downstream code branches on.
  Status values are stored as strings in the DB
  (`acquisition_targets.status`); this module is the single source of
  truth for which strings exist and which bucket each belongs to.

  ## Why this exists

  The v0.31.0 fix was a silent miscategorization — the "Queue all" path
  treated terminal-failure rows as in-flight, so the toast claimed
  success while no acquisition was actually queued. The bug was
  invisible until a user noticed.

  Centralising the categorization here, paired with the `MC0014`
  Credo check, makes that class of bug structurally harder:

    * downstream code calls `in_flight?/1`, `terminal?/1`,
      `rearmable?/1` instead of inlining string lists, so adding a new
      status requires exactly one edit (this file) — not a
      hunt-and-update across the codebase
    * the Credo check flags any inline `status in [...]` literal-list
      pattern outside this module and `Target` (which writes the
      literals to the DB), which is the AST shape of the original bug

  ## Buckets

  | atom          | string        | bucket             | rearmable? |
  |---------------|---------------|--------------------|------------|
  | `:seeking`    | `"seeking"`   | `:in_flight`       | no         |
  | `:acquired`   | `"acquired"`  | `:terminal_success`| yes        |
  | `:succeeded`  | `"succeeded"` | `:terminal_success`| no         |
  | `:failed`     | `"failed"`    | `:terminal_failure`| yes        |
  | `:cancelled`  | `"cancelled"` | `:terminal_failure`| yes        |

  `acquired` sits in `:terminal_success` because the search half of the
  worker's job has succeeded — Prowlarr accepted the release and the
  download client has it. The pursuit is now waiting for the file to
  land; if it doesn't, the user can `ChangeTarget` (which moves the
  target to `:failed` and starts a new one), so the row is still
  considered rearmable.

  `succeeded` is the *file-landed* terminal — no further attempts are
  ever made.

  Predicates accept either the string form (DB shape) or the atom form
  (typed code shape). Callers should not need to convert.
  """

  @in_flight_strings ~w(seeking)
  @terminal_success_strings ~w(acquired succeeded)
  @terminal_failure_strings ~w(failed cancelled)
  @rearmable_strings ~w(acquired failed cancelled)
  # "Cancel command can still flip this row" — `seeking` (worker
  # alive) and `acquired` (Prowlarr accepted, download in progress).
  # Excludes `succeeded` (file landed; nothing to cancel) and the
  # `:terminal_failure` rows (already gone). Wider than `in_flight`
  # because zero-seeders fires on `acquired` torrents.
  @cancellable_strings ~w(seeking acquired)
  @terminal_strings @terminal_success_strings ++ @terminal_failure_strings
  @all_strings @in_flight_strings ++ @terminal_strings

  @type bucket :: :in_flight | :terminal_success | :terminal_failure
  @type t :: :seeking | :acquired | :succeeded | :failed | :cancelled

  @doc "Every valid status, as DB strings."
  @spec all() :: [String.t()]
  def all, do: @all_strings

  @doc "Statuses where an Oban job is still alive (eligible for cancellation)."
  @spec in_flight() :: [String.t()]
  def in_flight, do: @in_flight_strings

  @doc "Statuses with no active job and no completed acquisition."
  @spec terminal_failure() :: [String.t()]
  def terminal_failure, do: @terminal_failure_strings

  @doc "All terminal statuses (success or failure)."
  @spec terminal() :: [String.t()]
  def terminal, do: @terminal_strings

  @doc "Statuses that `Acquisition.rearm_target/1` will revive into `seeking`."
  @spec rearmable() :: [String.t()]
  def rearmable, do: @rearmable_strings

  @doc """
  Statuses where a cancel command should flip the row to `cancelled` —
  `seeking` (worker alive) and `acquired` (Prowlarr accepted, download
  in progress). Excludes `succeeded` (file already landed) and the
  terminal-failure rows (already gone).
  """
  @spec cancellable() :: [String.t()]
  def cancellable, do: @cancellable_strings

  @spec in_flight?(String.t() | atom()) :: boolean()
  def in_flight?(status), do: normalize(status) in @in_flight_strings

  @spec terminal?(String.t() | atom()) :: boolean()
  def terminal?(status), do: normalize(status) in @terminal_strings

  @doc """
  True for rows that `Acquisition.rearm_target/1` will revive — every
  terminal status except `succeeded` (the file is here; nothing to
  rearm).
  """
  @spec rearmable?(String.t() | atom()) :: boolean()
  def rearmable?(status), do: normalize(status) in @rearmable_strings

  @doc """
  Returns the bucket the status belongs to. Raises on unknown — by
  design: an unknown status is a bug, not a runtime condition to
  handle.
  """
  @spec bucket(String.t() | atom()) :: bucket()
  def bucket(status) do
    str = normalize(status)

    cond do
      str in @in_flight_strings -> :in_flight
      str in @terminal_success_strings -> :terminal_success
      str in @terminal_failure_strings -> :terminal_failure
      true -> raise ArgumentError, "unknown target status: #{inspect(status)}"
    end
  end

  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(string) when is_binary(string), do: string
end
