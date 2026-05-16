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
    resolver
    |> rows_with_presence()
    |> Enum.flat_map(fn
      {image, false} -> [annotate(image)]
      {_image, true} -> []
    end)
  end

  @doc """
  Returns the count of missing image files. Walks the same set as
  `list_missing/1` — keep in mind this runs a disk check per image row.
  """
  @spec count_missing(resolver()) :: non_neg_integer()
  def count_missing(resolver \\ &Config.resolve_image_path/1) do
    resolver
    |> rows_with_presence()
    |> Enum.count(fn {_image, present?} -> not present? end)
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
    Enum.reduce(
      rows_with_presence(resolver),
      %{total: 0, missing: 0, by_role: %{}},
      fn
        {_image, true}, acc ->
          %{acc | total: acc.total + 1}

        {image, false}, acc ->
          %{
            total: acc.total + 1,
            missing: acc.missing + 1,
            by_role: Map.update(acc.by_role, image.role, 1, &(&1 + 1))
          }
      end
    )
  end

  # Single fetch + parallel disk-presence check. The check is per-file
  # `File.exists?` (via the resolver), embarrassingly parallel — running
  # serially turned a ~10k-image health summary into a sequential disk-stat
  # walk. `ordered: false` lets fast checks land first; the callers don't
  # depend on order.
  defp rows_with_presence(resolver) do
    rows =
      Image
      |> where([i], not is_nil(i.content_url))
      |> Repo.all()

    rows
    |> Task.async_stream(
      fn image -> {image, resolver.(image.content_url) != nil} end,
      max_concurrency: 16,
      ordered: false,
      timeout: 30_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp annotate(%Image{owner_id: entity_id, owner_type: entity_type} = image) do
    %{image: image, entity_id: entity_id, entity_type: entity_type}
  end
end
