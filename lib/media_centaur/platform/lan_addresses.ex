defmodule MediaCentaur.Platform.LanAddresses do
  @moduledoc """
  The host's IPv4 addresses on the local network: every address of an
  interface that is up and not loopback, as `:inet.getifaddrs/0` reports
  them. Settings → Players shows them beside the pairing code, so the
  owner can type the host's address into a TV. OS introspection, so it
  lives under `Platform`.
  """

  @doc "The host's non-loopback IPv4 addresses, in interface order."
  @spec ipv4() :: [:inet.ip4_address()]
  def ipv4 do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        for {_name, options} <- interfaces,
            up_and_not_loopback?(Keyword.get_values(options, :flags)),
            {:addr, {_a, _b, _c, _d} = address} <- options,
            do: address

      {:error, _reason} ->
        []
    end
  end

  defp up_and_not_loopback?([flags]), do: :up in flags and :loopback not in flags
  defp up_and_not_loopback?(_flags), do: false
end
