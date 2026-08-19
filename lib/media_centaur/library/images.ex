defmodule MediaCentaur.Library.Images do
  @moduledoc """
  Artwork rows — posters, backdrops, logos, episode stills — hanging off
  a library entity via the `(owner_type, owner_id)` pair.

  Image files on disk have deterministic paths
  (`{owner_id}/{role}.{extension}`), so a re-download normally overwrites
  in place and `upsert/2` is the ordinary write. The exception the upsert
  has to handle is an **extension change** (poster.jpg → poster.png):
  the row's `content_url` is re-pointed, and without intervention the old
  file would linger on disk forever. `upsert/2` removes it while the old
  path is still readable from the row about to be replaced.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{Image, OwnerRef}
  alias MediaCentaur.Repo

  @doc "Every `Image` row."
  @spec list_all() :: [Image.t()]
  def list_all, do: Repo.all(Image)

  @doc "Inserts an `Image`, accepting either owner shape."
  @spec create(map()) :: {:ok, Image.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: Repo.insert(Image.create_changeset(OwnerRef.normalise(attrs, :image)))

  @doc "Bang variant of `create/1` — raises on changeset error."
  @spec create!(map()) :: Image.t()
  def create!(attrs), do: Repo.bang!(create(attrs))

  @doc """
  Inserts an `Image`, replacing the row at `conflict_target` if it
  already exists, and deleting the previous file when the replacement
  changes its path.
  """
  @spec upsert(map(), [atom()]) :: {:ok, Image.t()} | {:error, Ecto.Changeset.t()}
  def upsert(attrs, conflict_target) do
    attrs = OwnerRef.normalise(attrs, :image)
    delete_replaced_file(attrs, conflict_target)

    Repo.insert(Image.create_changeset(attrs),
      on_conflict: {:replace, [:content_url, :extension, :updated_at]},
      conflict_target: conflict_target
    )
  end

  @doc """
  The `Image` rows owned by `(owner_type, owner_id)`.

  Used by the inbound link-time artwork backfill to learn which roles a
  container is already missing.
  """
  @spec list_for_owner(atom(), Ecto.UUID.t()) :: [Image.t()]
  def list_for_owner(owner_type, owner_id) when is_atom(owner_type) and is_binary(owner_id) do
    Repo.all(from(i in Image, where: i.owner_type == ^owner_type and i.owner_id == ^owner_id))
  end

  @doc """
  Resolves logo URLs for `{media_type, entity_id}` pairs in one query,
  returning `%{entity_id => web_path}` for any pair whose entity has a
  logo. Entities without one are simply absent.

  Used by views rendering tracked-show cards (Upcoming, Coming Up) so
  they can fall back from typography to the show logo without per-card
  lookups.
  """
  @spec logo_urls_for_entities([{:movie | :tv_series, Ecto.UUID.t()}]) :: %{
          Ecto.UUID.t() => String.t()
        }
  def logo_urls_for_entities([]), do: %{}

  def logo_urls_for_entities(pairs) when is_list(pairs) do
    movie_ids = for {:movie, id} <- pairs, is_binary(id), do: id
    tv_ids = for {:tv_series, id} <- pairs, is_binary(id), do: id

    rows =
      Repo.all(
        from(i in Image,
          where:
            i.role == "logo" and
              ((i.owner_type == :movie and i.owner_id in ^movie_ids) or
                 (i.owner_type == :tv_series and i.owner_id in ^tv_ids)),
          select: {i.owner_id, i.content_url}
        )
      )

    Map.new(rows, fn {entity_id, content_url} -> {entity_id, Image.web_path(content_url)} end)
  end

  defp delete_replaced_file(attrs, conflict_target) when is_list(conflict_target) do
    lookup = Enum.map(conflict_target, fn key -> {key, Map.get(attrs, key)} end)

    with false <- Enum.any?(lookup, fn {_key, value} -> is_nil(value) end),
         %Image{content_url: old_url} when is_binary(old_url) <- Repo.get_by(Image, lookup),
         new_url when new_url != old_url <- Map.get(attrs, :content_url),
         old_path when is_binary(old_path) <- MediaCentaur.Settings.Config.resolve_image_path(old_url) do
      File.rm(old_path)
    else
      _no_replaced_file -> :ok
    end
  end
end
