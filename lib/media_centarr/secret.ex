defmodule MediaCentarr.Secret do
  @moduledoc """
  Wraps a sensitive string (API key, password) so it doesn't leak via
  `inspect/2`, crash dumps, or accidental string interpolation.

  ## Usage

  Wrap on ingest, expose at the boundary:

      secret = Secret.wrap(System.get_env("API_KEY"))
      headers = [{"x-api-key", Secret.expose(secret)}]

  Treat the wrapped value as opaque elsewhere. The struct intentionally
  does NOT implement `String.Chars`, so `"\#{secret}"` raises
  `Protocol.UndefinedError` instead of silently leaking.

  `inspect/2` redacts the value:

      iex> inspect(Secret.wrap("hunter2"))
      "#Secret<***>"

  This applies recursively — a Secret nested inside any map / list / struct
  is redacted in that container's inspect output too. That covers the
  GenServer crash-dump path, where the entire `socket.assigns` is logged.

  ## When to use

  Any value that, if pasted into a logs channel, would let an attacker
  use the underlying service: API keys, passwords, OAuth tokens, signed
  cookies. Not for non-sensitive identifiers (UUIDs, usernames, URLs).
  """

  @enforce_keys [:value]
  defstruct [:value]

  @opaque t :: %__MODULE__{value: String.t()}

  @doc """
  Wraps a string as a `Secret`. `nil` passes through unchanged so callers
  don't need to special-case unset config values. Re-wrapping a `Secret`
  is a no-op.
  """
  @spec wrap(String.t() | nil | t()) :: t() | nil
  def wrap(nil), do: nil
  def wrap(%__MODULE__{} = secret), do: secret
  def wrap(value) when is_binary(value), do: %__MODULE__{value: value}

  @doc """
  Returns the raw underlying string. Use only at the boundary where the
  raw value must be sent (HTTP header, request body, external API).
  """
  @spec expose(t() | nil) :: String.t() | nil
  def expose(nil), do: nil
  def expose(%__MODULE__{value: value}), do: value

  @doc """
  True when the wrapped value is a non-empty string. Use this in place of
  the common `value not in [nil, ""]` check, which doesn't compose with
  `Secret`.
  """
  @spec present?(t() | nil) :: boolean()
  def present?(nil), do: false
  def present?(%__MODULE__{value: ""}), do: false
  def present?(%__MODULE__{value: value}) when is_binary(value), do: true

  defimpl Inspect do
    def inspect(_secret, _opts), do: "#Secret<***>"
  end
end
