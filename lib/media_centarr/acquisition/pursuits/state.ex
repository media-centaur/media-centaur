defmodule MediaCentarr.Acquisition.Pursuits.State do
  @moduledoc """
  The pursuit lifecycle as a typed enum.

  Stored as strings in `acquisition_pursuits.state`; this module is the
  single source of truth for which strings exist and which bucket each
  belongs to.

  ## Buckets

  | atom          | string         | bucket             |
  |---------------|----------------|--------------------|
  | `:active`     | `"active"`     | `:in_flight`       |
  | `:satisfied`  | `"satisfied"`  | `:terminal_success`|
  | `:exhausted`  | `"exhausted"`  | `:terminal_failure`|
  | `:cancelled`  | `"cancelled"`  | `:terminal_failure`|

  Predicates accept either the string form (DB shape) or the atom form
  (typed code shape).

  ## Awaiting-decision flag

  Whether a pursuit is blocked on user input is *orthogonal* to its
  lifecycle state and lives on the pursuit row as
  `awaiting_decision_at :: utc_datetime`. Read via
  `awaiting_decision?/1`. The flag is set by
  `Pursuits.Commands.RequestDecision` and cleared by `PickTarget` /
  `ChangeTarget` / any terminal-transition command.
  """

  alias MediaCentarr.Acquisition.Pursuits.Pursuit

  @in_flight_strings ~w(active)
  @terminal_success_strings ~w(satisfied)
  @terminal_failure_strings ~w(exhausted cancelled)
  @terminal_strings @terminal_success_strings ++ @terminal_failure_strings
  @all_strings @in_flight_strings ++ @terminal_strings

  @type bucket :: :in_flight | :terminal_success | :terminal_failure
  @type t :: :active | :satisfied | :exhausted | :cancelled

  @spec all() :: [String.t()]
  def all, do: @all_strings

  @doc "Non-terminal states. Currently `[\"active\"]` — kept as a list for symmetry with `terminal/0`."
  @spec in_flight() :: [String.t()]
  def in_flight, do: @in_flight_strings

  @spec terminal() :: [String.t()]
  def terminal, do: @terminal_strings

  @spec in_flight?(String.t() | atom()) :: boolean()
  def in_flight?(state), do: normalize(state) in @in_flight_strings

  @spec terminal?(String.t() | atom()) :: boolean()
  def terminal?(state), do: normalize(state) in @terminal_strings

  @doc """
  True when the pursuit is waiting on user input — `awaiting_decision_at`
  is set. Orthogonal to `terminal?/1`; a terminal pursuit may still have
  a residual timestamp from the historical record, but the meaningful
  check is "in_flight AND awaiting_decision".
  """
  @spec awaiting_decision?(Pursuit.t()) :: boolean()
  def awaiting_decision?(%Pursuit{awaiting_decision_at: nil}), do: false
  def awaiting_decision?(%Pursuit{awaiting_decision_at: %DateTime{}}), do: true

  @spec bucket(String.t() | atom()) :: bucket()
  def bucket(state) do
    str = normalize(state)

    cond do
      str in @in_flight_strings -> :in_flight
      str in @terminal_success_strings -> :terminal_success
      str in @terminal_failure_strings -> :terminal_failure
      true -> raise ArgumentError, "unknown pursuit state: #{inspect(state)}"
    end
  end

  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(string) when is_binary(string), do: string
end
