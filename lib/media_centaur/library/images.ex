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

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.Image

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Repo

  @doc "Every `Image` row."
  @spec list_all() :: [Image.t()]
  def list_all, do: Repo.all(Image)

  @doc """
  The rows with `present?` set from whether each file is on disk right now
  (`ImageCache.resolve_path/1`, the lookup the image server serves from).
  The read models call this when they take image rows in, so what they
  project is what can be served; a row whose file is missing keeps its
  place and loses only its artwork.
  """
  @spec with_presence([Image.t()] | nil) :: [Image.t()]
  def with_presence(nil), do: []

  def with_presence(images) when is_list(images) do
    Enum.map(images, fn %Image{content_url: content_url} = image ->
      %{image | present?: is_binary(content_url) and ImageCache.resolve_path(content_url) != nil}
    end)
  end

  @doc """
  The image server reports a library artwork path it could not serve.

  Reporting is not deciding: the read models decide what artwork a page
  shows, and this is the fact they need to re-decide — a row whose file
  vanished after it landed. The owner's container (a series for an
  episode thumb) is broadcast as changed, every projection re-checks the
  file, and the page swaps the broken image for its placeholder. Paths
  outside the `<owner_id>/<role>.<ext>` layout, and rows the library does
  not have, are ignored.
  """
  @spec report_missing_file(String.t()) :: :ok
  def report_missing_file(relative_path) when is_binary(relative_path) do
    with [owner_id, _file] <- String.split(relative_path, "/"),
         {:ok, _uuid} <- Ecto.UUID.cast(owner_id),
         %Image{owner_type: owner_type} <-
           Repo.one(
             from(i in Image,
               where: i.owner_id == ^owner_id and i.content_url == ^relative_path,
               limit: 1
             )
           ) do
      MediaCentaur.Library.Helpers.broadcast_entities_changed([container_id(owner_type, owner_id)])
    else
      _ -> :ok
    end
  end

  defp container_id(:episode, episode_id) do
    Repo.one(
      from(e in MediaCentaur.Library.Episode,
        join: s in assoc(e, :season),
        where: e.id == ^episode_id,
        select: s.tv_series_id
      )
    ) || episode_id
  end

  defp container_id(_owner_type, owner_id), do: owner_id

  @doc "Inserts an `Image` for an `(owner_type, owner_id)` owner."
  @spec create(map()) :: {:ok, Image.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: Repo.insert(Image.create_changeset(attrs))

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

    Map.new(rows, fn {entity_id, content_url} -> {entity_id, ImageFiles.web_path(content_url)} end)
  end

  defp delete_replaced_file(attrs, conflict_target) when is_list(conflict_target) do
    lookup = Enum.map(conflict_target, fn key -> {key, Map.get(attrs, key)} end)

    with false <- Enum.any?(lookup, fn {_key, value} -> is_nil(value) end),
         %Image{content_url: old_url} when is_binary(old_url) <- Repo.get_by(Image, lookup),
         new_url when new_url != old_url <- Map.get(attrs, :content_url),
         old_path when is_binary(old_path) <- ImageCache.resolve_path(old_url) do
      File.rm(old_path)
    else
      _no_replaced_file -> :ok
    end
  end
end
