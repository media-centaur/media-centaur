defmodule MediaCentaur.Acquisition.Pursuits.State do
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
  | `:partial`    | `"partial"`    | `:terminal_success`|
  | `:exhausted`  | `"exhausted"`  | `:terminal_failure`|
  | `:cancelled`  | `"cancelled"`  | `:terminal_failure`|

  Predicates accept either the string form (DB shape) or the atom form
  (typed code shape).

  ## Composite fold (ADR-055)

  A pursuit is a composite over units; its state is `fold_units/1`
  applied to the unit states (`Pursuits.UnitState`). `"partial"` exists
  only at the pursuit level — a terminal composite where some, but not
  all, units were satisfied. It buckets as `:terminal_success` because
  something landed; the UI badges it distinctly.

  ## Awaiting-decision flag

  Whether a pursuit is blocked on user input is a *unit-level* fact
  (`Unit.awaiting_decision_at`, read via `UnitState.awaiting_decision?/1`).
  Pursuit-level "awaiting decision" means "any unit awaiting" and is
  computed by the read side.
  """

  @in_flight_strings ~w(active)
  @terminal_success_strings ~w(satisfied partial)
  @terminal_failure_strings ~w(exhausted cancelled)
  @terminal_strings @terminal_success_strings ++ @terminal_failure_strings
  @all_strings @in_flight_strings ++ @terminal_strings

  @type bucket :: :in_flight | :terminal_success | :terminal_failure
  @type t :: :active | :satisfied | :partial | :exhausted | :cancelled

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
  Folds a composite pursuit's unit states into the pursuit state
  (ADR-055). Pure — callers pass the unit state strings.

  * any unit `"active"` → `"active"`
  * all units `"satisfied"` → `"satisfied"`
  * terminal with ≥1 `"satisfied"` → `"partial"`
  * terminal, none satisfied, ≥1 `"exhausted"` → `"exhausted"`
  * terminal, none satisfied, all `"cancelled"` → `"cancelled"`

  Raises on an empty list — a pursuit with zero units is a bug, not a
  state.
  """
  @spec fold_units([String.t()]) :: String.t()
  def fold_units([]) do
    raise ArgumentError, "cannot fold an empty unit list — every pursuit has at least one unit"
  end

  def fold_units(unit_states) when is_list(unit_states) do
    cond do
      "active" in unit_states -> "active"
      Enum.all?(unit_states, &(&1 == "satisfied")) -> "satisfied"
      "satisfied" in unit_states -> "partial"
      "exhausted" in unit_states -> "exhausted"
      true -> "cancelled"
    end
  end

  @spec bucket(String.t() | atom()) :: bucket()
  def bucket(state) do
    normalized = normalize(state)

    cond do
      normalized in @in_flight_strings -> :in_flight
      normalized in @terminal_success_strings -> :terminal_success
      normalized in @terminal_failure_strings -> :terminal_failure
      true -> raise ArgumentError, "unknown pursuit state: #{inspect(state)}"
    end
  end

  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(string) when is_binary(string), do: string
end
