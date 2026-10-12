defmodule MediaCentaur.Social do
  use Boundary,
    deps: [MediaCentaur.ErrorReports, MediaCentaur.Nostr],
    exports: [
      Connections,
      Contact,
      Events,
      Events.ContactChanged,
      Events.FriendAdded,
      Events.FriendRemoved,
      Events.IdentityChanged,
      Events.MembersChanged,
      Events.ProfileUpdated,
      Events.RelayAdded,
      Events.RelayChanged,
      Events.RelayRemoved,
      Identity,
      Person,
      Profile,
      Profile.Translation,
      Relay,
      RelayMember
    ]

  @moduledoc """
  Bounded context for the friend network's configuration: this install's
  identity (`Social.Identity`), the relay list (`Social.Relay`, each under
  the reader's follow rule), the live connections keyed by it
  (`Social.Connections`), the contacts — one row per key the reader has a
  view of, a friend when they added it by hand (`Social.Contact`), the
  members observed on a members-rule relay (`Social.RelayMember`) — and
  each key's published profile (`Social.Profile`), saved by the reader for
  their own key and ingested for a followed one. `people/0` reads the
  identity and every followed key as `Social.Person`, the one read model
  every surface draws a person from (ADR-074).

  Broadcasts typed events on `social:updates` (subscribe through
  `subscribe/0`) and re-broadcasts every relay connection's messages on
  `social:connections` (`subscribe_connections/0`).
  """

  import Ecto.Query

  alias MediaCentaur.Hue
  alias MediaCentaur.Social.AvatarStore
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Events
  alias MediaCentaur.Social.Contact
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.Social.Profile
  alias MediaCentaur.Social.Profile.Translation, as: ProfileTranslation
  alias MediaCentaur.Social.Relay
  alias MediaCentaur.Social.RelayMember
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @follow_rules Ecto.Enum.values(Relay, :follow)

  @doc "Subscribe the caller to the social events (`Social.Events`)."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.social_updates())

  @doc "Subscribe the caller to relay connection messages."
  @spec subscribe_connections() :: :ok | {:error, term()}
  def subscribe_connections, do: Topics.subscribe(Topics.social_connections())

  @doc """
  Adds a relay URL under a follow rule (`Relay.follow/0`), added unless
  given. Idempotent on the normalized URL: an existing relay keeps its rule
  (`set_follow/2` changes it).
  """
  @spec add_relay(String.t(), Relay.follow()) :: {:ok, Relay.t()} | {:error, Ecto.Changeset.t()}
  def add_relay(url, follow \\ :added) when is_binary(url) and follow in @follow_rules do
    normalized = Relay.normalize(url)

    case Repo.get_by(Relay, url: normalized) do
      %Relay{} = existing -> {:ok, existing}
      nil -> insert_relay(url, normalized, follow)
    end
  end

  @doc "One relay by URL (normalized first), or nil."
  @spec get_relay(String.t()) :: Relay.t() | nil
  def get_relay(url) when is_binary(url), do: Repo.get_by(Relay, url: Relay.normalize(url))

  @doc """
  Sets a relay's follow rule. Members → added forgets the relay's observed
  members: a key followed only through it stops being followed and its
  profile goes (`sweep_members/2` has the same rule). Broadcasts
  `RelayChanged` when it changed; the same rule again is silent.
  """
  @spec set_follow(String.t(), Relay.follow()) :: {:ok, Relay.t()} | {:error, :unknown_relay}
  def set_follow(url, follow) when is_binary(url) and follow in @follow_rules do
    case get_relay(url) do
      nil ->
        {:error, :unknown_relay}

      %Relay{follow: ^follow} = relay ->
        {:ok, relay}

      relay ->
        {:ok, {relay, pruned}} =
          Repo.transaction(fn ->
            relay = Repo.update!(Relay.changeset(relay, %{follow: follow}))
            pruned = if follow == :added, do: forget_members(relay), else: []
            {relay, pruned}
          end)

        delete_avatars(pruned)
        Events.broadcast(%Events.RelayChanged{url: relay.url})
        {:ok, relay}
    end
  end

  @doc """
  Removes a relay by URL. Its observed members go with it (the rows by
  cascade, the profiles and avatars by `prune_if_unfollowed/1`). Absent is
  a no-op — and broadcasts nothing.
  """
  @spec remove_relay(String.t()) :: :ok
  def remove_relay(url) when is_binary(url) do
    case get_relay(url) do
      nil ->
        :ok

      relay ->
        {:ok, pruned} =
          Repo.transaction(fn ->
            pubkeys =
              Repo.all(
                from(member in RelayMember, where: member.relay_id == ^relay.id, select: member.pubkey)
              )

            Repo.delete!(relay)
            prune_unfollowed(pubkeys)
          end)

        delete_avatars(pruned)
        Events.broadcast(%Events.RelayRemoved{url: relay.url})
        :ok
    end
  end

  @doc "Every configured relay, in URL order."
  @spec list_relays() :: [Relay.t()]
  def list_relays, do: Repo.all(from(relay in Relay, order_by: relay.url))

  @doc """
  Adds a friend by npub or 64-hex key, optionally under the reader's own
  name for them (UIDR-047); nil or blank is a friend without one. A key
  followed only through a relay is promoted, keeping the overrides the
  reader already set and taking the name when one is given. Idempotent on
  a friend: re-adding one changes nothing; the name is changed with
  `set_name_override/2`.
  """
  @spec add_friend(String.t(), String.t() | nil) ::
          {:ok, Contact.t()} | {:error, :invalid_pubkey | :own_key | Ecto.Changeset.t()}
  def add_friend(key, name \\ nil) when is_binary(key) and (is_binary(name) or is_nil(name)) do
    with {:ok, pubkey} <- Keys.parse_pubkey(String.trim(key)),
         :ok <- not_own_key(pubkey) do
      case Repo.get_by(Contact, pubkey: pubkey) do
        %Contact{added_at: nil} = member -> promote(member, name)
        %Contact{} = existing -> {:ok, existing}
        nil -> insert_contact(pubkey, name)
      end
    end
  end

  @doc """
  Sets the reader's optional name for a contact; nil or blank clears it,
  and the published name, else Unnamed, stands in. Broadcasts
  `ContactChanged` when it changed; the same name again is silent.
  """
  @spec set_name_override(String.t(), String.t() | nil) ::
          {:ok, Contact.t()} | {:error, :not_a_contact}
  def set_name_override(pubkey, name) when is_binary(pubkey) and (is_binary(name) or is_nil(name)) do
    with {:ok, contact} <- known_contact(pubkey) do
      apply_change(contact, %{name_override: name})
    end
  end

  @doc "Shows or hides a contact's avatar for this reader. Broadcasts `ContactChanged` when it flipped."
  @spec set_show_avatar(String.t(), boolean()) :: {:ok, Contact.t()} | {:error, :not_a_contact}
  def set_show_avatar(pubkey, show?) when is_binary(pubkey) and is_boolean(show?) do
    with {:ok, contact} <- known_contact(pubkey), do: apply_change(contact, %{show_avatar: show?})
  end

  @doc """
  Sets the reader's hue for a contact (UIDR-048), masking the one the
  contact published; nil clears it and the published hue, else the
  default, stands in. Broadcasts `ContactChanged` when it changed.
  """
  @spec set_hue_override(String.t(), Hue.t() | nil) ::
          {:ok, Contact.t()} | {:error, :not_a_contact | :invalid_hue}
  def set_hue_override(pubkey, hue) when is_binary(pubkey) do
    with :ok <- valid_hue(hue),
         {:ok, contact} <- known_contact(pubkey) do
      apply_change(contact, %{hue_override: hue})
    end
  end

  @doc "Hides or shows a person's activity for this reader. Broadcasts `ContactChanged` when it flipped."
  @spec set_hidden(String.t(), boolean()) :: {:ok, Contact.t()} | {:error, :not_a_contact}
  def set_hidden(pubkey, hidden?) when is_binary(pubkey) and is_boolean(hidden?) do
    with {:ok, contact} <- known_contact(pubkey), do: apply_change(contact, %{hidden: hidden?})
  end

  @doc """
  Removes a friend by public key: the added mark goes. The contact row
  stays — the reader's overrides and `hidden` wait for a return — and the
  profile and avatar go unless the key is still followed through a
  members-rule relay (`prune_if_unfollowed/1`, the one rule for every way
  a key stops being followed). Broadcasts `FriendRemoved`. A key that is
  not a friend is a no-op, and broadcasts nothing.
  """
  @spec remove_friend(String.t()) :: :ok
  def remove_friend(pubkey) when is_binary(pubkey) do
    case Repo.get_by(Contact, pubkey: String.downcase(pubkey)) do
      %Contact{added_at: added_at} = contact when added_at != nil ->
        {:ok, pruned} =
          Repo.transaction(fn ->
            Repo.update!(Contact.changeset(contact, %{added_at: nil}))
            prune_unfollowed([contact.pubkey])
          end)

        delete_avatars(pruned)
        Events.broadcast(%Events.FriendRemoved{pubkey: contact.pubkey})
        :ok

      _member_only_or_absent ->
        :ok
    end
  end

  @doc "The friends — the keys the reader added by hand — oldest first."
  @spec list_friends() :: [Contact.t()]
  def list_friends,
    do:
      Repo.all(
        from(contact in Contact,
          where: not is_nil(contact.added_at),
          order_by: [contact.added_at, contact.pubkey]
        )
      )

  @doc "One contact by public key, or nil."
  @spec contact_by_pubkey(String.t()) :: Contact.t() | nil
  def contact_by_pubkey(pubkey) when is_binary(pubkey),
    do: Repo.get_by(Contact, pubkey: String.downcase(pubkey))

  @doc """
  The NIP-19 `npub` form of a public key. The context owns the key
  vocabulary; the web layer never reaches into `Nostr.Keys` itself.
  """
  @spec to_npub(String.t()) :: String.t()
  def to_npub(pubkey) when is_binary(pubkey), do: Keys.to_npub(pubkey)

  @doc "Every friend's pubkey — the authors an added-rule relay's feed subscribes to."
  @spec friend_pubkeys() :: [String.t()]
  def friend_pubkeys,
    do:
      Repo.all(
        from(contact in Contact,
          where: not is_nil(contact.added_at),
          select: contact.pubkey,
          order_by: contact.pubkey
        )
      )

  @doc """
  Whether a key's events are kept: the identity, a friend, or a member of
  a relay whose follow rule is members. The one gate both ingest paths
  use. Hex in any case.
  """
  @spec followed_key?(String.t()) :: boolean()
  def followed_key?(pubkey) when is_binary(pubkey) do
    pubkey = String.downcase(pubkey)
    pubkey == Identity.pubkey() or Repo.exists?(followed_query(pubkey))
  end

  @doc """
  Every person this reader follows, by public key (ADR-074): the identity's
  own when one exists, every friend, and every member of a members-rule
  relay — hidden ones included, flagged — each as a `Person` with the name
  and the hue their `Profile` published, when one is stored, and its
  avatar when the reader shows it. The one place a contact row and a
  profile become what the reader sees.
  """
  @spec people() :: %{optional(String.t()) => Person.t()}
  def people do
    # Five fields per row: `raw_event` carries the encoded avatar and is
    # for republish, not for a page load.
    profiles =
      Profile
      |> select([p], struct(p, [:pubkey, :name, :avatar_type, :hue, :created_at]))
      |> Repo.all()
      |> Map.new(&{&1.pubkey, &1})

    memberships =
      from(member in RelayMember,
        join: relay in assoc(member, :relay),
        where: relay.follow == ^:members,
        select: {member.pubkey, relay.url}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    followed =
      Contact
      |> Repo.all()
      |> Enum.filter(&(Contact.friend?(&1) or is_map_key(memberships, &1.pubkey)))
      |> Map.new(
        &{&1.pubkey, person_for(&1, Map.get(profiles, &1.pubkey), Map.get(memberships, &1.pubkey, []))}
      )

    case Identity.pubkey() do
      nil -> followed
      me -> Map.put(followed, me, own_person_for(me, Map.get(profiles, me)))
    end
  end

  @doc "The followed people the surfaces draw: `people/0` less the hidden. The one place hidden is applied."
  @spec visible_people() :: %{optional(String.t()) => Person.t()}
  def visible_people, do: Map.reject(people(), fn {_pubkey, person} -> person.hidden end)

  @doc "How many of the given people the reader follows: everyone but themself."
  @spec count_followed(%{optional(String.t()) => Person.t()}) :: non_neg_integer()
  def count_followed(people) when is_map(people),
    do: Enum.count(people, fn {_pubkey, person} -> not person.own? end)

  @doc """
  The reader as a person, with or without an identity: the review modal
  previews as the reader before a key exists.
  """
  @spec own_person() :: Person.t()
  def own_person do
    case own_profile() do
      nil -> own_person_for(Identity.pubkey(), nil)
      %Profile{pubkey: pubkey} = profile -> own_person_for(pubkey, profile)
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
  The profile name rule, the one `save_profile/3` applies: `DisplayName.check/1`.
  The form checks it before it consumes a chosen picture, so a name error
  costs nothing.
  """
  @spec check_name(String.t()) :: {:ok, String.t()} | {:error, :name_required | :name_too_long}
  defdelegate check_name(name), to: MediaCentaur.DisplayName, as: :check

  @typedoc "What the save does with the avatar: keep the stored one, remove it, or set new WebP bytes (the master `ImageFiles.webp_master/4` made)."
  @type avatar_change :: :keep | :none | {:new, binary()}

  @doc """
  Saves the reader's own profile (ADR-073, UIDR-047): mints the identity
  when none exists, stamps the event strictly after the stored one,
  signs, stores, publishes to every connected relay and broadcasts
  `ProfileUpdated`. The name is required and capped at
  `Profile.Translation.max_name_length/0` characters, checked before
  anything is minted: the form refuses to save without one. The avatar
  change keeps the stored avatar, removes it, or sets new bytes; the
  stored file follows the row. New bytes over
  `Profile.Translation.max_avatar_bytes/0` are refused
  (`:avatar_too_large`) before anything is minted. `:keep` publishes the
  stored file's bytes; when the file is missing it publishes none, and
  the row follows. The hue is the angle the circle takes (UIDR-048), nil
  for none; out of range is refused (`:invalid_hue`) before anything is
  minted.
  """
  @spec save_profile(String.t(), avatar_change(), Hue.t() | nil) ::
          {:ok, Profile.t()}
          | {:error, :name_required | :name_too_long | :avatar_too_large | :invalid_hue}
  def save_profile(name, avatar_change, hue) when is_binary(name) do
    with {:ok, name} <- check_name(name),
         :ok <- within_avatar_cap(avatar_change),
         :ok <- valid_hue(hue) do
      secret = Identity.ensure()
      me = Identity.pubkey()
      stored = Repo.get_by(Profile, pubkey: me)
      avatar = resolve_avatar(avatar_change, stored)
      created_at = Event.stamp_after(stored && stored.created_at, System.os_time(:second))

      event =
        %{name: name, avatar: avatar, hue: hue}
        |> ProfileTranslation.to_event(me, created_at)
        |> Event.sign(secret)

      {:ok, attrs} = ProfileTranslation.from_event(event)
      profile = store_profile(stored, attrs)
      Connections.publish(event)
      Events.broadcast(%Events.ProfileUpdated{pubkey: me})
      {:ok, profile}
    end
  end

  @doc """
  Stores a verified profile event from a followed key (`followed_key?/1`):
  newer wins, a tie or an older one is `:ignored`, anything malformed is
  dropped whole. Broadcasts `ProfileUpdated` when stored.
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
         :ok <- followed_or_error(event.pubkey),
         {:ok, attrs} <- ProfileTranslation.from_event(event) do
      case Repo.get_by(Profile, pubkey: attrs.pubkey) do
        %Profile{created_at: held} when held >= attrs.created_at ->
          :ignored

        stored ->
          profile = store_profile(stored, attrs)
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

  defp within_avatar_cap({:new, bytes}) when is_binary(bytes) do
    if byte_size(bytes) <= ProfileTranslation.max_avatar_bytes(),
      do: :ok,
      else: {:error, :avatar_too_large}
  end

  defp within_avatar_cap(_keep_or_none), do: :ok

  defp resolve_avatar(:none, _stored), do: nil

  defp resolve_avatar({:new, bytes}, _stored) when is_binary(bytes),
    do: %{type: ProfileTranslation.master_type(), bytes: bytes}

  defp resolve_avatar(:keep, %Profile{pubkey: pubkey, avatar_type: type}) when is_binary(type) do
    case AvatarStore.read(pubkey, type) do
      {:ok, bytes} -> %{type: type, bytes: bytes}
      {:error, _missing} -> nil
    end
  end

  defp resolve_avatar(:keep, _none), do: nil

  # The row and the file move together: the avatar bytes never enter
  # the row, and a profile without an avatar leaves no file behind. Row
  # first: a write that fails after the row leaves a type with no file,
  # which `AvatarStore.url/3` reads as no avatar until a newer profile
  # arrives; file first could serve new bytes under the old version.
  defp store_profile(stored, attrs) do
    {bytes, row_attrs} = Map.pop(attrs, :avatar_bytes)

    profile =
      if stored,
        do: Repo.update!(Profile.changeset(stored, row_attrs)),
        else: Repo.insert!(Profile.changeset(row_attrs))

    if bytes,
      do: AvatarStore.write(profile.pubkey, profile.avatar_type, bytes),
      else: AvatarStore.delete(profile.pubkey)

    profile
  end

  defp delete_profile(pubkey) do
    delete_profile_row(pubkey)
    AvatarStore.delete(pubkey)
  end

  defp delete_profile_row(pubkey),
    do: Repo.delete_all(from(profile in Profile, where: profile.pubkey == ^pubkey))

  # The file half of a prune, after the transaction that dropped the rows
  # committed: an unlink cannot be rolled back, and the write lock is not
  # held over filesystem work.
  defp delete_avatars(pubkeys), do: Enum.each(pubkeys, &AvatarStore.delete/1)

  defp followed_or_error(pubkey), do: if(followed_key?(pubkey), do: :ok, else: {:error, :unknown_author})

  defp followed_query(pubkey) do
    from(contact in Contact,
      where: contact.pubkey == ^pubkey,
      where: not is_nil(contact.added_at) or contact.pubkey in subquery(member_pubkeys_query())
    )
  end

  # The keys followed through any members-rule relay.
  defp member_pubkeys_query do
    from(member in RelayMember,
      join: relay in assoc(member, :relay),
      where: relay.follow == ^:members,
      select: member.pubkey
    )
  end

  defp own_person_for(pubkey, profile) do
    %Person{
      pubkey: pubkey,
      own?: true,
      published_name: profile && profile.name,
      avatar_url: avatar_url(profile),
      published_hue: profile && profile.hue,
      short_npub: pubkey && short_npub(pubkey)
    }
  end

  defp person_for(%Contact{} = contact, profile, relay_urls) do
    %Person{
      pubkey: contact.pubkey,
      name_override: contact.name_override,
      published_name: profile && profile.name,
      avatar_url: if(contact.show_avatar, do: avatar_url(profile)),
      show_avatar: contact.show_avatar,
      published_hue: profile && profile.hue,
      hue_override: contact.hue_override,
      own?: false,
      friend?: Contact.friend?(contact),
      hidden: contact.hidden,
      member_of: Enum.sort(relay_urls),
      short_npub: short_npub(contact.pubkey),
      added_on: contact.added_at && DateTime.to_date(contact.added_at)
    }
  end

  defp avatar_url(nil), do: nil

  defp avatar_url(%Profile{} = profile),
    do: AvatarStore.url(profile.pubkey, profile.avatar_type, profile.created_at)

  defp not_own_key(pubkey), do: if(Identity.pubkey() == pubkey, do: {:error, :own_key}, else: :ok)

  defp valid_hue(nil), do: :ok
  defp valid_hue(hue), do: if(Hue.valid?(hue), do: :ok, else: {:error, :invalid_hue})

  defp known_contact(pubkey) do
    case contact_by_pubkey(pubkey) do
      nil -> {:error, :not_a_contact}
      contact -> {:ok, contact}
    end
  end

  defp promote(%Contact{} = member, name) do
    attrs =
      if is_binary(name) and String.trim(name) != "",
        do: %{added_at: now(), name_override: name},
        else: %{added_at: now()}

    contact = Repo.update!(Contact.changeset(member, attrs))
    Events.broadcast(%Events.FriendAdded{pubkey: contact.pubkey})
    {:ok, contact}
  end

  defp insert_contact(pubkey, name) do
    case Repo.insert(Contact.changeset(%{pubkey: pubkey, name_override: name, added_at: now()})) do
      {:ok, contact} ->
        Events.broadcast(%Events.FriendAdded{pubkey: contact.pubkey})
        {:ok, contact}

      {:error, changeset} ->
        # A concurrent insert of the same key is the re-add case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Contact, pubkey: pubkey)},
          else: {:error, changeset}
    end
  end

  defp now, do: DateTime.utc_now(:second)

  # No change is no broadcast. The changeset cannot fail here: the name
  # is optional, the switches are booleans by guard, the hue is checked
  # by `valid_hue/1` and the key is unchanged, so a failure is a bug.
  defp apply_change(%Contact{} = existing, attrs) do
    changeset = Contact.changeset(existing, attrs)

    if changeset.changes == %{} do
      {:ok, existing}
    else
      contact = Repo.update!(changeset)
      Events.broadcast(%Events.ContactChanged{pubkey: contact.pubkey})
      {:ok, contact}
    end
  end

  defp insert_relay(url, normalized, follow) do
    case Repo.insert(Relay.changeset(%{url: url, follow: follow})) do
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

  # --- members -----------------------------------------------------------------

  @doc """
  Records that `pubkey` published on the relay at `url`, for the sync loop:
  on a relay whose follow rule is members the key becomes followed, with a
  contact row when none exists, and `seen_at` moves to now; `:ignored` on
  an added-rule relay, an unknown relay, or the reader's own key.
  Broadcasts `MembersChanged` the first time a key is seen on a relay.
  """
  @spec note_member(String.t(), String.t()) :: :ok | :ignored
  def note_member(url, pubkey) when is_binary(url) and is_binary(pubkey) do
    pubkey = String.downcase(pubkey)

    case get_relay(url) do
      %Relay{follow: :members} = relay ->
        if pubkey == Identity.pubkey(), do: :ignored, else: record_member(relay, pubkey)

      _added_or_unknown ->
        :ignored
    end
  end

  @doc """
  Forgets the members of the relay at `url` that the connect begun at
  `before` did not see again, for the sync loop at the end of a read: a key
  the relay no longer serves stops being followed through it, and loses
  its profile and avatar unless still followed another way. Broadcasts
  `MembersChanged` when any row went. `:ignored` for an unknown relay.
  """
  @spec sweep_members(String.t(), DateTime.t()) :: :ok | :ignored
  def sweep_members(url, %DateTime{} = before) when is_binary(url) do
    case get_relay(url) do
      nil ->
        :ignored

      relay ->
        {:ok, {swept, pruned}} =
          Repo.transaction(fn ->
            stale =
              from(member in RelayMember,
                where: member.relay_id == ^relay.id and member.seen_at < ^before
              )

            pubkeys = Repo.all(from(member in stale, select: member.pubkey))
            Repo.delete_all(stale)
            {pubkeys, prune_unfollowed(pubkeys)}
          end)

        delete_avatars(pruned)
        if swept != [], do: Events.broadcast(%Events.MembersChanged{url: relay.url})
        :ok
    end
  end

  # The common path — a key seen again — is the one write that moves
  # `seen_at`; a miss is the first sight, which makes the rows and tells.
  defp record_member(%Relay{} = relay, pubkey) do
    seen_at = DateTime.utc_now()

    seen =
      from(member in RelayMember,
        where: member.relay_id == ^relay.id and member.pubkey == ^pubkey
      )

    case Repo.update_all(seen, set: [seen_at: seen_at]) do
      {1, _none} ->
        :ok

      {0, _none} ->
        Repo.insert!(Contact.changeset(%{pubkey: pubkey}),
          on_conflict: :nothing,
          conflict_target: :pubkey
        )

        Repo.insert!(RelayMember.changeset(%{relay_id: relay.id, pubkey: pubkey, seen_at: seen_at}))
        Events.broadcast(%Events.MembersChanged{url: relay.url})
        :ok
    end
  end

  # Drops every membership row of a relay and prunes what the keys no
  # longer earn, returning the pruned keys. Runs inside the caller's
  # transaction.
  defp forget_members(%Relay{id: relay_id}) do
    rows = from(member in RelayMember, where: member.relay_id == ^relay_id)
    pubkeys = Repo.all(from(member in rows, select: member.pubkey))
    Repo.delete_all(rows)
    prune_unfollowed(pubkeys)
  end

  # The keys among `pubkeys` that `prune_if_unfollowed/1` pruned.
  defp prune_unfollowed(pubkeys),
    do: pubkeys |> Enum.map(&prune_if_unfollowed/1) |> Enum.reject(&is_nil/1)

  # A key followed neither by the reader's hand nor through any relay
  # keeps its contact row — its overrides and `hidden` wait for a return —
  # but not its profile and avatar, which `people/0` would never show and
  # `ingest_profile/1` would refuse to refresh. Drops the profile row
  # only, inside the caller's transaction, and returns the key so the
  # caller drops the avatar file once the transaction committed
  # (`delete_avatars/1`); nil when the key is still followed.
  defp prune_if_unfollowed(pubkey) do
    if !followed_key?(pubkey) do
      delete_profile_row(pubkey)
      pubkey
    end
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, meta}} -> meta[:constraint] == :unique end)
  end
end
