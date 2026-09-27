defmodule MediaCentaur.Social do
  use Boundary,
    deps: [MediaCentaur.ErrorReports, MediaCentaur.Nostr],
    exports: [
      Connections,
      Events,
      Events.FriendAdded,
      Events.FriendChanged,
      Events.FriendRemoved,
      Events.IdentityChanged,
      Events.ProfileUpdated,
      Events.RelayAdded,
      Events.RelayRemoved,
      Friend,
      Identity,
      Person,
      Profile,
      Profile.Translation,
      Relay
    ]

  @moduledoc """
  Bounded context for the friend network's configuration: this install's
  identity (`Social.Identity`), the relay list (`Social.Relay`), the
  live connections keyed by it (`Social.Connections`) and the roster of
  followed keys under the reader's names for them (`Social.Friend`),
  and each key's published profile (`Social.Profile`), saved by the
  reader for their own key and ingested for a friend's.
  `people/0` reads the identity and the roster as `Social.Person`, the
  one read model every surface draws a person from (ADR-074).

  Broadcasts typed events on `social:updates` (subscribe through
  `subscribe/0`) and re-broadcasts every relay connection's messages on
  `social:connections` (`subscribe_connections/0`).
  """

  import Ecto.Query

  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Events
  alias MediaCentaur.Social.Friend
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.Social.Profile
  alias MediaCentaur.Social.Profile.Translation, as: ProfileTranslation
  alias MediaCentaur.Social.Relay
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to friends events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.social_updates())

  @doc "Subscribe the caller to relay connection messages."
  @spec subscribe_connections() :: :ok | {:error, term()}
  def subscribe_connections, do: Topics.subscribe(Topics.social_connections())

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
  Adds a friend by npub or 64-hex key, optionally under the reader's own
  name for them, the override that masks the name they publish
  (UIDR-047); nil or blank is a friend without one. Idempotent on the
  key: re-adding one already on the roster changes nothing, as adding a
  relay you already have does; the name is changed with
  `set_name_override/2`.
  """
  @spec add_friend(String.t(), String.t() | nil) ::
          {:ok, Friend.t()} | {:error, :invalid_pubkey | :own_key | Ecto.Changeset.t()}
  def add_friend(key, name \\ nil) when is_binary(key) and (is_binary(name) or is_nil(name)) do
    with {:ok, pubkey} <- Keys.parse_pubkey(String.trim(key)),
         :ok <- not_own_key(pubkey) do
      case Repo.get_by(Friend, pubkey: pubkey) do
        %Friend{} = existing -> {:ok, existing}
        nil -> insert_friend(pubkey, name)
      end
    end
  end

  @doc """
  Sets the reader's optional name for a friend; nil or blank clears it,
  and the published name, else Unnamed, stands in. Broadcasts
  `FriendChanged` when it changed; the same name again is silent.
  """
  @spec set_name_override(String.t(), String.t() | nil) ::
          {:ok, Friend.t()} | {:error, :not_a_friend}
  def set_name_override(pubkey, name) when is_binary(pubkey) and (is_binary(name) or is_nil(name)) do
    with {:ok, friend} <- known_friend(pubkey) do
      apply_change(friend, %{name_override: name})
    end
  end

  @doc "Removes a friend by public key. Absent is a no-op, and broadcasts nothing."
  @spec remove_friend(String.t()) :: :ok
  def remove_friend(pubkey) when is_binary(pubkey) do
    case Repo.get_by(Friend, pubkey: String.downcase(pubkey)) do
      nil ->
        :ok

      friend ->
        Repo.delete!(friend)
        delete_profile(friend.pubkey)
        Events.broadcast(%Events.FriendRemoved{pubkey: friend.pubkey})
        :ok
    end
  end

  @doc "The roster, oldest first."
  @spec list_friends() :: [Friend.t()]
  def list_friends, do: Repo.all(from(friend in Friend, order_by: [friend.inserted_at, friend.pubkey]))

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

  @doc "Every followed pubkey — the authors the activities feed subscribes to."
  @spec friend_pubkeys() :: [String.t()]
  def friend_pubkeys,
    do: Repo.all(from(friend in Friend, select: friend.pubkey, order_by: friend.pubkey))

  @doc "Whether a public key is this identity's or on the roster: the keys whose events a reader keeps. Hex in any case."
  @spec known_key?(String.t()) :: boolean()
  def known_key?(pubkey) when is_binary(pubkey) do
    pubkey = String.downcase(pubkey)
    pubkey == Identity.pubkey() or friend_by_pubkey(pubkey) != nil
  end

  @doc """
  Every person this reader knows, by public key (ADR-074): the identity's
  own when one exists, and every roster member, each as a `Person` with
  the name their `Profile` published, when one is stored. The one place
  a roster row and a profile become what the reader sees.
  """
  @spec people() :: %{optional(String.t()) => Person.t()}
  def people do
    names = Map.new(Repo.all(Profile), &{&1.pubkey, &1.name})
    friends = Map.new(list_friends(), &{&1.pubkey, person_for(&1, names)})

    case Identity.pubkey() do
      nil -> friends
      me -> Map.put(friends, me, own_person_for(me, Map.get(names, me)))
    end
  end

  @doc """
  The reader as a person, with or without an identity: the review modal
  previews as the reader before a key exists.
  """
  @spec own_person() :: Person.t()
  def own_person do
    case own_profile() do
      nil -> own_person_for(Identity.pubkey(), nil)
      %Profile{pubkey: pubkey, name: name} -> own_person_for(pubkey, name)
    end
  end

  @doc "The npub, elided in the middle: enough to compare against what a friend told you."
  @spec short_npub(String.t()) :: String.t()
  def short_npub(pubkey) when is_binary(pubkey) do
    npub = to_npub(pubkey)
    String.slice(npub, 0, 9) <> "…" <> String.slice(npub, -4..-1//1)
  end

  # --- profiles ----------------------------------------------------------------

  @doc """
  Saves the reader's own profile (ADR-073, UIDR-047): mints the identity
  when none exists, stamps the event strictly after the stored one,
  signs, stores, publishes to every connected relay and broadcasts
  `ProfileUpdated`. The name is required and capped at
  `Profile.Translation.max_name_length/0` characters, checked before
  anything is minted: the form refuses to save without one.
  """
  @spec save_profile(String.t()) :: {:ok, Profile.t()} | {:error, :name_required | :name_too_long}
  def save_profile(name) when is_binary(name) do
    with {:ok, name} <- present_name(name),
         :ok <- within_name_cap(name) do
      secret = Identity.ensure()
      me = Identity.pubkey()
      stored = Repo.get_by(Profile, pubkey: me)
      created_at = Event.stamp_after(stored && stored.created_at, System.os_time(:second))
      event = name |> ProfileTranslation.to_event(me, created_at) |> Event.sign(secret)
      {:ok, attrs} = ProfileTranslation.from_event(event)
      profile = upsert_profile(stored, attrs)
      Connections.publish(event)
      Events.broadcast(%Events.ProfileUpdated{pubkey: me})
      {:ok, profile}
    end
  end

  @doc """
  Stores a verified profile event from a known key (the identity or the
  roster): newer wins, a tie or an older one is `:ignored`, anything
  malformed is dropped whole. Broadcasts `ProfileUpdated` when stored.
  """
  @spec ingest_profile(Event.t()) ::
          {:ok, Profile.t()}
          | :ignored
          | {:error,
             :unknown_author
             | :wrong_kind
             | :bad_content
             | :unsupported_version
             | :bad_id
             | :bad_signature
             | :malformed}
  def ingest_profile(%Event{} = event) do
    with :ok <- Event.verify(event),
         :ok <- known_key_or_error(event.pubkey),
         {:ok, attrs} <- ProfileTranslation.from_event(event) do
      case Repo.get_by(Profile, pubkey: attrs.pubkey) do
        %Profile{created_at: held} when held >= attrs.created_at ->
          :ignored

        stored ->
          profile = upsert_profile(stored, attrs)
          Events.broadcast(%Events.ProfileUpdated{pubkey: profile.pubkey})
          {:ok, profile}
      end
    end
  end

  @doc "The reader's own profile, or nil before one was saved."
  @spec own_profile() :: Profile.t() | nil
  def own_profile do
    case Identity.pubkey() do
      nil -> nil
      me -> Repo.get_by(Profile, pubkey: me)
    end
  end

  @doc "The own profile as a wire event, for the own-events diff; `[]` before one exists."
  @spec own_events() :: [Event.t()]
  def own_events do
    case own_profile() do
      nil ->
        []

      %Profile{raw_event: raw} ->
        case Event.from_map(raw) do
          {:ok, event} -> [event]
          {:error, _reason} -> []
        end
    end
  end

  @doc "What an own event with this id is, for the words a relay's refusal takes: `:profile`, or nil."
  @spec own_event_kind(String.t()) :: :profile | nil
  def own_event_kind(event_id) when is_binary(event_id) do
    case own_profile() do
      %Profile{raw_event: %{"id" => ^event_id}} -> :profile
      _other -> nil
    end
  end

  @doc """
  Replaces the identity with another secret key and forgets the old
  key's own profile row, which no longer names anyone the reader is.
  The new key's profile arrives from the relays if one was ever
  published.
  """
  @spec import_identity(String.t()) :: :ok | {:error, :invalid_secret}
  def import_identity(nsec) when is_binary(nsec) do
    old = Identity.pubkey()

    with :ok <- Identity.import_nsec(nsec) do
      # Re-importing the same key changes nothing and keeps its profile.
      if old && old != Identity.pubkey(), do: delete_profile(old)
      :ok
    end
  end

  defp upsert_profile(nil, attrs), do: Repo.insert!(Profile.changeset(attrs))
  defp upsert_profile(%Profile{} = stored, attrs), do: Repo.update!(Profile.changeset(stored, attrs))

  defp delete_profile(pubkey),
    do: Repo.delete_all(from(profile in Profile, where: profile.pubkey == ^pubkey))

  defp known_key_or_error(pubkey), do: if(known_key?(pubkey), do: :ok, else: {:error, :unknown_author})

  defp own_person_for(pubkey, published_name) do
    %Person{
      pubkey: pubkey,
      own?: true,
      published_name: published_name,
      short_npub: pubkey && short_npub(pubkey)
    }
  end

  defp person_for(%Friend{} = friend, names) do
    %Person{
      pubkey: friend.pubkey,
      name_override: friend.name_override,
      published_name: Map.get(names, friend.pubkey),
      own?: false,
      short_npub: short_npub(friend.pubkey),
      added_on: DateTime.to_date(friend.inserted_at)
    }
  end

  defp not_own_key(pubkey), do: if(Identity.pubkey() == pubkey, do: {:error, :own_key}, else: :ok)

  defp present_name(name) do
    case String.trim(name) do
      "" -> {:error, :name_required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp within_name_cap(name) do
    if String.length(name) <= ProfileTranslation.max_name_length(),
      do: :ok,
      else: {:error, :name_too_long}
  end

  defp known_friend(pubkey) do
    case friend_by_pubkey(pubkey) do
      nil -> {:error, :not_a_friend}
      friend -> {:ok, friend}
    end
  end

  defp insert_friend(pubkey, name) do
    case Repo.insert(Friend.changeset(%{pubkey: pubkey, name_override: name})) do
      {:ok, friend} ->
        Events.broadcast(%Events.FriendAdded{pubkey: friend.pubkey})
        {:ok, friend}

      {:error, changeset} ->
        # A concurrent insert of the same key is the re-add case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Friend, pubkey: pubkey)},
          else: {:error, changeset}
    end
  end

  # No change is no broadcast. The changeset cannot fail here: the name
  # is optional and the key is unchanged, so a failure is a bug.
  defp apply_change(%Friend{} = existing, attrs) do
    changeset = Friend.changeset(existing, attrs)

    if changeset.changes == %{} do
      {:ok, existing}
    else
      friend = Repo.update!(changeset)
      Events.broadcast(%Events.FriendChanged{pubkey: friend.pubkey})
      {:ok, friend}
    end
  end

  defp insert_relay(url, normalized) do
    case Repo.insert(Relay.changeset(%{url: url})) do
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
