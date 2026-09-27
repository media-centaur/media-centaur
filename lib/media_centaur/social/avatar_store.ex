defmodule MediaCentaur.Social.AvatarStore do
  @moduledoc """
  Where a known key's avatar bytes live: `{data_dir}/images/social/<pubkey>.<ext>`,
  the social instance of the data-dir artwork idiom (`TmdbArtwork`,
  `Apps.Artwork`): disk is the ledger, the URL is resolved from disk at
  read time and carries the profile's wire time as `?v=`, so a replaced
  avatar mints a new URL and an unchanged one stays immutable in the
  browser. Served by `MediaCentaurWeb.Plugs.ImageServer`; the URL never
  carries `?w=`, since a tile paints the master as it is. Written by
  `Social` when a profile is stored, removed when the profile loses its
  avatar or the key is forgotten. A reader never decodes what it stores.
  """

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Social.Profile.Translation

  @subdir "images/social"

  @doc "The data-dir-relative path for a key's avatar of `type`."
  @spec relative_path(String.t(), String.t()) :: String.t()
  def relative_path(pubkey, type),
    do: Path.join(@subdir, pubkey <> "." <> Translation.avatar_extension(type))

  @doc "Writes the bytes, replacing any file of another type for the key."
  @spec write(String.t(), String.t(), binary()) :: :ok
  def write(pubkey, type, bytes) when is_binary(pubkey) and is_binary(type) and is_binary(bytes) do
    :ok = delete(pubkey)
    dest = ImageFiles.on_disk_path(relative_path(pubkey, type))
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, bytes)
  end

  @doc "The stored bytes, or `{:error, :enoent}`."
  @spec read(String.t(), String.t()) :: {:ok, binary()} | {:error, File.posix()}
  def read(pubkey, type), do: File.read(ImageFiles.on_disk_path(relative_path(pubkey, type)))

  @doc "Removes every avatar file for the key. Idempotent."
  @spec delete(String.t()) :: :ok
  def delete(pubkey) when is_binary(pubkey) do
    dir = ImageFiles.on_disk_path(@subdir)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, pubkey <> "."))
        |> Enum.each(&File.rm!(Path.join(dir, &1)))

      {:error, _no_dir} ->
        :ok
    end

    :ok
  end

  @doc "The versioned URL for the key's avatar, or nil when there is no type or no file."
  @spec url(String.t(), String.t() | nil, non_neg_integer()) :: String.t() | nil
  def url(_pubkey, nil, _version), do: nil

  def url(pubkey, type, version) do
    relative = relative_path(pubkey, type)
    if File.regular?(ImageFiles.on_disk_path(relative)), do: ImageFiles.web_path(relative, version)
  end
end
