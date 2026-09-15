defmodule MediaCentaurWeb.SettingsLive.IgnoreRulesLogic do
  @moduledoc """
  Validation for the Settings ignore-rules card, and the inline error
  copy for each rejection.

  ADR-030: the decision is pure and unit-tested; the LiveView supplies
  the filesystem facts (`:exists?`, `:readable?`) and the database
  facts (`:media_dirs`, `:linked_paths`) it has already read.

  Whether a rule would cover a file is decided by
  `Watcher.IgnoreRules.matching_rule/2` — the same matching used by the
  watcher, the scan and the retraction pass. Re-deriving it here with a
  SQL `LIKE` or a hand-rolled prefix check would put a fourth
  implementation of rule matching in the codebase, which is the thing
  this card's own feature set out to remove.

  ## Why the invariant is enforced here

  `Watcher.IgnoreRules` holds the invariant that no linked file's path
  may sit under an ignore rule. This module is the one place a rule is
  created, so it is the only place the invariant can be violated.
  Letting a rule through that covers imported titles would stop their
  `FilePresence` rows being re-stamped by the scan, and
  `Library.AbsenceSweeper` would purge them — running the deletion
  cascade — once the absence TTL elapsed, for files still sitting on
  disk.
  """

  alias MediaCentaur.Watcher.IgnoreRules

  @type context :: %{
          required(:existing) => [String.t()],
          required(:linked_paths) => [String.t()],
          optional(:media_dirs) => [String.t()],
          optional(:exists?) => boolean(),
          optional(:readable?) => boolean()
        }

  @type rejection ::
          :empty
          | :relative
          | :duplicate
          | :not_a_directory
          | :not_readable
          | :outside_media_dirs
          | {:has_imported_files, pos_integer()}

  @doc """
  Validates a path rule — an absolute directory whose subtree is not
  library content.

  Checks run cheapest-first and stop at the first rejection, so a
  half-typed path reports its shape problem rather than a confusing
  downstream one.
  """
  @spec validate_path_rule(String.t() | nil, context()) :: {:ok, String.t()} | {:error, rejection()}
  def validate_path_rule(input, context) do
    trimmed = String.trim(input || "")

    cond do
      trimmed == "" -> {:error, :empty}
      Path.type(trimmed) != :absolute -> {:error, :relative}
      trimmed in context.existing -> {:error, :duplicate}
      not Map.get(context, :exists?, true) -> {:error, :not_a_directory}
      not Map.get(context, :readable?, true) -> {:error, :not_readable}
      not inside_media_dir?(trimmed, context) -> {:error, :outside_media_dirs}
      true -> imported_files_check(trimmed, IgnoreRules.new([trimmed], []), context)
    end
  end

  @doc """
  Validates a name rule — a directory name whose contents are not
  library content, wherever that name appears.
  """
  @spec validate_name_rule(String.t() | nil, context()) :: {:ok, String.t()} | {:error, rejection()}
  def validate_name_rule(input, context) do
    trimmed = String.trim(input || "")

    cond do
      trimmed == "" ->
        {:error, :empty}

      Enum.any?(context.existing, &(String.downcase(&1) == String.downcase(trimmed))) ->
        {:error, :duplicate}

      true ->
        imported_files_check(trimmed, IgnoreRules.new([], [trimmed]), context)
    end
  end

  @doc """
  The inline error for a rejection, or `nil` where the field is simply
  incomplete and an error would be noise.
  """
  @spec error_message(rejection() | nil, :path | :name) :: String.t() | nil
  def error_message(nil, _kind), do: nil
  def error_message(:empty, _kind), do: nil
  def error_message(:relative, _kind), do: "Must be an absolute path (starts with /)."
  def error_message(:duplicate, _kind), do: "Already in the list."
  def error_message(:not_a_directory, _kind), do: "Path does not exist or is not a directory."
  def error_message(:not_readable, _kind), do: "Path exists but isn't readable by the app."

  def error_message(:outside_media_dirs, _kind),
    do: "Only paths inside a media directory can be ignored."

  def error_message({:has_imported_files, count}, :path) do
    "This path holds #{files(count)} already in your library. " <>
      "Remove those titles first, or choose a narrower path."
  end

  def error_message({:has_imported_files, count}, :name) do
    "Folders with this name hold #{files(count)} already in your library. " <>
      "Remove those titles first."
  end

  defp imported_files_check(trimmed, rules, context) do
    case Enum.count(context.linked_paths, &IgnoreRules.ignored?(&1, rules)) do
      0 -> {:ok, trimmed}
      count -> {:error, {:has_imported_files, count}}
    end
  end

  # No media directories configured yet: there is nothing to be inside,
  # so shape validation is all this card can offer.
  defp inside_media_dir?(_path, %{media_dirs: []}), do: true

  defp inside_media_dir?(path, %{media_dirs: media_dirs}) do
    Enum.any?(media_dirs, fn dir -> path == dir or String.starts_with?(path, dir <> "/") end)
  end

  defp inside_media_dir?(_path, _context), do: true

  defp files(1), do: "1 file"
  defp files(count), do: "#{count} files"
end
