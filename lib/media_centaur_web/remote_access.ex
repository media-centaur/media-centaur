defmodule MediaCentaurWeb.RemoteAccess do
  @moduledoc """
  The gate's one policy: a request is admitted by where it comes from.

  From the host itself (a loopback address, `Settings.Config.BindAddress.loopback?/1`)
  it is the **host player**, `:host`, whatever its session holds. From any
  other address it is admitted only when its browser session holds the id
  of a paired player (`"player_id"`, written by `PairingController`
  beside ADR-078's `"profile_id"`), read back from `Players` on every
  judgement so a removed player is cut off at once — and only while the
  remote players feature is on (`MediaCentaur.Features`, ADR-081).
  Anything else is `:unpaired`.

  Three enforcement points carry it and act on a player's removal:
  `Plugs.RemoteAccess` for HTTP requests (judged on every request),
  `Live.PlayerAware` for the LiveView socket, which bypasses plugs, and
  `PlayerSocket` for the player channel. None judges anything itself.

  Loopback is trusted, so a loopback request must also name the host as
  only the host would (`host_allowed?/2`). A web page that rebinds its own
  domain to 127.0.0.1 reaches this address from the viewer's browser and
  arrives under that domain, and is refused. A reverse proxy on this
  computer must send a local `Host`, and it makes every client it serves
  a loopback address: the host player. Authentication is the proxy's.
  """

  alias MediaCentaur.Features
  alias MediaCentaur.Playback
  alias MediaCentaur.Players
  alias MediaCentaur.Settings.Config.BindAddress

  @doc """
  The verdict for a request from `address` whose session holds `player_id`
  (nil for none): the player it is on, as the id every viewing names
  (`Playback.player/0`), or `:unpaired`.
  """
  @spec admit(:inet.ip_address(), term()) :: {:ok, Playback.player()} | :unpaired
  def admit(address, player_id) do
    cond do
      BindAddress.loopback?(address) -> {:ok, :host}
      # Remote players off (ADR-081): nothing off the host is admitted,
      # paired or not; the device lands on the pairing page, which says so.
      not Features.enabled?(:players) -> :unpaired
      player = Players.get(player_id) -> {:ok, player.id}
      true -> :unpaired
    end
  end

  @doc """
  Whether a request from `address` under the `Host` name `host` may be
  judged at all: anything off the host may (its session admits it), and
  from loopback an IP literal, `localhost` and its subdomains, or this
  computer's own name.
  """
  @spec host_allowed?(:inet.ip_address(), String.t()) :: boolean()
  def host_allowed?(address, host) do
    not BindAddress.loopback?(address) or address_literal?(host) or local_name?(String.downcase(host))
  end

  defp address_literal?(host) do
    match?(
      {:ok, _address},
      host |> String.trim("[") |> String.trim("]") |> to_charlist() |> :inet.parse_address()
    )
  end

  defp local_name?("localhost"), do: true

  defp local_name?(host) do
    {:ok, hostname} = :inet.gethostname()
    name = hostname |> to_string() |> String.downcase()
    String.ends_with?(host, ".localhost") or host in [name, name <> ".local"]
  end
end
