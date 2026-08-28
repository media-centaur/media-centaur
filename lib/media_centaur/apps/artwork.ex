defmodule MediaCentaur.Apps.Artwork do
  @moduledoc """
  App artwork cache — the Apps instance of the app-wide non-library
  artwork idiom (see `MediaCentaur.TmdbArtwork`): identity-keyed
  directory under `data_dir`, disk as the ledger, URLs resolved from
  disk at read time, served by `MediaCentaurWeb.Plugs.ImageServer` with
  the `?w=` derivative ladder.

  Layout: `{data_dir}/images/apps/{app_id}/banner.jpg` (460×215 Steam
  header — the card art) and `poster.jpg` (600×900 capsule — cached at
  add time for a future poster view). No TTL, no holds: app art is
  permanent while its app exists and is deleted synchronously with it.
  """

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Settings.Config

  @subdir "images/apps"
  @filenames %{banner: "banner.jpg", poster: "poster.jpg"}

  @type role :: :banner | :poster

  @doc "The data_dir-relative path for a role — what ImageServer serves."
  @spec relative_path(role(), String.t()) :: String.t()
  def relative_path(role, app_id) do
    Path.join([@subdir, app_id, Map.fetch!(@filenames, role)])
  end

  @doc "The on-disk absolute path for a role, whether or not the file exists."
  @spec on_disk_path(role(), String.t()) :: String.t()
  def on_disk_path(role, app_id), do: Path.join(data_dir(), relative_path(role, app_id))

  @doc "Web URLs for the roles that exist on disk; missing roles are nil."
  @spec urls(String.t()) :: %{banner_url: String.t() | nil, poster_url: String.t() | nil}
  def urls(app_id) do
    %{banner_url: role_url(:banner, app_id), poster_url: role_url(:poster, app_id)}
  end

  @doc "Copies a local file (e.g. Steam's librarycache art) into the cache."
  @spec store_file(role(), String.t(), String.t()) :: :ok | {:error, term()}
  def store_file(role, app_id, source_path) do
    dest = on_disk_path(role, app_id)
    File.mkdir_p!(Path.dirname(dest))

    case File.cp(source_path, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Downloads a URL into the cache via the shared ImageFiles service."
  @spec store_url(role(), String.t(), String.t()) :: :ok | {:error, term()}
  def store_url(role, app_id, url) do
    case ImageFiles.download_raw(url, on_disk_path(role, app_id)) do
      {:ok, _path} -> :ok
      {:error, _category, reason} -> {:error, reason}
    end
  end

  @doc "Removes the app's art directory and any derivatives. Idempotent."
  @spec delete(String.t()) :: :ok
  def delete(app_id) do
    dir = Path.join([data_dir(), @subdir, app_id])

    case File.ls(dir) do
      {:ok, files} -> Enum.each(files, &ImageFiles.purge_derivatives_for(Path.join(dir, &1)))
      {:error, _reason} -> :ok
    end

    File.rm_rf(dir)
    :ok
  end

  defp role_url(role, app_id) do
    if File.exists?(on_disk_path(role, app_id)) do
      Image.web_path(relative_path(role, app_id))
    end
  end

  defp data_dir, do: Config.get(:data_dir) || "data"
end
