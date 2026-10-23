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

  Three enforcement points carry it and act on a player's removal:
  `Plugs.RemoteAccess` for HTTP requests (judged on every request),
  `Live.PlayerAware` for the LiveView socket, which bypasses plugs, and
  `PlayerSocket` for the player channel. None judges anything itself.
  """

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
      player = Players.get(player_id) -> {:ok, player.id}
      true -> :unpaired
    end
  end
end
