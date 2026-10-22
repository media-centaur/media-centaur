defmodule MediaCentaurWeb.MediaToken do
  @moduledoc """
  The capability a remote player presents for one media file: a
  `Phoenix.Token` signed by this endpoint over `{player_id, presence_id}`,
  good for `max_age/0`. The host mints one into each media URL it composes
  for a player's viewing (`Playback.Transport.Remote`, through the
  locator the player channel captured at connect); `Plugs.MediaServer`
  admits a `/media/*` request by it alone (ADR-079, the owner's decision
  of 2026-10-22 in `campaigns/remote-players.md`).

  A token names one file for one player and expires; it is never a
  session. The device's identity stays in its session cookie.
  """

  alias MediaCentaurWeb.Endpoint

  @salt "media capability"
  @max_age_seconds 12 * 60 * 60

  @doc "How long a token admits, in seconds."
  @spec max_age() :: pos_integer()
  def max_age, do: @max_age_seconds

  @doc "A token admitting `player_id` to the file of `presence_id`."
  @spec sign(String.t(), String.t()) :: String.t()
  def sign(player_id, presence_id) when is_binary(player_id) and is_binary(presence_id) do
    Phoenix.Token.sign(Endpoint, @salt, {player_id, presence_id})
  end

  @doc "The `{player_id, presence_id}` a token admits, or why not."
  @spec verify(term()) :: {:ok, {String.t(), String.t()}} | {:error, :invalid | :expired | :missing}
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(Endpoint, @salt, token, max_age: @max_age_seconds) do
      {:ok, {player_id, presence_id}} when is_binary(player_id) and is_binary(presence_id) ->
        {:ok, {player_id, presence_id}}

      {:ok, _other_shape} ->
        {:error, :invalid}

      {:error, reason} when reason in [:invalid, :expired] ->
        {:error, reason}
    end
  end

  def verify(_not_a_token), do: {:error, :missing}
end
