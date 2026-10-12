defmodule MediaCentaur.Social.Events do
  @moduledoc """
  Typed events on `social:updates`, plus the connection re-broadcast on
  `social:connections`. The only `Topics.publish` in the Social
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

  defmodule RelayChanged do
    @moduledoc "A relay's follow rule changed."
    @enforce_keys [:url]
    defstruct [:url]
    @type t :: %__MODULE__{url: String.t()}
  end

  defmodule MembersChanged do
    @moduledoc "A members-rule relay's observed members changed: a key was seen on it for the first time, or a read ended without one."
    @enforce_keys [:url]
    defstruct [:url]
    @type t :: %__MODULE__{url: String.t()}
  end

  defmodule FriendAdded do
    @moduledoc "A public key became a friend: added by hand, or a member promoted."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  defmodule ContactChanged do
    @moduledoc "The reader's choices for a contact changed: the name override, the avatar switch, the hue override or hidden."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  defmodule FriendRemoved do
    @moduledoc "A public key stopped being a friend; it may still be followed as a member."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  defmodule ProfileUpdated do
    @moduledoc "A known key's profile was stored: ingested from a relay, or the reader's own saved."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  @type t ::
          IdentityChanged.t()
          | RelayAdded.t()
          | RelayRemoved.t()
          | RelayChanged.t()
          | MembersChanged.t()
          | FriendAdded.t()
          | ContactChanged.t()
          | FriendRemoved.t()
          | ProfileUpdated.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%IdentityChanged{} = event), do: publish({:identity_changed, event})
  def broadcast(%RelayAdded{} = event), do: publish({:relay_added, event})
  def broadcast(%RelayRemoved{} = event), do: publish({:relay_removed, event})
  def broadcast(%RelayChanged{} = event), do: publish({:relay_changed, event})
  def broadcast(%MembersChanged{} = event), do: publish({:members_changed, event})
  def broadcast(%FriendAdded{} = event), do: publish({:friend_added, event})
  def broadcast(%ContactChanged{} = event), do: publish({:contact_changed, event})
  def broadcast(%FriendRemoved{} = event), do: publish({:friend_removed, event})
  def broadcast(%ProfileUpdated{} = event), do: publish({:profile_updated, event})

  @doc """
  Re-broadcasts one relay connection's owner message on
  `social:connections`. Not a typed struct: the payload is
  `Nostr.Connection`'s own message vocabulary, relayed verbatim so a
  subscriber reads exactly what the connection reported.
  """
  @spec broadcast_connection(String.t(), term()) :: :ok | {:error, term()}
  def broadcast_connection(url, message) when is_binary(url) do
    Topics.publish(Topics.social_connections(), {:relay_connection, url, message})
  end

  defp publish(message), do: Topics.publish(Topics.social_updates(), message)
end
