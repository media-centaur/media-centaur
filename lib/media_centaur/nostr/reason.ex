defmodule MediaCentaur.Nostr.Reason do
  @moduledoc """
  Plain-language cause for a lost or refused relay connection — the one
  place a transport term becomes words a user reads.

  A `Nostr.Connection` reports why a socket went away as whatever Mint
  handed it (`%Mint.TransportError{reason: :econnrefused}`) or one of its
  own atoms (`:closed_by_relay`, `:unresponsive`). Relays speak for
  themselves in `OK`, `CLOSED` and `AUTH` verdicts, so a string passes
  through untouched. Everything else maps to a fixed vocabulary; a term
  nothing here knows becomes "connection failed" rather than an
  inspected struct.
  """

  @doc "The user-facing text for a connection reason."
  @spec describe(term()) :: String.t()
  def describe(reason) when is_binary(reason), do: reason
  def describe(:closed_by_relay), do: "closed by relay"
  def describe(:unresponsive), do: "unresponsive"
  def describe(%Mint.TransportError{reason: reason}), do: transport(reason)
  def describe(%Mint.WebSocketError{}), do: "not a WebSocket relay"
  def describe(%Mint.HTTPError{}), do: "not a WebSocket relay"
  def describe(_other), do: "connection failed"

  defp transport(:econnrefused), do: "connection refused"
  defp transport(:nxdomain), do: "host not found"
  defp transport(:timeout), do: "timed out"
  defp transport(:closed), do: "closed by relay"
  defp transport({:tls_alert, _alert}), do: "TLS failed"
  defp transport(:ehostunreach), do: "host unreachable"
  defp transport(:enetunreach), do: "network unreachable"
  defp transport(_other), do: "connection failed"
end
