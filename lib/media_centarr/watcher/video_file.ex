defmodule MediaCentarr.Watcher.VideoFile do
  @moduledoc """
  Canonical list of video file extensions the watcher recognises, plus the
  matching predicate. Centralised so adding a new extension is a one-file
  change instead of a grep-and-edit across the watcher subsystem.
  """

  @extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .ts .m2ts)

  @doc "Returns the canonical lowercase list of recognised video extensions."
  @spec extensions() :: [String.t()]
  def extensions, do: @extensions

  @doc "Returns true when `path` ends in a recognised video extension (case-insensitive)."
  @spec video?(String.t()) :: boolean()
  def video?(path) when is_binary(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @extensions
  end
end
