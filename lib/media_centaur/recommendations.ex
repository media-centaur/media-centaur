defmodule MediaCentaur.Recommendations do
  use Boundary,
    deps: [
      MediaCentaur.Friends,
      MediaCentaur.Nostr,
      MediaCentaur.TMDB,
      MediaCentaur.TmdbArtwork
    ],
    exports: [
      Events,
      Events.Received,
      Events.Sent,
      Recommendation,
      TmdbArtworkHolds,
      Translation
    ]

  @moduledoc """
  Bounded context for recommendations: what this install sent to its
  friends and what its friends sent to it.

  Records are translated from signed kind-32160 events (`Translation`),
  kept one per author + title (a newer event replaces the row), and
  synced with the relays by `Recommendations.Sync`. Knows nothing about
  the watchlist or the library — the web layer joins those, which is why
  `list_feed/0` decorates rows with the friend's nickname and nothing
  else.

  `list_feed/0` includes this identity's own recommendations alongside
  received ones (spec: the Feed marks them "You") — `own?` and `nickname`
  tell a row apart; `nickname` is `nil` on an own row.

  Broadcasts typed events on `recommendations:updates` (subscribe
  through `subscribe/0`).
  """

  import Ecto.Query

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Recommendations.Events
  alias MediaCentaur.Recommendations.Recommendation
  alias MediaCentaur.Recommendations.Translation
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  @type feed_row :: %{recommendation: Recommendation.t(), nickname: String.t() | nil, own?: boolean()}

  @doc "Subscribe the caller to recommendation events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.recommendations_updates())

  @max_note_length Translation.max_note_length()

  @doc """
  Builds, signs, stores and publishes a recommendation from this
  identity, creating the identity first (`Identity.ensure/0`) if none
  exists yet. `note` is trimmed first; blank becomes `nil`; a note over
  #{@max_note_length} characters is rejected with `{:error,
  :note_too_long}` and nothing is stored.
  """
  @spec recommend(Title.t(), String.t() | nil) ::
          {:ok, Recommendation.t()} | {:error, :note_too_long | term()}
  def recommend(%Title{} = title, note) do
    with {:ok, note} <- validate_note(note) do
      secret = Identity.ensure()
      event = title |> Translation.to_event(note, Identity.pubkey()) |> Event.sign(secret)

      with {:ok, attrs} <- Translation.from_event(event),
           {:ok, rec} <- upsert(attrs) do
        Connections.publish(event)
        Events.broadcast(%Events.Sent{id: rec.id})
        {:ok, rec}
      end
    end
  end

  @doc """
  Stores a relay-delivered event: it must verify, and its author must be
  a friend or this identity. `:ignored` when it is not newer than what is
  already stored — including our own event coming back off a relay.
  """
  @spec ingest(Event.t()) :: {:ok, Recommendation.t()} | :ignored | {:error, term()}
  def ingest(%Event{} = event) do
    with :ok <- Event.verify(event),
         :ok <- known_author(event.pubkey),
         {:ok, attrs} <- Translation.from_event(event) do
      store_if_newer(attrs)
    end
  end

  @doc """
  Every recommendation, newest first — received ones with the friend's
  nickname, this identity's own marked `own?: true` with `nickname: nil`
  (the spec's Feed shows them as "You"). Before an identity exists
  nothing stored can be ours, so every row is a received one.
  """
  @spec list_feed() :: [feed_row()]
  def list_feed do
    friends = Map.new(Friends.list_friends(), &{&1.pubkey, &1.nickname})
    me = Identity.pubkey()

    Recommendation
    |> order_by(desc: :recommended_at)
    |> Repo.all()
    |> Enum.map(&feed_row(&1, me, friends))
  end

  @doc "Recommendations this install sent, newest first — none before an identity exists."
  @spec list_sent() :: [Recommendation.t()]
  def list_sent do
    case Identity.pubkey() do
      nil ->
        []

      me ->
        Repo.all(
          from(r in Recommendation, where: r.author_pubkey == ^me, order_by: [desc: r.recommended_at])
        )
    end
  end

  @doc "This identity's signed events, for republishing to relays that lack them."
  @spec own_events() :: [Event.t()]
  def own_events do
    Enum.flat_map(list_sent(), fn rec ->
      case Event.from_map(rec.raw_event) do
        {:ok, event} -> [event]
        {:error, _reason} -> []
      end
    end)
  end

  @doc "One recommendation by id, or nil."
  @spec get(Ecto.UUID.t()) :: Recommendation.t() | nil
  def get(id), do: Repo.get(Recommendation, id)

  @doc """
  Aggregate traffic for the Status widget, in two queries rather than
  loading every row: how many recommendations this identity sent, how
  many it received, and when the newest received one landed. Before an
  identity exists nothing stored can be ours, so everything counts as
  received (mirrors `list_feed/0`).
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
          received: Repo.aggregate(Recommendation, :count),
          last_received_at: max_recommended_at(Recommendation)
        }

      me ->
        counts_for(me)
    end
  end

  @doc """
  The recommendations for `ids`, as `%{id => recommendation}` — one query,
  for a caller decorating a list of rows that name their provenance. Ids
  with no row are simply absent from the map.
  """
  @spec get_many([Ecto.UUID.t()]) :: %{optional(Ecto.UUID.t()) => Recommendation.t()}
  def get_many([]), do: %{}

  def get_many(ids) when is_list(ids) do
    Recommendation
    |> where([r], r.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # --- internals ---

  defp validate_note(nil), do: {:ok, nil}

  defp validate_note(note) when is_binary(note) do
    case String.trim(note) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= @max_note_length, do: {:ok, trimmed}, else: {:error, :note_too_long}
    end
  end

  defp feed_row(%Recommendation{author_pubkey: author} = rec, me, _friends) when author == me,
    do: %{recommendation: rec, nickname: nil, own?: true}

  defp feed_row(%Recommendation{} = rec, _me, friends),
    do: %{
      recommendation: rec,
      nickname: Map.get(friends, rec.author_pubkey, "a former friend"),
      own?: false
    }

  # One grouped count query buckets every row as "sent" or "received" by
  # comparing author_pubkey to `me`; a second query finds the newest
  # `recommended_at` among the received bucket only.
  defp counts_for(me) do
    buckets =
      Recommendation
      |> group_by([r], fragment("CASE WHEN ? = ? THEN 'sent' ELSE 'received' END", r.author_pubkey, ^me))
      |> select(
        [r],
        {fragment("CASE WHEN ? = ? THEN 'sent' ELSE 'received' END", r.author_pubkey, ^me), count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    received_query = where(Recommendation, [r], r.author_pubkey != ^me)

    %{
      sent: Map.get(buckets, "sent", 0),
      received: Map.get(buckets, "received", 0),
      last_received_at: max_recommended_at(received_query)
    }
  end

  defp max_recommended_at(query), do: query |> select([r], max(r.recommended_at)) |> Repo.one()

  defp known_author(pubkey) do
    if pubkey == Identity.pubkey() or Friends.friend_by_pubkey(pubkey),
      do: :ok,
      else: {:error, :unknown_author}
  end

  defp store_if_newer(attrs) do
    case upsert_if_newer(attrs) do
      {:ok, rec} ->
        ensure_artwork_async(rec)
        broadcast_received(rec)
        {:ok, rec}

      other ->
        other
    end
  end

  # Our own event arriving back from a relay is not news to the feed.
  defp broadcast_received(%Recommendation{author_pubkey: author} = rec) do
    if author == Identity.pubkey(),
      do: :ok,
      else: Events.broadcast(%Events.Received{id: rec.id, author_pubkey: author})
  end

  # Sync is the single writer for inbound events, so the unique-constraint
  # race Discovery guards against cannot happen here.
  defp upsert(attrs) do
    case existing(attrs) do
      nil -> Repo.insert(Recommendation.changeset(attrs))
      rec -> Repo.update(Recommendation.changeset(rec, attrs))
    end
  end

  defp upsert_if_newer(attrs) do
    case existing(attrs) do
      nil ->
        Repo.insert(Recommendation.changeset(attrs))

      %Recommendation{recommended_at: at} = rec ->
        if DateTime.after?(attrs.recommended_at, at),
          do: Repo.update(Recommendation.changeset(rec, attrs)),
          else: :ignored
    end
  end

  defp existing(%{author_pubkey: author, tmdb_id: tmdb_id, media_type: media_type}),
    do: Repo.get_by(Recommendation, author_pubkey: author, tmdb_id: tmdb_id, media_type: media_type)

  # A recommended title is standing interest: warm its artwork. Network —
  # context-layer task (ADR-049).
  defp ensure_artwork_async(rec) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      TmdbArtwork.ensure(rec.media_type, rec.tmdb_id)
    end)

    :ok
  end
end
