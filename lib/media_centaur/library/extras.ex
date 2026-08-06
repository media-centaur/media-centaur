defmodule MediaCentaur.Library.Extras do
  @moduledoc """
  Records and lookup for `Extra` — bonus features (featurettes,
  behind-the-scenes, deleted scenes) owned by a container.

  An Extra hangs off an `(owner_type, owner_id)` pair rather than a
  per-type FK, so the same table serves movies, series, collections and
  seasons; `Library.OwnerRef` translates the per-type shorthand callers
  still use. Its file lives in `Library.Files` as an `ExtraFile` — an
  Extra is a metadata-and-file pair, not a `PlayableItem`.

  `name` has exactly one update path (`rename/2`), because the name is
  derived from the file path by the re-derive sweep rather than authored.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{Extra, OwnerRef, Writes}
  alias MediaCentaur.Repo

  @doc "Fetches an `Extra` by id."
  @spec fetch(Ecto.UUID.t()) :: {:ok, Extra.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(Extra, id) do
      nil -> {:error, :not_found}
      extra -> {:ok, extra}
    end
  end

  @doc "Inserts an `Extra`, accepting either owner shape."
  @spec create(map()) :: {:ok, Extra.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: Repo.insert(Extra.create_changeset(OwnerRef.normalise(attrs, :extra)))

  @doc "Bang variant of `create/1` — raises on changeset error."
  @spec create!(map()) :: Extra.t()
  def create!(attrs), do: Repo.bang!(create(attrs))

  @doc """
  Finds an extra by its `(owner_type, owner_id, content_url)` tuple or
  creates it. Lets ingest upsert extras without re-discovering the same
  bonus feature on every Watcher event.
  """
  @spec find_or_create_by_owner(map()) :: {:ok, Extra.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_by_owner(attrs) do
    Writes.find_or_insert_by(
      Extra,
      [
        owner_type: Writes.attr(attrs, :owner_type),
        owner_id: Writes.attr(attrs, :owner_id),
        content_url: Writes.attr(attrs, :content_url)
      ],
      attrs
    )
  end

  @doc """
  Extras owned by the given UUID, whatever the owner type — the
  `(owner_type, owner_id)` discriminator makes the type irrelevant to the
  lookup when the id is already known to be unique.
  """
  @spec list_for_owner(Ecto.UUID.t()) :: [Extra.t()]
  def list_for_owner(owner_id), do: Repo.all(from(x in Extra, where: x.owner_id == ^owner_id))

  @doc "Extras owned by a specific season."
  @spec list_for_season(Ecto.UUID.t()) :: [Extra.t()]
  def list_for_season(season_id),
    do: Repo.all(from(x in Extra, where: x.owner_type == :season and x.owner_id == ^season_id))

  @doc """
  Re-derives an extra's display name — the only update path for
  `Extra.name`. Rejects a blank value. Used by the re-derive sweep
  (`Pipeline.ExtraRederive`).
  """
  @spec rename(Extra.t(), String.t() | nil) :: {:ok, Extra.t()} | {:error, Ecto.Changeset.t()}
  def rename(%Extra{} = extra, name) do
    extra
    |> Extra.update_name_changeset(%{name: name})
    |> Repo.update()
  end

  @doc """
  Extras whose `name` can be re-derived from a file path — those carrying
  a `content_url`. Drives the re-derive sweep.
  """
  @spec list_rederivable() :: [Extra.t()]
  def list_rederivable, do: Repo.all(from(e in Extra, where: not is_nil(e.content_url)))

  @doc """
  Count of extras with a blank or missing `name` — the visible symptom
  the re-derive sweep repairs; drives the Maintenance button's
  prominence.
  """
  @spec count_blank_names() :: non_neg_integer()
  def count_blank_names,
    do: Repo.aggregate(from(e in Extra, where: is_nil(e.name) or e.name == ""), :count)
end
