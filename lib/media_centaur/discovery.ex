defmodule MediaCentaur.Discovery do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TmdbArtwork, MediaCentaur.TMDB],
    exports: [TitleIntent, Events, Events.RungChanged]

  @moduledoc """
  Bounded context for discovery: the **title intents** a person holds —
  one record per title, carrying the rung that says what the app should
  do about that title's releases — and, in later iterations, the
  candidate sources that feed them (TMDB discover, list import, friend
  recommendations).

  A record here is the only authored thing in the whole tracking story.
  Discovery stores the rung and knows nothing about what it causes: no
  calendars, no wants, no grabs. `ReleaseTracking.set_rung/3` is the one
  write path, because deriving the machinery needs to see both sides, and
  the dependency runs that way (ADR-065 §6/§7).

  Accepts `MediaCentaur.TMDB.Title` at the boundary — the app-wide title
  value every candidate source produces (converged 2026-09-02; see
  docs/superpowers/specs/2026-09-02-friends-recommendations-design.md).
  """

  import Ecto.Query

  alias MediaCentaur.Discovery.{Events, TitleIntent}
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  @type media_type :: :movie | :tv_series
  @type ref :: {integer(), media_type()}

  @doc "Subscribe the caller to title-intent update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.discovery_updates())

  @doc """
  Puts `title` at `rung`, creating the record or moving the existing one.
  `attrs` may carry `:source`, `:note` and — for a `:friend`-sourced
  record — `:activity_id`; they apply on creation only, since provenance
  is about where a title first came from.

  This is Discovery's write, not the app's: raising a rung has
  consequences Discovery must not know about, so callers go through
  `ReleaseTracking.set_rung/3`.
  """
  @spec put_rung(Title.t(), TitleIntent.rung(), map()) ::
          {:ok, TitleIntent.t()} | {:error, Ecto.Changeset.t()}
  def put_rung(%Title{} = title, rung, attrs \\ %{}) do
    case get_intent(title.tmdb_id, title.media_type) do
      %TitleIntent{} = existing ->
        existing
        |> TitleIntent.rung_changeset(rung, title)
        |> Repo.update()
        |> case do
          # Leaving Ignored for the list is the one move that is also a
          # first listing: the artwork was not promoted when it was dismissed.
          {:ok, intent} when existing.rung == :ignored ->
            ensure_artwork_async(intent)
            announce({:ok, intent}, existing.rung)

          result ->
            announce(result, existing.rung)
        end

      nil ->
        title
        |> TitleIntent.create_changeset(rung, attrs)
        |> Repo.insert()
        |> case do
          {:ok, intent} ->
            ensure_artwork_async(intent)
            announce({:ok, intent}, nil)

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            # A concurrent write won the race exactly when a unique
            # constraint fired (constraint metadata, not field name — a
            # future validation on :tmdb_id must not be mistaken for the
            # race); move the winner to the rung this call asked for.
            if unique_violation?(errors),
              do: put_rung(title, rung, attrs),
              else: {:error, changeset}
        end
    end
  end

  @doc "Forgets a title entirely — the Off rung. Absent refs are a no-op."
  @spec forget(integer(), media_type()) :: :ok
  def forget(tmdb_id, media_type) do
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
          rung: nil
        })

        :ok
    end
  end

  @doc "The title's record, or nil when it is Off."
  @spec get_intent(integer(), media_type()) :: TitleIntent.t() | nil
  def get_intent(tmdb_id, media_type) do
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

  @doc """
  The grab decision for a title, resolved from its rung against the
  global default. The one question acquisition asks about a title, so it
  asks it here rather than modelling the ladder itself.
  """
  @spec grab_mode(integer(), media_type(), String.t()) :: String.t()
  def grab_mode(tmdb_id, media_type, default),
    do: TitleIntent.grab_mode(rung(tmdb_id, media_type), default)

  @doc "Whether the title is on the list at all — List or above; Off and Ignored are not."
  @spec listed?(integer(), media_type()) :: boolean()
  def listed?(tmdb_id, media_type), do: TitleIntent.rung_at_least?(rung(tmdb_id, media_type), :list)

  @doc """
  The watchlist: every title intent at List or above, newest first, each
  with the owning library container's id (nil when the library doesn't
  know the title) — derived live via `Library.ExternalIds.tmdb_owners/1`,
  never stored. Ignored titles are records too, but not on the list.
  """
  @spec list_watchlist() :: [%{intent: TitleIntent.t(), library_owner_id: Ecto.UUID.t() | nil}]
  def list_watchlist do
    intents =
      Repo.all(from(i in TitleIntent, where: i.rung != :ignored, order_by: [desc: i.inserted_at]))

    owners = ExternalIds.tmdb_owners(Enum.map(intents, &{&1.tmdb_id, &1.media_type}))

    Enum.map(intents, fn intent ->
      %{intent: intent, library_owner_id: Map.get(owners, {intent.tmdb_id, intent.media_type})}
    end)
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

  defp announce({:ok, %TitleIntent{} = intent} = result, previous_rung) do
    Events.broadcast(%Events.RungChanged{
      tmdb_id: intent.tmdb_id,
      media_type: intent.media_type,
      title: intent.title,
      previous_rung: previous_rung,
      rung: intent.rung
    })

    result
  end

  defp announce(result, _previous_rung), do: result

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
