defmodule MediaCentaurWeb.SettingsLive.Reach do
  @moduledoc """
  How another device reaches this install: the pure judgement, from the
  endpoint's bound address and port and the host's LAN addresses
  (`Platform.LanAddresses`), that the Players and Local API sections draw.
  """

  alias MediaCentaur.Settings.Config.BindAddress

  @typedoc "Not at all while bound to loopback, or at these URLs."
  @type t :: :loopback | {:addresses, [String.t()]}

  @doc """
  From the endpoint's `http` config (`ip`, `port`) and the host's LAN
  addresses: `:loopback` when the install listens on the host alone;
  otherwise the URLs a device can use — every LAN address when bound to
  every interface, or the one address bound.
  """
  @spec reach(keyword(), [:inet.ip_address()]) :: t()
  def reach(http, lan_addresses) do
    ip = Keyword.fetch!(http, :ip)
    port = Keyword.fetch!(http, :port)

    cond do
      BindAddress.loopback?(ip) -> :loopback
      any_interface?(ip) -> {:addresses, Enum.map(lan_addresses, &reach_url(&1, port))}
      true -> {:addresses, [reach_url(ip, port)]}
    end
  end

  @doc "The URLs of a `reach/2` answer; none on loopback."
  @spec addresses(t()) :: [String.t()]
  def addresses({:addresses, urls}), do: urls
  def addresses(:loopback), do: []

  defp any_interface?({0, 0, 0, 0}), do: true
  defp any_interface?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp any_interface?(_ip), do: false

  defp reach_url(ip, port), do: "http://#{:inet.ntoa(ip)}:#{port}"
end
