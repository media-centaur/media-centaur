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

  @type feed_row :: %{recommendation: Recommendation.t(), nickname: String.t()}

  @doc "Subscribe the caller to recommendation events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.recommendations_updates())

  @doc "Builds, signs, stores and publishes a recommendation from this identity."
  @spec recommend(Title.t(), String.t() | nil) :: {:ok, Recommendation.t()} | {:error, term()}
  def recommend(%Title{} = title, note) do
    secret = Identity.ensure()
    event = title |> Translation.to_event(note, Identity.pubkey()) |> Event.sign(secret)

    with {:ok, attrs} <- Translation.from_event(event),
         {:ok, rec} <- upsert(attrs) do
      Connections.publish(event)
      Events.broadcast(%Events.Sent{id: rec.id})
      {:ok, rec}
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
  Received recommendations, newest first, with the friend's nickname.
  Before an identity exists nothing stored can be ours, so every row is
  a received one.
  """
  @spec list_feed() :: [feed_row()]
  def list_feed do
    friends = Map.new(Friends.list_friends(), &{&1.pubkey, &1.nickname})

    Identity.pubkey()
    |> feed_query()
    |> Repo.all()
    |> Enum.map(&%{recommendation: &1, nickname: Map.get(friends, &1.author_pubkey, "a former friend")})
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

  defp feed_query(nil), do: from(r in Recommendation, order_by: [desc: r.recommended_at])

  defp feed_query(me),
    do: from(r in Recommendation, where: r.author_pubkey != ^me, order_by: [desc: r.recommended_at])

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
