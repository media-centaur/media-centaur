defmodule MediaCentarr.Acquisition.GrabStatus do
  @moduledoc """
  The Acquisition grab lifecycle as a typed enum, with bucket predicates
  for the three categories downstream code branches on. Status values
  are stored as strings in the DB (`acquisition_grabs.status`); this
  module is the single source of truth for which strings exist and which
  bucket each belongs to.

  ## Why this exists

  The v0.31.0 fix was a silent miscategorization — the "Queue all" path
  treated terminal-failure rows (cancelled / abandoned) as in-flight, so
  the toast claimed success while no grab was actually queued. The bug
  was invisible until a user noticed.

  Centralising the categorization here, paired with the `MC0014
  GrabStatusContract` Credo check, makes that class of bug structurally
  harder:

    * downstream code calls `in_flight?/1`, `terminal?/1`, `rearmable?/1`
      instead of inlining string lists, so adding a new status requires
      *exactly one* edit (this file) — not a hunt-and-update across the
      codebase
    * the Credo check flags any inline `status in [...]` literal-list
      pattern outside this module and `Grab` (which writes the literals
      to the DB), which is the AST shape of the original bug

  ## Buckets

  | atom             | string         | bucket             | rearmable? |
  |------------------|----------------|--------------------|------------|
  | `:searching`     | `"searching"`  | `:in_flight`       | no         |
  | `:snoozed`       | `"snoozed"`    | `:in_flight`       | no         |
  | `:grabbed`       | `"grabbed"`    | `:terminal_success`| no         |
  | `:abandoned`     | `"abandoned"`  | `:terminal_failure`| yes        |
  | `:cancelled`     | `"cancelled"`  | `:terminal_failure`| yes        |

  Predicates accept either the string form (DB shape) or the atom form
  (typed code shape). Callers should not need to convert.
  """

  @in_flight_strings ~w(searching snoozed)
  @terminal_success_strings ~w(grabbed)
  @terminal_failure_strings ~w(abandoned cancelled)
  @terminal_strings @terminal_success_strings ++ @terminal_failure_strings
  @all_strings @in_flight_strings ++ @terminal_strings

  @type bucket :: :in_flight | :terminal_success | :terminal_failure
  @type t :: :searching | :snoozed | :grabbed | :abandoned | :cancelled

  @doc "Every valid status, as DB strings."
  @spec all() :: [String.t()]
  def all, do: @all_strings

  @doc "Statuses where an Oban job is still alive (eligible for cancellation)."
  @spec in_flight() :: [String.t()]
  def in_flight, do: @in_flight_strings

  @doc "Statuses with no active job and no completed download."
  @spec terminal_failure() :: [String.t()]
  def terminal_failure, do: @terminal_failure_strings

  @doc "All terminal statuses (success or failure)."
  @spec terminal() :: [String.t()]
  def terminal, do: @terminal_strings

  @spec in_flight?(String.t() | atom()) :: boolean()
  def in_flight?(status), do: normalize(status) in @in_flight_strings

  @spec terminal?(String.t() | atom()) :: boolean()
  def terminal?(status), do: normalize(status) in @terminal_strings

  @doc """
  True for terminal-failure rows (cancelled, abandoned). These are the
  only rows `Acquisition.rearm_grab/1` will revive.
  """
  @spec rearmable?(String.t() | atom()) :: boolean()
  def rearmable?(status), do: normalize(status) in @terminal_failure_strings

  @doc """
  Returns the bucket the status belongs to. Raises on unknown — by
  design: an unknown status is a bug, not a runtime condition to handle.
  """
  @spec bucket(String.t() | atom()) :: bucket()
  def bucket(status) do
    str = normalize(status)

    cond do
      str in @in_flight_strings -> :in_flight
      str in @terminal_success_strings -> :terminal_success
      str in @terminal_failure_strings -> :terminal_failure
      true -> raise ArgumentError, "unknown grab status: #{inspect(status)}"
    end
  end

  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(string) when is_binary(string), do: string
end
