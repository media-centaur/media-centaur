defmodule MediaCentarr.Credo.Checks.RowMutationInSchemaMigration do
  use Credo.Check,
    id: "MC0015",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Schema migrations (`priv/repo/migrations/`) must not perform bulk
      row mutations (`UPDATE` / `DELETE`). Use a data migration in
      `priv/repo/data_migrations/` instead — these are tracked in the
      `data_migrations` table (separate from `schema_migrations`), so a
      dev `mix ecto.migrate` against a shared database can't shadow
      them.

      See ADR-040
      (`decisions/architecture/2026-05-09-040-data-migrations.md`) for
      the full authoring contract.

      ## Why this rule exists

      `priv/repo/migrations/20260515000000_repoint_collection_child_watched_files.exs`
      was authored as a schema migration and ran via `mix ecto.migrate`
      from a dev session sharing the user's database. When the user
      later updated the release, Ecto saw the version as already applied
      and skipped it. New rows with the buggy shape (added between dev's
      `migrate` call and the user's release update) were never repaired,
      and the user had to manually patch them. A data migration would
      have run in its own stream, against the user's release boot, with
      no possibility of dev-side shadowing.

      ## Surgical inline fixups

      Small, surgical row-fixups that genuinely belong with a schema
      change (e.g. `heal_grabs_tmdb_type_tv_series.exs`, which heals an
      enum spelling drift in the same migration that makes the new
      spelling canonical) may opt out per-line:

          # credo:disable-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
          execute("UPDATE acquisition_grabs SET tmdb_type = 'tv' WHERE tmdb_type = 'tv_series'")

      Anything larger — anything that wouldn't fit in the same hunk as
      its accompanying schema change — belongs in a data migration.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if schema_migration_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp schema_migration_file?(filename) do
    String.contains?(filename, "priv/repo/migrations/") and
      String.ends_with?(filename, ".exs")
  end

  # `execute("UPDATE …")` / `execute("DELETE …")` — also catches heredocs,
  # which become binary literals in the AST.
  defp traverse({:execute, meta, [sql | _]} = ast, issues, issue_meta) when is_binary(sql) do
    case mutation_keyword(sql) do
      nil -> {ast, issues}
      keyword -> {ast, [issue_for(issue_meta, "execute(\"#{keyword} …\")", meta[:line]) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp mutation_keyword(sql) do
    sql
    |> String.trim_leading()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> String.upcase()
    |> case do
      "UPDATE" -> "UPDATE"
      "DELETE" -> "DELETE"
      _ -> nil
    end
  end

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Bulk row mutation in a schema migration — move to a data migration in " <>
          "`priv/repo/data_migrations/` per ADR-040. For surgical inline fixups " <>
          "paired with a schema change, add " <>
          "`# credo:disable-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration`.",
      trigger: trigger,
      line_no: line_no || 1
    )
  end
end
