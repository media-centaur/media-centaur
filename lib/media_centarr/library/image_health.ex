defmodule MediaCentarr.Library.ImageHealth do
  @moduledoc """
  Detects `library_images` rows whose files are missing from disk.

  An image is "missing" when its `content_url` is populated but no file
  exists at the resolved path in any configured watch directory. Rows
  with `content_url = nil` are excluded — those are mid-refresh and the
  pipeline is already responsible for filling them.
  """
  import Ecto.Query

  alias MediaCentarr.Config
  alias MediaCentarr.Library.Image
  alias MediaCentarr.Repo

  @type entity_type :: :movie | :episode | :tv_series | :movie_series | :video_object

  @type missing_entry :: %{
          image: %Image{},
          entity_id: Ecto.UUID.t(),
          entity_type: entity_type()
        }

  @type resolver :: (String.t() | nil -> String.t() | nil)

  @doc """
  Returns image rows whose files are absent on disk, each annotated with
  the owning entity's id and type.
  """
  @spec list_missing(resolver()) :: [missing_entry()]
  def list_missing(resolver \\ &Config.resolve_image_path/1) do
    Image
    |> where([i], not is_nil(i.content_url))
    |> Repo.all()
    |> Enum.filter(fn image -> resolver.(image.content_url) == nil end)
    |> Enum.map(&annotate/1)
  end

  @doc """
  Returns the count of missing image files. Walks the same set as
  `list_missing/1` — keep in mind this runs a disk check per image row.
  """
  @spec count_missing(resolver()) :: non_neg_integer()
  def count_missing(resolver \\ &Config.resolve_image_path/1) do
    resolver |> list_missing() |> length()
  end

  @doc """
  Returns `%{total: n, missing: n, by_role: %{role => missing_count}}`.

  `total` counts image rows with a non-nil content_url. `by_role` only
  includes roles that have at least one missing file.
  """
  @spec summary(resolver()) :: %{
          total: non_neg_integer(),
          missing: non_neg_integer(),
          by_role: %{String.t() => non_neg_integer()}
        }
  def summary(resolver \\ &Config.resolve_image_path/1) do
    rows =
      Image
      |> where([i], not is_nil(i.content_url))
      |> Repo.all()

    missing = Enum.filter(rows, fn image -> resolver.(image.content_url) == nil end)

    by_role =
      missing
      |> Enum.group_by(& &1.role)
      |> Map.new(fn {role, items} -> {role, length(items)} end)

    %{total: length(rows), missing: length(missing), by_role: by_role}
  end

  defp annotate(%Image{} = image) do
    {entity_id, entity_type} = derive_entity(image)
    %{image: image, entity_id: entity_id, entity_type: entity_type}
  end

  defp derive_entity(%Image{movie_id: id}) when not is_nil(id), do: {id, :movie}
  defp derive_entity(%Image{episode_id: id}) when not is_nil(id), do: {id, :episode}
  defp derive_entity(%Image{tv_series_id: id}) when not is_nil(id), do: {id, :tv_series}
  defp derive_entity(%Image{movie_series_id: id}) when not is_nil(id), do: {id, :movie_series}
  defp derive_entity(%Image{video_object_id: id}) when not is_nil(id), do: {id, :video_object}
end
