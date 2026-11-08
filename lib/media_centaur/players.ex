defmodule MediaCentaur.Players do
  use Boundary,
    deps: [],
    exports: [
      Events,
      Events.PairingChanged,
      Events.PlayerChanged,
      Events.PlayerPaired,
      Events.PlayerRemoved,
      Pairing,
      Pairing.Code,
      Player,
      Player.Device
    ]

  @moduledoc """
  Bounded context for the players paired with this install: the devices
  on the LAN, each a `Player` row, that the gate (`MediaCentaurWeb.RemoteAccess`)
  admits because their browser session holds the row's id. Pairing is
  how a device becomes one: the owner starts it here, which mints the one
  open `Pairing.Code`; the device offers the digits with its name on the
  pairing page, and `pair/2` turns a match into a row. The host itself is
  not a row — it is admitted by address.

  A player's row also holds what the host learns of the device: its name
  is the owner's to change (`rename/2`); the device's declaration and
  when and from where its channel last opened or closed are recorded by
  the channel (`record_connect/2`, `record_disconnect/1`), the browser's
  user agent by the LiveView socket (`record_user_agent/2`). Each change
  broadcasts `PlayerChanged`. Whether a player is connected now is
  Playback's (`Playback.connected_players/0`).

  Knows nothing about which player a request is from; that is the web
  layer's (`MediaCentaurWeb.RemoteAccess`, `Live.PlayerAware`), the same
  split as `Profiles` and `Live.ProfileAware`. Broadcasts typed events on
  `players:updates` (`subscribe/0`).
  """

  import Ecto.Query

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Players.Events
  alias MediaCentaur.Players.Pairing
  alias MediaCentaur.Players.Player
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to player and pairing events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.players_updates())

  @doc "Every paired player, oldest first."
  @spec list() :: [Player.t()]
  def list, do: Repo.all(from player in Player, order_by: [asc: player.inserted_at, asc: player.id])

  @doc "A player by id; nil for an unknown or malformed id."
  @spec get(term()) :: Player.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Player, uuid)
      :error -> nil
    end
  end

  def get(_not_a_string), do: nil

  @doc "Opens pairing: mints the one code, replacing any open one. Broadcasts `PairingChanged`."
  @spec start_pairing() :: Pairing.Code.t()
  def start_pairing do
    code = Pairing.start()
    Events.broadcast(%Events.PairingChanged{code: code})
    code
  end

  @doc "The open pairing code, or nil."
  @spec pairing() :: Pairing.Code.t() | nil
  def pairing, do: Pairing.current()

  @doc "Closes the open pairing code, if any. Broadcasts `PairingChanged` when one was open."
  @spec cancel_pairing() :: :ok
  def cancel_pairing do
    if Pairing.cancel(), do: Events.broadcast(%Events.PairingChanged{code: nil})
    :ok
  end

  @doc """
  A device offers `code` with its `name`. A match under
  `DisplayName.check/1` adds the player, consumes the code and broadcasts
  `PlayerPaired` then `PairingChanged` (closed). A bad name leaves the
  code open. A miss spends an attempt; the last miss closes the code and
  broadcasts the closing.
  """
  @spec pair(String.t(), String.t()) ::
          {:ok, Player.t()} | {:error, :invalid_code | :name_required | :name_too_long}
  def pair(code, name) when is_binary(code) and is_binary(name) do
    with {:ok, name} <- DisplayName.check(name),
         :ok <- redeem(code) do
      {:ok, player} = %Player{} |> Player.changeset(%{name: name}) |> Repo.insert()
      Events.broadcast(%Events.PlayerPaired{player: player})
      Events.broadcast(%Events.PairingChanged{code: nil})
      {:ok, player}
    end
  end

  defp redeem(code) do
    case Pairing.redeem(code) do
      :ok ->
        :ok

      {:error, :invalid_code, :closed} ->
        Events.broadcast(%Events.PairingChanged{code: nil})
        {:error, :invalid_code}

      {:error, :invalid_code, :open} ->
        {:error, :invalid_code}
    end
  end

  @doc "Renames under `DisplayName.check/1`. Broadcasts `PlayerChanged`."
  @spec rename(Player.t(), String.t()) :: {:ok, Player.t()} | {:error, :name_required | :name_too_long}
  def rename(%Player{} = player, name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name) do
      player |> Player.changeset(%{name: name}) |> update_and_broadcast()
    end
  end

  @doc """
  The player's channel opened from `address`, carrying the device's
  declaration (`Player.Device.from_declaration/1`'s input, or nil for
  none: the device held stays). Stamps `last_seen_at`. A removed player
  records nothing. Broadcasts `PlayerChanged`.
  """
  @spec record_connect(Ecto.UUID.t(), %{address: String.t(), device: map() | nil}) :: :ok
  def record_connect(player_id, %{address: address, device: declaration}) do
    device = if declaration, do: Player.Device.from_declaration(declaration)
    record_seen(player_id, %{last_address: address, device: device})
  end

  @doc "The player's channel closed: stamps `last_seen_at`. A removed player records nothing. Broadcasts `PlayerChanged`."
  @spec record_disconnect(Ecto.UUID.t()) :: :ok
  def record_disconnect(player_id), do: record_seen(player_id, %{})

  defp record_seen(player_id, attrs) do
    with %Player{} = player <- get(player_id) do
      {:ok, _player} = player |> Player.seen_changeset(attrs) |> update_and_broadcast()
    end

    :ok
  end

  @doc """
  The user agent of the browser showing the player's pages. Written, and
  `PlayerChanged` broadcast, only when it differs from the one held; a
  removed player records nothing.
  """
  @spec record_user_agent(Ecto.UUID.t(), String.t()) :: :ok
  def record_user_agent(player_id, user_agent) when is_binary(user_agent) do
    {changed, _rows} =
      Repo.update_all(
        from(player in Player,
          where: player.id == ^player_id,
          where: is_nil(player.user_agent) or player.user_agent != ^user_agent
        ),
        set: [user_agent: user_agent, updated_at: DateTime.utc_now()]
      )

    if changed == 1, do: Events.broadcast(%Events.PlayerChanged{player: get(player_id)})
    :ok
  end

  defp update_and_broadcast(changeset) do
    with {:ok, player} <- Repo.update(changeset) do
      Events.broadcast(%Events.PlayerChanged{player: player})
      {:ok, player}
    end
  end

  @doc "Removes a player: its open page and channel close now, its next HTTP request is unpaired. Already removed answers `:ok` and broadcasts nothing. Broadcasts `PlayerRemoved`."
  @spec remove(Player.t()) :: :ok
  def remove(%Player{} = player) do
    case Repo.delete(player, stale_error_field: :id) do
      {:ok, _deleted} ->
        Events.broadcast(%Events.PlayerRemoved{id: player.id})
        :ok

      {:error, _stale} ->
        :ok
    end
  end
end
