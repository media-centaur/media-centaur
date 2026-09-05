defmodule MediaCentaur.Activities do
  use Boundary,
    deps: [
      MediaCentaur.Social,
      MediaCentaur.Nostr,
      MediaCentaur.TMDB,
      MediaCentaur.TmdbArtwork
    ],
    exports: [
      Activity,
      Activity.Episode,
      Events,
      Events.Deleted,
      Events.Received,
      Events.Sent,
      TmdbArtworkHolds,
      Translation
    ]

  @moduledoc """
  Bounded context for activities: what this install told its friends and
  what its friends told it. An activity is one signed statement by one
  signer about one title, of one of three kinds — a recommendation, a
  title watched, a release tracked (`Activity`).

  Records are translated from signed events (`Translation`), kept one
  per author + kind + title (a newer event replaces the row), and synced
  with the relays by `Activities.Sync`. Knows nothing about the watchlist
  or the library — the web layer joins those, which is why `list_feed/0`
  decorates rows with the friend's nickname and nothing else.

  `list_feed/0` includes this identity's own activities alongside
  received ones — `own?` and `nickname` tell a row apart; `nickname` is
  `nil` on an own row. Withdrawn rows (tombstones, see `Activity`) are
  excluded everywhere except `own_events/0`, which republishes their
  deletions.

  Recommending is an explicit act of sharing and always publishes.
  Watching and tracking are published by `Activities.Publisher` only
  while their sharing toggle is on; `watched/2` and `tracking/1` are the
  primitives it calls and do not consult the toggle themselves.

  Broadcasts typed events on `activities:updates` (subscribe through
  `subscribe/0`).
  """

  import Ecto.Query

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Activities.Events
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  @type feed_row :: %{activity: Activity.t(), nickname: String.t() | nil, own?: boolean()}

  @doc "Subscribe the caller to activity events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.activities_updates())

  @max_note_length Translation.max_note_length()

  @doc """
  Builds, signs, stores and publishes a recommendation from this
  identity, creating the identity first (`Identity.ensure/0`) if none
  exists yet. `note` is trimmed first; blank becomes `nil`; a note over
  #{@max_note_length} characters is rejected with `{:error,
  :note_too_long}` and nothing is stored. Stamped after whatever the
  row already holds (see `stamp/3`).
  """
  @spec recommend(Title.t(), String.t() | nil) ::
          {:ok, Activity.t()} | {:error, :note_too_long | term()}
  def recommend(%Title{} = title, note) do
    with {:ok, note} <- validate_note(note) do
      publish_own(:recommendation, title, note: note)
    end
  end

  @doc """
  Builds, signs, stores and publishes a watched activity from this
  identity: `title` finished, at `episode` for a TV series (`nil` for a
  movie). Watching the next episode replaces the row and the relay's
  record — the feed shows the latest episode finished, not every one.
  """
  @spec watched(Title.t(), Episode.t() | nil) :: {:ok, Activity.t()} | {:error, term()}
  def watched(%Title{} = title, episode), do: publish_own(:watched, title, episode: episode)

  @doc "Builds, signs, stores and publishes a tracking activity from this identity: `title` is now tracked."
  @spec tracking(Title.t()) :: {:ok, Activity.t()} | {:error, term()}
  def tracking(%Title{} = title), do: publish_own(:tracking, title, [])

  defp publish_own(kind, %Title{} = title, payload) do
    secret = Identity.ensure()
    me = Identity.pubkey()
    now = System.os_time(:second)

    row =
      existing(%{kind: kind, author_pubkey: me, tmdb_id: title.tmdb_id, media_type: title.media_type})

    times = [created_at: stamp(row, now, :after), acted_at: now]
    event = kind |> Translation.to_event(title, payload, me, times) |> Event.sign(secret)

    with {:ok, attrs} <- Translation.from_event(event),
         {:ok, activity} <- upsert(attrs) do
      Connections.publish(event)
      Events.broadcast(%Events.Sent{id: activity.id, kind: kind})
      {:ok, activity}
    end
  end

  @doc """
  Withdraws one of this identity's own activities: signs a deletion
  (kind 5) for its kind and address, keeps the row as a tombstone,
  publishes the deletion to every connected relay, and broadcasts
  `Events.Deleted`. `{:error, :not_own}` for a friend's row; `{:error,
  :not_found}` for an unknown id. Withdrawing a tombstone again is a
  no-op returning the row.
  """
  @spec delete(Ecto.UUID.t()) :: {:ok, Activity.t()} | {:error, :not_own | :not_found | term()}
  def delete(id) do
    case Repo.get(Activity, id) do
      nil -> {:error, :not_found}
      %Activity{deleted_at: %DateTime{}} = activity -> {:ok, activity}
      %Activity{} = activity -> delete_own(activity)
    end
  end

  defp delete_own(%Activity{author_pubkey: author} = activity) do
    if author == Identity.pubkey() do
      now = System.os_time(:second)
      times = [created_at: stamp(activity, now, :at_or_after), deleted_at: now]

      event =
        activity.kind
        |> Translation.to_deletion(
          author,
          activity.media_type,
          activity.tmdb_id,
          activity.event_id,
          times
        )
        |> Event.sign(Identity.secret())

      with {:ok, attrs} <- Translation.from_deletion(event),
           {:ok, activity} <- Repo.update(Activity.tombstone_changeset(activity, attrs)) do
        Connections.publish(event)
        Events.broadcast(%Events.Deleted{id: activity.id, kind: activity.kind, author_pubkey: author})
        {:ok, activity}
      end
    else
      {:error, :not_own}
    end
  end

  @doc """
  Stores a relay-delivered event: it must verify, and its author must be
  a friend or this identity. An activity event is stored when newer than
  the row — a tombstone included, which it revives. A deletion (kind 5)
  tombstones the row it addresses when the row is not newer. `:ignored`
  otherwise — including our own events coming back off a relay.
  """
  @spec ingest(Event.t()) :: {:ok, Activity.t()} | :ignored | {:error, term()}
  def ingest(%Event{kind: 5} = event) do
    with :ok <- Event.verify(event),
         :ok <- known_author(event.pubkey),
         {:ok, attrs} <- Translation.from_deletion(event) do
      tombstone_if_newer(attrs)
    end
  end

  def ingest(%Event{} = event) do
    with :ok <- Event.verify(event),
         :ok <- known_author(event.pubkey),
         {:ok, attrs} <- Translation.from_event(event) do
      store_if_newer(attrs)
    end
  end

  @doc """
  Every activity, newest first — received ones with the friend's
  nickname, this identity's own marked `own?: true` with `nickname: nil`
  (the Feed shows them as "You"). Before an identity exists nothing
  stored can be ours, so every row is a received one.
  """
  @spec list_feed() :: [feed_row()]
  def list_feed do
    friends = Map.new(Social.list_friends(), &{&1.pubkey, &1.nickname})
    me = Identity.pubkey()

    Activity
    |> live()
    |> order_by(desc: :acted_at)
    |> Repo.all()
    |> Enum.map(&feed_row(&1, me, friends))
  end

  @doc "Activities this install sent, newest first — none before an identity exists."
  @spec list_sent() :: [Activity.t()]
  def list_sent do
    case Identity.pubkey() do
      nil ->
        []

      me ->
        Activity
        |> live()
        |> where([a], a.author_pubkey == ^me)
        |> order_by([a], desc: a.acted_at)
        |> Repo.all()
    end
  end

  @doc """
  This identity's signed events, for republishing to relays that lack
  them: the activity event of every live own row, the deletion of every
  withdrawn one.
  """
  @spec own_events() :: [Event.t()]
  def own_events do
    case Identity.pubkey() do
      nil ->
        []

      me ->
        Activity
        |> where([a], a.author_pubkey == ^me)
        |> Repo.all()
        |> Enum.flat_map(&own_event/1)
    end
  end

  defp own_event(%Activity{deleted_at: nil, raw_event: raw}), do: decode_stored(raw)
  defp own_event(%Activity{deletion_event: raw}), do: decode_stored(raw)

  defp decode_stored(raw) do
    case Event.from_map(raw) do
      {:ok, event} -> [event]
      {:error, _reason} -> []
    end
  end

  defp live(query), do: where(query, [a], is_nil(a.deleted_at))

  @doc "One activity by id, or nil."
  @spec get(Ecto.UUID.t()) :: Activity.t() | nil
  def get(id), do: Repo.get(Activity, id)

  @doc """
  What an own event with this id is — the kind of a live row's activity,
  the deletion of a withdrawn one — or `nil` for an id no row holds (a
  stranger's event, or a deletion since superseded by a revival).
  """
  @spec own_event_kind(String.t()) :: Activity.kind() | :deletion | nil
  def own_event_kind(event_id) do
    query =
      from a in Activity,
        where:
          a.event_id == ^event_id or fragment("json_extract(?, '$.id') = ?", a.deletion_event, ^event_id)

    case Repo.one(query) do
      nil -> nil
      %Activity{event_id: ^event_id, kind: kind} -> kind
      %Activity{} -> :deletion
    end
  end

  @doc """
  Aggregate traffic for the Status widget, in two queries rather than
  loading every row: how many activities this identity sent, how many it
  received, and when the newest received one landed. Before an identity
  exists nothing stored can be ours, so everything counts as received
  (mirrors `list_feed/0`).
  """
  @spec counts() :: %{
          sent: non_neg_integer(),
          received: non_neg_integer(),
          last_received_at: DateTime.t() | nil
        }
  def counts do
    case Identity.pubkey() do
      nil ->
        %{
          sent: 0,
          received: Activity |> live() |> Repo.aggregate(:count),
          last_received_at: max_acted_at(live(Activity))
        }

      me ->
        counts_for(me)
    end
  end

  @doc """
  The activities for `ids`, as `%{id => activity}` — one query, for a
  caller decorating a list of rows that name their provenance. Ids with
  no row are simply absent from the map.
  """
  @spec get_many([Ecto.UUID.t()]) :: %{optional(Ecto.UUID.t()) => Activity.t()}
  def get_many([]), do: %{}

  def get_many(ids) when is_list(ids) do
    Activity
    |> where([a], a.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # --- internals ---

  # The wire time of a new own event. A relay keeps one record per
  # address and, on a tie, keeps what it holds (a deletion beating an
  # activity, contract Deletion rule 2), so an activity must be stamped
  # strictly after the activity or tombstone it supersedes and a
  # deletion no earlier than the activity it withdraws — otherwise the
  # relay discards what this install stored, and the own-events diff
  # republishes it on every connect.
  defp stamp(nil, now, _bound), do: now

  defp stamp(%Activity{} = activity, now, bound) do
    held = Enum.max([Activity.event_created_at(activity), Activity.deletion_created_at(activity) || 0])
    floor = if bound == :after, do: held + 1, else: held
    max(now, floor)
  end

  defp validate_note(nil), do: {:ok, nil}

  defp validate_note(note) when is_binary(note) do
    case String.trim(note) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= @max_note_length, do: {:ok, trimmed}, else: {:error, :note_too_long}
    end
  end

  defp feed_row(%Activity{author_pubkey: author} = activity, me, _friends) when author == me,
    do: %{activity: activity, nickname: nil, own?: true}

  defp feed_row(%Activity{} = activity, _me, friends),
    do: %{
      activity: activity,
      nickname: Map.get(friends, activity.author_pubkey, "a former friend"),
      own?: false
    }

  # One grouped count query buckets every row as "sent" or "received" by
  # comparing author_pubkey to `me`; a second query finds the newest
  # `acted_at` among the received bucket only.
  defp counts_for(me) do
    buckets =
      Activity
      |> live()
      |> group_by([a], fragment("CASE WHEN ? = ? THEN 'sent' ELSE 'received' END", a.author_pubkey, ^me))
      |> select(
        [a],
        {fragment("CASE WHEN ? = ? THEN 'sent' ELSE 'received' END", a.author_pubkey, ^me), count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    received_query = Activity |> live() |> where([a], a.author_pubkey != ^me)

    %{
      sent: Map.get(buckets, "sent", 0),
      received: Map.get(buckets, "received", 0),
      last_received_at: max_acted_at(received_query)
    }
  end

  defp max_acted_at(query), do: query |> select([a], max(a.acted_at)) |> Repo.one()

  defp known_author(pubkey) do
    if pubkey == Identity.pubkey() or Social.friend_by_pubkey(pubkey),
      do: :ok,
      else: {:error, :unknown_author}
  end

  defp store_if_newer(attrs) do
    case upsert_if_newer(attrs) do
      {:ok, activity} ->
        ensure_artwork_async(activity)
        broadcast_received(activity)
        {:ok, activity}

      other ->
        other
    end
  end

  # Our own event arriving back from a relay is not news to the feed.
  defp broadcast_received(%Activity{author_pubkey: author} = activity) do
    if author == Identity.pubkey(),
      do: :ok,
      else:
        Events.broadcast(%Events.Received{id: activity.id, kind: activity.kind, author_pubkey: author})
  end

  # Sync is the single writer for inbound events, so the unique-constraint
  # race Discovery guards against cannot happen here.
  defp upsert(attrs) do
    case existing(attrs) do
      nil -> Repo.insert(Activity.changeset(attrs))
      activity -> Repo.update(Activity.changeset(activity, attrs))
    end
  end

  # Newer on the wire than the row's event *and* its tombstone, if any:
  # an event older than the deletion that withdrew it is the stale copy
  # the tombstone exists to refuse.
  defp upsert_if_newer(attrs) do
    case existing(attrs) do
      nil ->
        Repo.insert(Activity.changeset(attrs))

      %Activity{} = activity ->
        if attrs.created_at > Activity.event_created_at(activity) and
             attrs.created_at > (Activity.deletion_created_at(activity) || 0),
           do: Repo.update(Activity.changeset(activity, attrs)),
           else: :ignored
    end
  end

  # A deletion applies to an event at or before its time; a row already
  # withdrawn by a deletion at least as new is left alone, and a
  # deletion for an address never stored has nothing to tombstone.
  defp tombstone_if_newer(attrs) do
    case existing(attrs) do
      nil ->
        :ignored

      %Activity{} = activity ->
        if tombstone_applies?(activity, attrs.created_at), do: tombstone(activity, attrs), else: :ignored
    end
  end

  defp tombstone_applies?(%Activity{} = activity, created_at) do
    case Activity.deletion_created_at(activity) do
      nil -> created_at >= Activity.event_created_at(activity)
      already -> created_at > already
    end
  end

  defp tombstone(activity, attrs) do
    with {:ok, activity} <- Repo.update(Activity.tombstone_changeset(activity, attrs)) do
      broadcast_deleted(activity)
      {:ok, activity}
    end
  end

  # Our own deletion arriving back from a relay is not news.
  defp broadcast_deleted(%Activity{author_pubkey: author} = activity) do
    if author == Identity.pubkey(),
      do: :ok,
      else:
        Events.broadcast(%Events.Deleted{id: activity.id, kind: activity.kind, author_pubkey: author})
  end

  defp existing(%{kind: kind, author_pubkey: author, tmdb_id: tmdb_id, media_type: media_type}),
    do:
      Repo.get_by(Activity, kind: kind, author_pubkey: author, tmdb_id: tmdb_id, media_type: media_type)

  # A title in the feed is standing interest: warm its artwork. Network —
  # context-layer task (ADR-049).
  defp ensure_artwork_async(activity) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      TmdbArtwork.ensure(activity.media_type, activity.tmdb_id)
    end)

    :ok
  end
end
