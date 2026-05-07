defmodule MediaCentarr.Acquisition.Pursuits.State do
  @moduledoc """
  The pursuit lifecycle as a typed enum.

  Stored as strings in `acquisition_pursuits.state`; this module is the
  single source of truth for which strings exist and which bucket each
  belongs to. Mirrors the `Acquisition.GrabStatus` pattern.

  ## Buckets

  | atom               | string             | bucket             |
  |--------------------|--------------------|--------------------|
  | `:active`          | `"active"`         | `:in_flight`       |
  | `:needs_decision`  | `"needs_decision"` | `:in_flight`       |
  | `:satisfied`       | `"satisfied"`      | `:terminal_success`|
  | `:exhausted`       | `"exhausted"`      | `:terminal_failure`|
  | `:cancelled`       | `"cancelled"`      | `:terminal_failure`|

  Predicates accept either the string form (DB shape) or the atom form
  (typed code shape).
  """

  @in_flight_strings ~w(active needs_decision)
  @terminal_success_strings ~w(satisfied)
  @terminal_failure_strings ~w(exhausted cancelled)
  @terminal_strings @terminal_success_strings ++ @terminal_failure_strings
  @all_strings @in_flight_strings ++ @terminal_strings

  @type bucket :: :in_flight | :terminal_success | :terminal_failure
  @type t :: :active | :needs_decision | :satisfied | :exhausted | :cancelled

  @spec all() :: [String.t()]
  def all, do: @all_strings

  @spec in_flight() :: [String.t()]
  def in_flight, do: @in_flight_strings

  @spec terminal() :: [String.t()]
  def terminal, do: @terminal_strings

  @spec in_flight?(String.t() | atom()) :: boolean()
  def in_flight?(state), do: normalize(state) in @in_flight_strings

  @spec terminal?(String.t() | atom()) :: boolean()
  def terminal?(state), do: normalize(state) in @terminal_strings

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
