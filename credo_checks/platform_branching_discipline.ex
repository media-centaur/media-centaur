defmodule MediaCentaur.Credo.Checks.PlatformBranchingDiscipline do
  use Credo.Check,
    id: "MC0017",
    base_priority: :high,
    category: :design,
    param_defaults: [grandfathered: []],
    explanations: [
      check: """
      All OS-divergent code must live under `MediaCentaur.Platform.*`
      (`lib/media_centaur/platform/`). Outside that namespace,
      branching on `:os.type/0` or calling `:os.cmd/1` is forbidden.

      The rule keeps platform divergence in one discoverable place.
      A contributor opening `lib/media_centaur/` should be able to
      answer "where does this app branch on OS?" in one glance —
      the answer is the `platform/` directory.

          # NOT allowed — `Watcher` is business logic
          defmodule MediaCentaur.Watcher do
            def handle_event(events) do
              case :os.type() do
                {:unix, :darwin} -> filter_macos(events)
                _ -> events
              end
            end
          end

          # Allowed — `Platform.WatcherEvents` is a platform seam
          defmodule MediaCentaur.Platform.WatcherEvents do
            def normalize(events) do
              case :os.type() do
                {:unix, :darwin} -> macos_translate(events)
                _ -> events
              end
            end
          end

      Source: `campaigns/macos-platform-support.md` — the
      Project-structure visibility rule.

      ## Options

        * `:grandfathered` — list of file paths (relative to the
          project root) that may keep their existing `:os.type/0`
          calls. New violations in grandfathered files still fail.
          The list shrinks as each seam is extracted to
          `Platform.*`.
      """,
      params: [
        grandfathered:
          "List of file paths (relative to project root) that are exempt from the check while pending migration to Platform.*"
      ]
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    cond do
      not lib_path?(filename) -> []
      platform_path?(filename) -> []
      filename in Params.get(params, :grandfathered, __MODULE__) -> []
      true -> analyze(source_file, params)
    end
  end

  defp lib_path?(filename), do: String.starts_with?(filename, "lib/")

  defp platform_path?(filename) do
    String.starts_with?(filename, "lib/media_centaur/platform/") or
      filename == "lib/media_centaur/platform.ex"
  end

  defp analyze(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # `:os.type()` — the canonical platform branch
  defp traverse({{:., meta, [:os, :type]}, _, _args} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, ":os.type/0", meta[:line]) | issues]}
  end

  # `:os.cmd(...)` — usually an OS-specific shell-out
  defp traverse({{:., meta, [:os, :cmd]}, _, _args} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, ":os.cmd/1", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` is not allowed outside `MediaCentaur.Platform.*`. " <>
          "Move the OS-divergent logic into a module under `lib/media_centaur/platform/` " <>
          "and call through the seam. See `campaigns/macos-platform-support.md`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
