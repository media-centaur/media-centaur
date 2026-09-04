defmodule MediaCentaur.Credo.Checks.OneModulePerFile do
  use Credo.Check,
    id: "MC0032",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      An application file under `lib/` defines exactly one **top-level**
      module.

      Two sibling modules in one file make each unfindable from its name —
      `MediaCentaur.Profile.Suites.ComingUpRefreshSuite` did not live in
      `coming_up_refresh_suite.ex` — and they compile as a unit, so a
      change to either recompiles both and everything that depends on
      either.

      A module **nested inside** the file's module is a different thing
      and is allowed: `MediaCentaur.Library.Events.EntitiesChanged` inside
      `library/events.ex` is namespaced by the file it is in, so its name
      still says where to find it. That is the house pattern for typed
      events and view-model structs, used in ~38 files.

          # NOT allowed — two modules, one file
          defmodule MediaCentaur.Profile.Suites.ComingUpSuite do
          end

          defmodule MediaCentaur.Profile.Suites.ComingUpRefreshSuite do
          end

          # Allowed — one file each, path mirroring the module name
          # lib/media_centaur/profile/suites/coming_up_suite.ex
          # lib/media_centaur/profile/suites/coming_up_refresh_suite.ex

          # Allowed — nested, so the file's module namespaces it
          defmodule MediaCentaur.Library.Events do
            defmodule EntitiesChanged do
              defstruct [:ids]
            end
          end

      Test files are exempt: a stub module colocated with the single test
      that uses it has no compile-order or discoverability cost, and
      moving it to `test/support/` would widen its scope for no gain.

      Source: AGENTS.md, "Elixir guidelines".
      """
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if lib_path?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.ast()
      |> top_level_defmodule_lines()
      |> Enum.sort()
      # The first module in the file is the one that belongs there; every
      # sibling after it is the finding.
      |> Enum.drop(1)
      |> Enum.map(&issue_for(issue_meta, &1))
    else
      []
    end
  end

  defp lib_path?(filename), do: String.starts_with?(filename, "lib/")

  # Only the file's own top level — a `defmodule` inside another module is
  # namespaced by it and stays legal.
  defp top_level_defmodule_lines({:__block__, _meta, children}),
    do: Enum.flat_map(children, &top_level_defmodule_lines/1)

  defp top_level_defmodule_lines({:defmodule, meta, _args}), do: [meta[:line]]
  defp top_level_defmodule_lines(_ast), do: []

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "A file under `lib/` defines one module. Move this module to its own " <>
          "file, named for it — `MediaCentaur.Foo.Bar` lives in " <>
          "`lib/media_centaur/foo/bar.ex`. See AGENTS.md.",
      trigger: "defmodule",
      line_no: line_no
    )
  end
end
