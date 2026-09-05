defmodule MediaCentaur.Eventually do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The one deterministic stand-in for a settle sleep: polls a predicate to
  a deadline and fails with a message when it never holds (ADR-049 —
  tests drive async work to completion, they do not wait a fixed time
  and hope). Imported by `DataCase` and `ConnCase`.
  """
  import ExUnit.Assertions, only: [flunk: 1]

  @default_timeout_ms 2_000
  @default_interval_ms 20

  @doc """
  Calls `fun` every `:interval` ms until it returns a truthy value, which
  is returned, or `:timeout` ms elapse, which fails the test with
  `:message` (a string or a zero-arity function, evaluated at failure).
  """
  @spec eventually((-> term()), keyword()) :: term()
  def eventually(fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    interval = Keyword.get(opts, :interval, @default_interval_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(fun, deadline, interval, Keyword.get(opts, :message))
  end

  defp poll(fun, deadline, interval, message) do
    case fun.() do
      falsy when falsy in [nil, false] ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk(failure_message(message))
        else
          Process.sleep(interval)
          poll(fun, deadline, interval, message)
        end

      value ->
        value
    end
  end

  defp failure_message(nil), do: "eventually/2: condition never became true"
  defp failure_message(message) when is_function(message, 0), do: message.()
  defp failure_message(message), do: message
end
