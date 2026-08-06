defmodule MediaCentaur.Library.Seasons do
  @moduledoc """
  Records and lookup for `Season` — the grouping between a `TVSeries` and
  its `Episode`s.

  A Season is identified within its series by `season_number`, and that
  pair carries a unique index, which is what makes `find_or_create/1`
  safe under concurrent ingest of the same series.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{Season, Writes}
  alias MediaCentaur.Repo

  @doc "Every `Season` row."
  @spec list_all() :: [Season.t()]
  def list_all, do: Repo.all(Season)

  @doc "Fetches a `Season` by id."
  @spec fetch(Ecto.UUID.t()) :: {:ok, Season.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(Season, id) do
      nil -> {:error, :not_found}
      season -> {:ok, season}
    end
  end

  @doc "Inserts a `Season`."
  @spec create(map()) :: {:ok, Season.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: Repo.insert(Season.create_changeset(attrs))

  @doc "Bang variant of `create/1` — raises on changeset error."
  @spec create!(map()) :: Season.t()
  def create!(attrs), do: Repo.bang!(create(attrs))

  @doc "Deletes a `Season`."
  @spec destroy(Season.t()) :: {:ok, Season.t()} | {:error, Ecto.Changeset.t()}
  def destroy(season), do: Repo.delete(season)

  @doc "As `destroy/1`, raising on failure and returning `:ok`."
  @spec destroy!(Season.t()) :: :ok
  def destroy!(season), do: Writes.destroy!(season)

  @doc """
  Finds the season at `(tv_series_id, season_number)` or creates it.
  Recovers from a concurrent insert via the unique index on that pair.
  """
  @spec find_or_create(map()) :: {:ok, Season.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create(attrs) do
    Writes.find_or_insert_by(
      Season,
      [
        tv_series_id: Writes.attr(attrs, :tv_series_id),
        season_number: Writes.attr(attrs, :season_number)
      ],
      attrs
    )
  end

  @doc "Every season of a TV series."
  @spec list_for_tv_series(Ecto.UUID.t()) :: [Season.t()]
  def list_for_tv_series(tv_series_id),
    do: Repo.all(from(s in Season, where: s.tv_series_id == ^tv_series_id))
end
