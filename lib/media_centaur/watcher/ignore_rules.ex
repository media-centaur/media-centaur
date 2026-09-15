defmodule MediaCentaur.Watcher.IgnoreRules do
  @moduledoc """
  Decides whether a path is library content.

  Every boundary where a path enters the library asks this module, and
  they all ask the same question: the inotify event filter, the
  directory scan, and the recovery re-emit
  (`Watcher.Rescan.rescan_unlinked/0`). Before this module there were
  three independent answers and a fourth caller that never asked — a
  directory the user had excluded kept being re-fed to the pipeline on
  every boot, costing two TMDB searches per file that could never
  resolve. See `docs/plans/2026-09-15-ignore-rules-unification.md`.

  ## The two rule kinds

  An **ignore rule** states that some part of a media directory is not
  library content. It comes in two matching modes, the same distinction
  gitignore draws between patterns with and without a slash:

    * **path rule** — an absolute path (config `exclude_dirs`). Matches
      that path and everything under it. Matched with `dir <> "/"` so
      `/foo` never matches `/foobar`.
    * **name rule** — a directory *name* (config `skip_dirs`), matched
      case-insensitively wherever it appears. A *file* named `Sample`
      is never ignored; a *directory* named `Sample` is, along with
      everything under it.

  `load/1` adds two rules the user does not configure: `.staging` as a
  name rule — the download-client assembly contract (prowlarr-stack's
  SABnzbd verifies, repairs and unpacks there, then renames the
  finished job out), so anything inside is in-progress by construction
  — and the media directory's own image-cache and image-staging roots
  as path rules.

  ## Invariant

  > No linked file's path may sit under an ignore rule.

  Enforced where a rule is created (Settings validation), and
  maintained thereafter by construction: nothing imports from an
  ignored path, and a file moved into an ignored folder leaves the
  library through the normal absence path, which is the right reading
  of that move. Without it, ignoring a directory that holds imported
  titles would starve their `FilePresence` rows of the scan's
  `last_seen_at` refresh and `Library.AbsenceSweeper` would purge them
  — and run the deletion cascade — for files still sitting on disk.

  ## Why a struct

  The rule set is precompiled once (per media directory, cached on the
  watcher's GenServer state) so a per-path check doesn't rebuild
  `dir <> "/"` or downcase a name on every inotify event. Every
  predicate pattern-matches `%IgnoreRules{}`, so a stray raw-list
  caller crashes at the function boundary with a stack trace pointing
  at the caller rather than buried inside an anonymous fn.
  """

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Watcher.VideoFile

  # Always applied, however the rule set was built — a `new/2` caller
  # passing an empty name list still gets `.staging` invisibility.
  # Downcased like every other name rule, so `.STAGING` matches too.
  @reserved_name_rules [".staging"]

  @enforce_keys [:path_rules, :name_rules]
  defstruct [:path_rules, :name_rules]

  @type t :: %__MODULE__{
          path_rules: [{String.t(), String.t()}],
          name_rules: [String.t()]
        }

  @doc "The name rules applied regardless of configuration."
  @spec reserved_name_rules() :: [String.t()]
  def reserved_name_rules, do: @reserved_name_rules

  @doc """
  Builds the rule set for `media_dir` from configuration.

  Two config reads plus the derived image roots — cheap enough to call
  per scan, cached on watcher state only to keep it off the inotify
  event path.
  """
  @spec load(String.t()) :: t()
  def load(media_dir) do
    images_dir = ImageCache.dir_for(media_dir)
    staging_dir = ImageCache.staging_dir_for(media_dir)

    # The derived roots are filtered to this media directory because
    # they are computed from it; a configured path rule is kept as-is,
    # since one pointing elsewhere simply never matches. Rejecting a
    # rule outside every media directory is Settings' job, at the point
    # the rule is created.
    derived = Enum.filter([images_dir, staging_dir], &under?(&1, media_dir))

    new((Config.get(:exclude_dirs) || []) ++ derived, Config.get(:skip_dirs) || [])
  end

  @doc """
  Pure constructor. `path_rules` are absolute paths, `name_rules` are
  directory names in any case; the reserved name rules are added for
  you.
  """
  @spec new([String.t()], [String.t()]) :: t()
  def new(path_rules, name_rules) when is_list(path_rules) and is_list(name_rules) do
    %__MODULE__{
      path_rules: Enum.map(Enum.uniq(path_rules), fn dir -> {dir, dir <> "/"} end),
      name_rules: Enum.uniq(Enum.map(name_rules, &String.downcase/1) ++ @reserved_name_rules)
    }
  end

  @doc """
  The admission predicate: `path` is a recognised video file and no
  rule ignores it.

  This is the one question every entry boundary asks. `ignored_dir?/2`
  exists only so a traversal can stop descending; it can never
  disagree, because a file under an ignored directory already fails
  here.
  """
  @spec library_content?(String.t(), t()) :: boolean()
  def library_content?(path, %__MODULE__{} = rules) when is_binary(path) do
    VideoFile.video?(path) and not ignored?(path, rules)
  end

  @doc """
  True when a rule covers `path`, read as a file path: a path rule
  matches it or an ancestor, or a name rule matches one of its *parent*
  components. The final component is the file's own name and never
  matches a name rule.
  """
  @spec ignored?(String.t(), t()) :: boolean()
  def ignored?(path, %__MODULE__{} = rules) when is_binary(path) do
    matching_rule(path, rules) != nil
  end

  @doc """
  Which rule covers `path`, or `nil`. Path rules are checked first.

  `ignored?/2` is this function's boolean face, so the predicate and
  the explanation can never disagree. The explanation is what makes a
  report actionable: told only that a file is ignored, a user with
  several rules has no way to know which one to change.
  """
  @spec matching_rule(String.t(), t()) :: {:path, String.t()} | {:name, String.t()} | nil
  def matching_rule(path, %__MODULE__{} = rules) when is_binary(path) do
    case matching_path_rule(path, rules) do
      nil ->
        path
        |> Path.split()
        |> Enum.drop(-1)
        |> Enum.find_value(fn component ->
          if name_rule_match?(component, rules), do: {:name, String.downcase(component)}
        end)

      dir ->
        {:path, dir}
    end
  end

  @doc "Human-readable form of a `matching_rule/2` result, for logs and UI copy."
  @spec describe_rule({:path, String.t()} | {:name, String.t()}) :: String.t()
  def describe_rule({:path, dir}), do: "excluded directory #{dir}"
  def describe_rule({:name, name}), do: "ignored folder name #{inspect(name)}"

  @doc """
  True when a rule covers `path`, read as a directory path: a path rule
  matches it or an ancestor, or a name rule matches its own basename.

  The traversal prune — a directory this returns `true` for contains no
  library content, so there is no reason to descend.
  """
  @spec ignored_dir?(String.t(), t()) :: boolean()
  def ignored_dir?(path, %__MODULE__{} = rules) when is_binary(path) do
    matching_path_rule(path, rules) != nil or name_rule_match?(Path.basename(path), rules)
  end

  defp matching_path_rule(path, %__MODULE__{path_rules: path_rules}) do
    Enum.find_value(path_rules, fn {dir, dir_slash} ->
      if path == dir or String.starts_with?(path, dir_slash), do: dir
    end)
  end

  defp name_rule_match?(component, %__MODULE__{name_rules: name_rules}) do
    String.downcase(component) in name_rules
  end

  defp under?(path, media_dir), do: path == media_dir or String.starts_with?(path, media_dir <> "/")
end
