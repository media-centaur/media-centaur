defmodule MediaCentaur.Library.Episodes do
  @moduledoc """
  Records and lookup for `Episode` — the playable leaf beneath a
  `Season`.

  An Episode is identified within its season by `episode_number`, and
  that pair carries a unique index, which is what makes `find_or_create/1`
  safe under concurrent ingest.

  Reads that return an Episode run through `Library.ContentUrls` so the
  virtual `:content_url` is materialised from the WatchedFile chain
  before the struct escapes — Library Schema v2 Phase 2 Task I dropped
  the persisted column.

  Two lookup shapes exist because they answer different questions at
  different points in ingest. `find_by_path/2` walks
  `Episode → PlayableItem → WatchedFile` and is for callers holding a
  path; `find_by_season_episode/3` walks `Episode → Season` and is for
  callers holding the numbers, including `Library.Inbound` at file-link
  time, when the WatchedFile does not exist yet because it is being
  created in the same flow.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{ContentUrls, Episode, PlayableItem, Season, WatchedFile, Writes}
  alias MediaCentaur.Repo

  @doc "Every `Episode` row."
  @spec list_all() :: [Episode.t()]
  def list_all, do: Repo.all(Episode)

  @doc """
  Episodes of a season, with `:content_url` materialised. Extra preloads
  may be passed as `load:`.
  """
  @spec list_for_season(Ecto.UUID.t(), keyword()) :: [Episode.t()]
  def list_for_season(season_id, opts \\ []) do
    preloads = List.flatten([ContentUrls.required_preload() | Keyword.get(opts, :load, [])])

    from(e in Episode, where: e.season_id == ^season_id)
    |> Repo.all()
    |> Repo.preload(preloads)
    |> Enum.map(&ContentUrls.populate/1)
  end

  @doc "Fetches an `Episode` by id, with `:content_url` materialised."
  @spec fetch(Ecto.UUID.t()) :: {:ok, Episode.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(Episode, id) do
      nil ->
        {:error, :not_found}

      episode ->
        {:ok, episode |> Repo.preload(ContentUrls.required_preload()) |> ContentUrls.populate()}
    end
  end

  @doc "Inserts an `Episode`."
  @spec create(map()) :: {:ok, Episode.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: Repo.insert(Episode.create_changeset(attrs))

  @doc "Bang variant of `create/1` — raises on changeset error."
  @spec create!(map()) :: Episode.t()
  def create!(attrs), do: Repo.bang!(create(attrs))

  @doc """
  Finds the episode at `(season_id, episode_number)` or creates it.
  Recovers from a concurrent insert via the unique index on that pair.
  """
  @spec find_or_create(map()) :: {:ok, Episode.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create(attrs) do
    Writes.find_or_insert_by(
      Episode,
      [
        season_id: Writes.attr(attrs, :season_id),
        episode_number: Writes.attr(attrs, :episode_number)
      ],
      attrs
    )
  end

  @doc """
  The episode under `tv_series_id` linked to `file_path` via its
  `PlayableItem → WatchedFile` chain, or `nil`.

  `WatchedFile.file_path` is the sole source of truth for "the file on
  disk for this Episode". A `nil` result is an ordinary case — an ingest
  race or a stale event — and callers must handle it.
  """
  @spec find_by_path(Ecto.UUID.t(), String.t()) :: Episode.t() | nil
  def find_by_path(tv_series_id, file_path) when is_binary(tv_series_id) and is_binary(file_path) do
    Repo.one(
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        join: pi in PlayableItem,
        on: pi.container_id == e.id and pi.container_type == :episode,
        join: w in WatchedFile,
        on: w.playable_item_id == pi.id,
        where: s.tv_series_id == ^tv_series_id and w.file_path == ^file_path,
        limit: 1
      )
    )
  end

  @doc """
  The episode under `tv_series_id` at `(season_number, episode_number)`,
  or `nil`. For callers holding the numbers rather than a path.
  """
  @spec find_by_season_episode(Ecto.UUID.t(), integer(), integer()) :: Episode.t() | nil
  def find_by_season_episode(tv_series_id, season_number, episode_number)
      when is_binary(tv_series_id) and is_integer(season_number) and is_integer(episode_number) do
    Repo.one(
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        where:
          s.tv_series_id == ^tv_series_id and
            s.season_number == ^season_number and
            e.episode_number == ^episode_number,
        limit: 1
      )
    )
  end
end
