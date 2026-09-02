defmodule MediaCentaur.Friends.Events do
  @moduledoc """
  Typed events on `friends:updates`, plus the connection re-broadcast on
  `friends:connections`. The only `Topics.publish` in the Friends
  context (event chokepoint).
  """

  alias MediaCentaur.Topics

  defmodule IdentityChanged do
    @moduledoc "The install's identity was generated or replaced."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  defmodule RelayAdded do
    @moduledoc "A relay URL joined the configured list."
    @enforce_keys [:url]
    defstruct [:url]
    @type t :: %__MODULE__{url: String.t()}
  end

  defmodule RelayRemoved do
    @moduledoc "A relay URL left the configured list."
    @enforce_keys [:url]
    defstruct [:url]
    @type t :: %__MODULE__{url: String.t()}
  end

  defmodule FriendAdded do
    @moduledoc "A public key joined the roster, or its nickname changed."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  defmodule FriendRemoved do
    @moduledoc "A public key left the roster."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  @type t ::
          IdentityChanged.t()
          | RelayAdded.t()
          | RelayRemoved.t()
          | FriendAdded.t()
          | FriendRemoved.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%IdentityChanged{} = event), do: publish({:identity_changed, event})
  def broadcast(%RelayAdded{} = event), do: publish({:relay_added, event})
  def broadcast(%RelayRemoved{} = event), do: publish({:relay_removed, event})
  def broadcast(%FriendAdded{} = event), do: publish({:friend_added, event})
  def broadcast(%FriendRemoved{} = event), do: publish({:friend_removed, event})

  @doc """
  Re-broadcasts one relay connection's owner message on
  `friends:connections`. Not a typed struct: the payload is
  `Nostr.Connection`'s own message vocabulary, relayed verbatim so a
  subscriber reads exactly what the connection reported.
  """
  @spec broadcast_connection(String.t(), term()) :: :ok | {:error, term()}
  def broadcast_connection(url, message) when is_binary(url) do
    Topics.publish(Topics.friends_connections(), {:relay_connection, url, message})
  end

  defp publish(message), do: Topics.publish(Topics.friends_updates(), message)
end
