defmodule MediaCentaur.Acquisition.Artwork do
  @moduledoc """
  Display artwork for acquisition surfaces (the pursuit modal hero):
  backdrop + logo URLs for a TMDB identity that may not be in the
  library yet.

  Local-first resolution — never a hot-link:

  1. A release-tracking item for the same identity already carries
     cached files (`backdrop_path` / `logo_path`).
  2. The shared tracking image store has files on disk for this
     `tmdb_id` (a previous `ensure/2`, or tracking that has since been
     removed — the store is keyed by tmdb_id, not by item).

  `ensure/2` fills the store when both miss: one TMDB detail fetch
  (images ride along via `append_to_response`) and the standard
  `ImageStore` downloads — the very cache release tracking uses, so
  tracking the title later finds the artwork already in place. All
  failures degrade to `resolve/2`'s nils; callers fall back to the
  synthetic gradient + logotype treatment (UIDR-014).
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.ImageStore
  alias MediaCentaur.TMDB.Client

  @type urls :: %{backdrop_url: String.t() | nil, logo_url: String.t() | nil}

  @doc "Local-only lookup — DB + disk, safe on any read path."
  @spec resolve(String.t() | integer(), String.t() | atom()) :: urls()
  def resolve(tmdb_id, tmdb_type) do
    case normalize_id(tmdb_id) do
      nil ->
        %{backdrop_url: nil, logo_url: nil}

      id ->
        item = ReleaseTracking.get_item_by_tmdb(id, media_type(tmdb_type))

        %{
          backdrop_url: item_url(item, :backdrop_path) || store_url(:backdrop, id),
          logo_url: item_url(item, :logo_path) || store_url(:logo, id)
        }
    end
  end

  @doc """
  `resolve/2`, fetching + caching what's missing first. Does network —
  callers run it async (the pursuit modal uses `start_async`).
  """
  @spec ensure(String.t() | integer(), String.t() | atom()) :: urls()
  def ensure(tmdb_id, tmdb_type) do
    with id when not is_nil(id) <- normalize_id(tmdb_id),
         %{backdrop_url: backdrop, logo_url: logo} when is_nil(backdrop) or is_nil(logo) <-
           resolve(id, tmdb_type) do
      fetch_into_store(id, tmdb_type)
      resolve(id, tmdb_type)
    else
      nil -> %{backdrop_url: nil, logo_url: nil}
      %{} = resolved -> resolved
    end
  end

  defp fetch_into_store(id, tmdb_type) do
    case detail(id, tmdb_type) do
      {:ok, data} ->
        if path = data["backdrop_path"], do: ImageStore.download_backdrop(id, path)
        if path = logo_path(data), do: ImageStore.download_logo(id, path)
        :ok

      {:error, reason} ->
        Log.warning(:acquisition, "artwork fetch failed for tmdb:#{id} — #{inspect(reason)}")
        :error
    end
  end

  defp detail(id, type) do
    case media_type(type) do
      :movie -> Client.get_movie(id)
      :tv_series -> Client.get_tv(id)
    end
  end

  # Same pick as the pipeline mapper: English logo first, any second.
  defp logo_path(data) do
    logos = get_in(data, ["images", "logos"]) || []
    logo = Enum.find(logos, &(&1["iso_639_1"] == "en")) || List.first(logos)
    logo && logo["file_path"]
  end

  defp item_url(nil, _field), do: nil

  defp item_url(item, field) do
    case Map.get(item, field) do
      path when is_binary(path) -> MediaCentaur.Library.Image.web_path(path)
      _missing -> nil
    end
  end

  defp store_url(role, id) do
    if File.exists?(ImageStore.on_disk_path(role, id)) do
      MediaCentaur.Library.Image.web_path(ImageStore.relative_path(role, id))
    end
  end

  defp media_type(type) when type in [:movie, "movie"], do: :movie
  defp media_type(type) when type in [:tv, "tv", :tv_series, "tv_series"], do: :tv_series

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp normalize_id(_id), do: nil
end
