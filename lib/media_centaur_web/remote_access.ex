defmodule MediaCentaurWeb.RemoteAccess do
  @moduledoc """
  The gate's one policy: a request is admitted by where it comes from.

  From the host itself (a loopback address, `Settings.Config.BindAddress.loopback?/1`)
  it is the **host player**, `:host`, whatever its session holds. From any
  other address it is admitted only when its browser session holds the id
  of a paired player (`"player_id"`, written by `PairingController`
  beside ADR-078's `"profile_id"`), read back from `Players` on every
  judgement so a removed player is cut off at once. Anything else is
  `:unpaired`.

  Two enforcement points call it: `Plugs.RemoteAccess` for HTTP requests
  and `Live.PlayerAware` for the LiveView socket, which bypasses plugs.
  Neither judges anything itself.
  """

  alias MediaCentaur.Players
  alias MediaCentaur.Players.Player
  alias MediaCentaur.Settings.Config.BindAddress

  @typedoc "Who a request is from: the host itself, or a paired player."
  @type player :: :host | Player.t()

  @doc "The verdict for a request from `address` whose session holds `player_id` (nil for none)."
  @spec admit(:inet.ip_address(), term()) :: {:ok, player()} | :unpaired
  def admit(address, player_id) do
    cond do
      BindAddress.loopback?(address) -> {:ok, :host}
      player = Players.get(player_id) -> {:ok, player}
      true -> :unpaired
    end
  end
end
