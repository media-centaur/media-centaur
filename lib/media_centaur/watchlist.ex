defmodule MediaCentaur.Watchlist do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.Profiles, MediaCentaur.TmdbArtwork, MediaCentaur.TMDB],
    exports: [TitleIntent, Events, Events.RungChanged, Events.CaughtUp]

  @moduledoc """
  The watchlist: the **title intents** a person holds — one record per
  title, carrying the rung that says what the app should do about that
  title's releases — and, in later iterations, the candidate sources
  that feed them (TMDB discover, list import, friend reviews). Shown
  on Discovery by release stage (UIDR-050, amended 2026-11-02).

  A record here is the only authored thing in the whole tracking story.
  Watchlist stores the rung and knows nothing about what it causes: no
  calendars, no wants, no grabs. `ReleaseTracking.set_rung/4` is the one
  write path, because deriving the machinery needs to see both sides, and
  the dependency runs that way (ADR-066).

  Accepts `MediaCentaur.TMDB.Title` at the boundary — the app-wide title
  value every candidate source produces (converged 2026-09-02; see
  docs/superpowers/specs/2026-09-02-friends-recommendations-design.md).
  A record keeps only that title's identity: the snapshot a listed title
  is painted from is the TMDB store's, attached on every read by
  `Watchlist.Titles` (ADR-071).

  Named `Discovery` until 2026-10-03 (ADR-075 rule 3: a context carries
  its surface's name). `Pipeline.Discovery` — file discovery — is a
  different context.
  """

  import Ecto.Query

  alias MediaCentaur.Watchlist.{Events, TitleIntent, Titles}
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Profiles.Actor
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  @type media_type :: :movie | :tv_series
  @type ref :: {integer(), media_type()}

  @doc "Subscribe the caller to title-intent update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.watchlist_updates())

  @doc """
  Puts `title` at `rung`, creating the record or moving the existing one.
  `attrs` may carry `:source`, `:note` and — for a `:friend`-sourced
  record — `:activity_id`; they apply on creation only, since provenance
  is about where a title first came from. `actor` is the profile that
  acted, or `nil` when no person did; it rides on the `RungChanged` event
  so a listing is shared only for a person's act (ADR-082).

  This is Watchlist's write, not the app's: raising a rung has
  consequences Watchlist must not know about, so callers go through
  `ReleaseTracking.set_rung/4`.
  """
  @spec put_rung(Title.t(), TitleIntent.rung(), Actor.t() | nil, map()) ::
          {:ok, TitleIntent.t()} | {:error, Ecto.Changeset.t()}
  def put_rung(%Title{} = title, rung, actor, attrs \\ %{}) do
    case fetch_intent(title.tmdb_id, title.media_type) do
      %TitleIntent{} = existing ->
        existing
        |> TitleIntent.rung_changeset(rung, title)
        |> Repo.update()
        |> case do
          # Leaving Ignored for the list is the one move that is also a
          # first listing: the artwork was not promoted when it was dismissed.
          {:ok, intent} when existing.rung == :ignored ->
            ensure_artwork_async(intent)
            announce({:ok, intent}, existing.rung, title, actor)

          result ->
            announce(result, existing.rung, title, actor)
        end

      nil ->
        title
        |> TitleIntent.create_changeset(rung, attrs)
        |> Repo.insert()
        |> case do
          {:ok, intent} ->
            ensure_artwork_async(intent)
            announce({:ok, intent}, nil, title, actor)

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            # A concurrent write won the race exactly when a unique
            # constraint fired (constraint metadata, not field name — a
            # future validation on :tmdb_id must not be mistaken for the
            # race); move the winner to the rung this call asked for.
            if unique_violation?(errors),
              do: put_rung(title, rung, actor, attrs),
              else: {:error, changeset}
        end
    end
  end

  @doc """
  Forgets a title entirely — the Off rung. Absent refs are a no-op. The
  event carries the store's snapshot of the title, a bare identity when
  the store never held it, and `actor`, the profile that acted or `nil`.
  """
  @spec forget(integer(), media_type(), Actor.t() | nil) :: :ok
  def forget(tmdb_id, media_type, actor) do
    case get_intent(tmdb_id, media_type) do
      nil ->
        :ok

      intent ->
        Repo.delete(intent)

        Events.broadcast(%Events.RungChanged{
          tmdb_id: tmdb_id,
          media_type: media_type,
          title: intent.title,
          previous_rung: intent.rung,
          rung: nil,
          actor: actor
        })

        :ok
    end
  end

  @doc """
  Sets the title's caught-up point — the latest aired episode the person
  has seen (`TitleIntent.caught_up_changeset/2`), or `nil` for none: they
  have seen nothing yet — and broadcasts `Events.CaughtUp`.
  `{:error, :not_listed}` when the title has no record: the point is a
  fact about a listed title. Who decides *which* episode — the latest
  aired on Follow and on the *Caught up* press, a chosen one from the
  caught-up panel — is `ReleaseTracking.catch_up/2`, the verb's one write
  path; this is the record's half.
  """
  @spec catch_up(integer(), media_type(), TitleIntent.caught_up() | nil) ::
          {:ok, TitleIntent.t()} | {:error, :not_listed | Ecto.Changeset.t()}
  def catch_up(tmdb_id, media_type, point) do
    case fetch_intent(tmdb_id, media_type) do
      nil ->
        {:error, :not_listed}

      %TitleIntent{} = intent ->
        intent
        |> TitleIntent.caught_up_changeset(point)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {season, episode} = point || {nil, nil}

            Events.broadcast(%Events.CaughtUp{
              tmdb_id: tmdb_id,
              media_type: media_type,
              season: season,
              episode: episode
            })

            {:ok, Titles.attach_one(updated)}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc "The title's caught-up point, or nil when none is set or the title is Off."
  @spec caught_up(integer(), media_type()) :: TitleIntent.caught_up() | nil
  def caught_up(tmdb_id, media_type) do
    case fetch_intent(tmdb_id, media_type) do
      nil -> nil
      %TitleIntent{} = intent -> TitleIntent.caught_up(intent)
    end
  end

  @doc "The title's record with its stored snapshot attached, or nil when it is Off."
  @spec get_intent(integer(), media_type()) :: TitleIntent.t() | nil
  def get_intent(tmdb_id, media_type), do: tmdb_id |> fetch_intent(media_type) |> Titles.attach_one()

  defp fetch_intent(tmdb_id, media_type) do
    Repo.one(from(i in TitleIntent, where: i.tmdb_id == ^tmdb_id and i.media_type == ^media_type))
  end

  @doc "The title's rung, or nil when it is Off."
  @spec rung(integer(), media_type()) :: TitleIntent.rung() | nil
  def rung(tmdb_id, media_type) do
    Repo.one(
      from(i in TitleIntent,
        where: i.tmdb_id == ^tmdb_id and i.media_type == ^media_type,
        select: i.rung
      )
    )
  end

  @doc "Whether the title auto-grabs — plans its releases when they drop. The one question acquisition asks about a title."
  @spec grabs?(integer(), media_type()) :: boolean()
  def grabs?(tmdb_id, media_type), do: TitleIntent.grabs?(rung(tmdb_id, media_type))

  @doc "Whether the title is on the list at all — List or above; Off and Ignored are not."
  @spec listed?(integer(), media_type()) :: boolean()
  def listed?(tmdb_id, media_type), do: TitleIntent.rung_at_least?(rung(tmdb_id, media_type), :list)

  @typedoc "A record as every list read returns it: the intent with its snapshot, and the owning library container's id."
  @type listed :: %{intent: TitleIntent.t(), library_owner_id: Ecto.UUID.t() | nil}

  @doc """
  Every title intent — Ignored included — newest first, its stored
  snapshot attached, each with the owning library container's id (nil
  when the library doesn't know the title), derived live via
  `Library.ExternalIds.tmdb_owners/1`, never stored. The Watchlist page's
  inventory read (campaign `discovery.md`, M15); `list_watchlist/0` is
  the List-or-above filter of it.
  """
  @spec list_intents() :: [listed()]
  def list_intents do
    intents =
      from(i in TitleIntent, order_by: [desc: i.inserted_at])
      |> Repo.all()
      |> Titles.attach()

    owners = ExternalIds.tmdb_owners(Enum.map(intents, &{&1.tmdb_id, &1.media_type}))

    Enum.map(intents, fn intent ->
      %{intent: intent, library_owner_id: Map.get(owners, {intent.tmdb_id, intent.media_type})}
    end)
  end

  @doc """
  The watchlist: every title intent at List or above, as `list_intents/0`
  returns them. Ignored titles are records too, but not on the list.
  """
  @spec list_watchlist() :: [listed()]
  def list_watchlist do
    Enum.reject(list_intents(), &(&1.intent.rung == :ignored))
  end

  @doc """
  Every recorded title's rung, Ignored included, as `{tmdb_id,
  media_type} => rung` — bulk decoration for search rows and list rows,
  which show the rung rather than a yes/no, and the Feed
  tab's filter.
  """
  @spec rungs() :: %{ref() => TitleIntent.rung()}
  def rungs do
    Map.new(Repo.all(from(i in TitleIntent, select: {{i.tmdb_id, i.media_type}, i.rung})))
  end

  # The event carries the title the person acted on — always named, so a
  # listing can be shared from it — and the record is returned as every
  # read returns it, with the store's snapshot attached.
  defp announce({:ok, %TitleIntent{} = intent}, previous_rung, %Title{} = title, actor) do
    Events.broadcast(%Events.RungChanged{
      tmdb_id: intent.tmdb_id,
      media_type: intent.media_type,
      title: title,
      previous_rung: previous_rung,
      rung: intent.rung,
      actor: actor
    })

    {:ok, Titles.attach_one(intent)}
  end

  defp announce(result, _previous_rung, _title, _actor), do: result

  defp unique_violation?(errors) do
    Enum.any?(errors, fn {_field, {_msg, meta}} -> meta[:constraint] == :unique end)
  end

  # Listed titles persist, so their artwork moves from TMDB-hotlink to
  # the local referenced tier. Network — context-layer task (ADR-049).
  # An ignored title is a record the person does not want; nothing is
  # fetched for it.
  defp ensure_artwork_async(%TitleIntent{rung: :ignored}), do: :ok

  defp ensure_artwork_async(intent) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      TmdbArtwork.ensure(intent.media_type, intent.tmdb_id)
    end)

    :ok
  end
end
