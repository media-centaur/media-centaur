defmodule MediaCentaur.Social do
  use Boundary,
    deps: [MediaCentaur.Nostr],
    exports: [
      Connections,
      Events,
      Events.FriendAdded,
      Events.FriendRemoved,
      Events.IdentityChanged,
      Events.RelayAdded,
      Events.RelayRemoved,
      Friend,
      Identity,
      Relay
    ]

  @moduledoc """
  Bounded context for the friend network's configuration: this install's
  identity (`Social.Identity`), the relay list (`Social.Relay`), the
  live connections keyed by it (`Social.Connections`) and the roster of
  followed keys (`Social.Friend`).

  Broadcasts typed events on `social:updates` (subscribe through
  `subscribe/0`) and re-broadcasts every relay connection's messages on
  `social:connections` (`subscribe_connections/0`).
  """

  import Ecto.Query

  alias MediaCentaur.Social.Events
  alias MediaCentaur.Social.Friend
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Relay
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to friends events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.friends_updates())

  @doc "Subscribe the caller to relay connection messages."
  @spec subscribe_connections() :: :ok | {:error, term()}
  def subscribe_connections, do: Topics.subscribe(Topics.friends_connections())

  @doc "Adds a relay URL (idempotent on the normalized URL)."
  @spec add_relay(String.t()) :: {:ok, Relay.t()} | {:error, Ecto.Changeset.t()}
  def add_relay(url) when is_binary(url) do
    normalized = Relay.normalize(url)

    case Repo.get_by(Relay, url: normalized) do
      %Relay{} = existing -> {:ok, existing}
      nil -> insert_relay(url, normalized)
    end
  end

  @doc "Removes a relay by URL. Absent is a no-op — and broadcasts nothing."
  @spec remove_relay(String.t()) :: :ok
  def remove_relay(url) when is_binary(url) do
    case Repo.get_by(Relay, url: Relay.normalize(url)) do
      nil ->
        :ok

      relay ->
        Repo.delete!(relay)
        Events.broadcast(%Events.RelayRemoved{url: relay.url})
        :ok
    end
  end

  @doc "Every configured relay, in URL order."
  @spec list_relays() :: [Relay.t()]
  def list_relays, do: Repo.all(from(relay in Relay, order_by: relay.url))

  @doc """
  Advances a relay's sync cursor (`synced_until`, Unix seconds) — the
  newest event time seen from it. Never moves backwards; a URL with no
  row is a no-op (the relay was removed mid-sync).
  """
  @spec advance_synced_until(String.t(), non_neg_integer()) :: :ok
  def advance_synced_until(url, created_at) when is_binary(url) and is_integer(created_at) do
    Repo.update_all(
      from(relay in Relay,
        where: relay.url == ^url and (is_nil(relay.synced_until) or relay.synced_until < ^created_at)
      ),
      set: [synced_until: created_at]
    )

    :ok
  end

  @doc "A relay's sync cursor, or nil before its first event (or when the URL is unknown)."
  @spec synced_until(String.t()) :: non_neg_integer() | nil
  def synced_until(url) when is_binary(url) do
    Repo.one(from(relay in Relay, where: relay.url == ^url, select: relay.synced_until))
  end

  @doc """
  Adds a friend by npub or 64-hex key with a local nickname. Idempotent
  on the key: re-adding one already on the roster renames it.
  """
  @spec add_friend(String.t(), String.t()) ::
          {:ok, Friend.t()}
          | {:error, :invalid_pubkey | :nickname_required | :own_key | Ecto.Changeset.t()}
  def add_friend(key, nickname) when is_binary(key) and is_binary(nickname) do
    with {:ok, pubkey} <- Keys.parse_pubkey(String.trim(key)),
         :ok <- not_own_key(pubkey),
         :ok <- nickname_present(nickname) do
      upsert_friend(pubkey, String.trim(nickname))
    end
  end

  @doc "Removes a friend by public key. Absent is a no-op — and broadcasts nothing."
  @spec remove_friend(String.t()) :: :ok
  def remove_friend(pubkey) when is_binary(pubkey) do
    case Repo.get_by(Friend, pubkey: String.downcase(pubkey)) do
      nil ->
        :ok

      friend ->
        Repo.delete!(friend)
        Events.broadcast(%Events.FriendRemoved{pubkey: friend.pubkey})
        :ok
    end
  end

  @doc "The roster, by nickname."
  @spec list_friends() :: [Friend.t()]
  def list_friends, do: Repo.all(from(friend in Friend, order_by: friend.nickname))

  @doc "One friend by public key, or nil."
  @spec friend_by_pubkey(String.t()) :: Friend.t() | nil
  def friend_by_pubkey(pubkey) when is_binary(pubkey),
    do: Repo.get_by(Friend, pubkey: String.downcase(pubkey))

  @doc """
  The NIP-19 `npub` form of a public key. The context owns the key
  vocabulary; the web layer never reaches into `Nostr.Keys` itself.
  """
  @spec to_npub(String.t()) :: String.t()
  def to_npub(pubkey) when is_binary(pubkey), do: Keys.to_npub(pubkey)

  @doc "Every followed pubkey — the authors the recommendations feed subscribes to."
  @spec friend_pubkeys() :: [String.t()]
  def friend_pubkeys,
    do: Repo.all(from(friend in Friend, select: friend.pubkey, order_by: friend.pubkey))

  defp not_own_key(pubkey), do: if(Identity.pubkey() == pubkey, do: {:error, :own_key}, else: :ok)

  defp nickname_present(nickname),
    do: if(String.trim(nickname) == "", do: {:error, :nickname_required}, else: :ok)

  defp upsert_friend(pubkey, nickname) do
    case Repo.get_by(Friend, pubkey: pubkey) do
      %Friend{} = existing -> rename_friend(existing, nickname)
      nil -> insert_friend(pubkey, nickname)
    end
  end

  defp insert_friend(pubkey, nickname) do
    case Repo.insert(Friend.changeset(%{pubkey: pubkey, nickname: nickname})) do
      {:ok, friend} ->
        Events.broadcast(%Events.FriendAdded{pubkey: friend.pubkey})
        {:ok, friend}

      {:error, changeset} ->
        # A concurrent insert of the same key is the rename case, not a failure.
        if unique_violation?(changeset),
          do: rename_friend(Repo.get_by!(Friend, pubkey: pubkey), nickname),
          else: {:error, changeset}
    end
  end

  # An identical re-add is a no-op: same nickname, no broadcast.
  defp rename_friend(%Friend{nickname: nickname} = existing, nickname), do: {:ok, existing}

  defp rename_friend(existing, nickname) do
    with {:ok, friend} <- Repo.update(Friend.changeset(existing, %{nickname: nickname})) do
      Events.broadcast(%Events.FriendAdded{pubkey: friend.pubkey})
      {:ok, friend}
    end
  end

  defp insert_relay(url, normalized) do
    case Repo.insert(Relay.create_changeset(%{url: url})) do
      {:ok, relay} ->
        Events.broadcast(%Events.RelayAdded{url: relay.url})
        {:ok, relay}

      {:error, changeset} ->
        # A concurrent insert of the same URL is the idempotent case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Relay, url: normalized)},
          else: {:error, changeset}
    end
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, meta}} -> meta[:constraint] == :unique end)
  end
end
