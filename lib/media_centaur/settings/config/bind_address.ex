defmodule MediaCentaur.Settings.Config.BindAddress do
  @moduledoc """
  The `bind` bootstrap key: the address the HTTP endpoint listens on.

  Loopback by default, so an install is reachable only from its own
  host. The owner opens it to the LAN (`"0.0.0.0"`, or one interface's
  address) so paired players can reach it; the gate
  (`MediaCentaurWeb.RemoteAccess`) then admits a non-loopback request
  only when its browser session holds a paired player.

  Read by `config/runtime.exs` for the endpoint and by `Settings.Config`
  for `Config.get(:bind)`, both from the same TOML, through `parse/1`.
  `loopback?/1` is the one judgement of "is this address the host
  itself" the gate and the Players section share.
  """

  @loopback_default {127, 0, 0, 1}

  @typedoc "An `:inet.ip_address/0`."
  @type address :: :inet.ip_address()

  @doc """
  The address for a TOML `bind` value: `nil` is loopback; a string must
  be an IPv4 or IPv6 literal. Anything else is an error whose message
  names the key and the value.
  """
  @spec parse(term()) :: {:ok, address()} | {:error, String.t()}
  def parse(nil), do: {:ok, @loopback_default}

  def parse(value) when is_binary(value) do
    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, address} -> {:ok, address}
      {:error, :einval} -> {:error, invalid(value)}
    end
  end

  def parse(value), do: {:error, invalid(value)}

  @doc "`parse/1`, raising `ArgumentError` on an invalid value."
  @spec parse!(term()) :: address()
  def parse!(value) do
    case parse(value) do
      {:ok, address} -> address
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc "Whether the address is the host itself: IPv4 `127/8`, IPv6 `::1`, or IPv4 loopback mapped into IPv6."
  @spec loopback?(address()) :: boolean()
  def loopback?({127, _, _, _}), do: true
  def loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def loopback?({0, 0, 0, 0, 0, 65_535, high, _low}) when div(high, 256) == 127, do: true
  def loopback?(_address), do: false

  defp invalid(value) do
    "TOML key `bind` must be an IPv4 or IPv6 address such as \"0.0.0.0\"; got #{inspect(value)}"
  end
end
