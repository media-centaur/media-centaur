defmodule MediaCentaur.Profiles.PictureStore do
  @moduledoc """
  Where a profile's picture lives: `{data_dir}/images/profiles/<id>.webp`,
  one 256×256 WebP master per profile, the data-dir picture idiom over
  `ImageFiles`' primitives (`Social.AvatarStore` is the same idiom keyed
  by pubkey). Disk is the ledger; the URL carries `picture_at` as `?v=`
  so a replaced picture mints a new URL and an unchanged one stays
  immutable in the browser.
  """

  alias MediaCentaur.ImageFiles

  @subdir "images/profiles"
  @side 256
  @max_bytes 262_144

  @doc "The master's shape, for `ImageFiles.webp_master/4`."
  @spec master_size() :: {pos_integer(), pos_integer()}
  def master_size, do: {@side, @side}

  @doc "The master's byte cap, for `ImageFiles.webp_master/4`: generous, since nothing goes on the wire."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The data-dir-relative path of a profile's picture."
  @spec relative_path(Ecto.UUID.t()) :: String.t()
  def relative_path(id), do: Path.join(@subdir, id <> ".webp")

  @spec write(Ecto.UUID.t(), binary()) :: :ok
  def write(id, bytes), do: ImageFiles.write_file(relative_path(id), bytes)

  @spec delete(Ecto.UUID.t()) :: :ok
  def delete(id), do: ImageFiles.remove_file(relative_path(id))

  @doc "The versioned URL, or nil when the file is not on disk."
  @spec url(Ecto.UUID.t(), non_neg_integer()) :: String.t() | nil
  def url(id, version), do: ImageFiles.url_if_present(relative_path(id), version)
end
