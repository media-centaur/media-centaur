defmodule MediaCentaur.Credo.Checks.NoRepoSetupInTests do
  use Credo.Check,
    id: "MC0023",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Tests must not build their starting state with a `Repo` write.

      The distinction is *setup* versus *assertion*, not `Repo` versus not:

        * **Writes are setup.** `Repo.insert/1`, `update!/1`, `delete_all/1`
          and friends construct the world the test runs against. Doing that
          inline skips the changeset, so the test can assert against a row
          the application could never actually produce — and every such site
          is a private, undocumented factory that drifts from the real one.
          Use `MediaCentaur.TestFactory`: `create_*` for records,
          `force_attrs/2`, `backdate/3` or `force_state/2` when you
          deliberately need a state the public API refuses to produce.

        * **Reads are assertions.** `Repo.get!/2`, `Repo.all/1`,
          `Repo.aggregate/3` and friends check what the code under test
          actually persisted. Reaching past the context to confirm a row
          landed is exactly what an integration assertion should do, and
          this check leaves them alone.

              # NOT preferred — inline setup
              {:ok, pursuit} = Repo.insert(%Pursuit{state: "satisfied"})

              # preferred
              pursuit = create_pursuit() |> force_state("satisfied")

              # allowed — asserting the write landed
              assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"

      `test/support/` is exempt: the factory is where setup writes belong.

      The `@grandfathered` list is the rollout backlog, not a permanent
      exemption — the files on it still build state inline, mostly because
      the schema in question has no factory builder yet. Add the builder,
      convert the file, remove it from the list. Do not add new entries.

      Source: `campaigns/audit-remediation-2026-08.md` Stage 4.
      """
    ]

  # Functions that write. Reads are deliberately absent — they are
  # legitimate assertions.
  @write_functions [
    :insert,
    :insert!,
    :insert_all,
    :insert_or_update,
    :insert_or_update!,
    :update,
    :update!,
    :update_all,
    :delete,
    :delete!,
    :delete_all
  ]

  # Rollout backlog — files that still build state with inline `Repo`
  # writes. Each needs a `TestFactory` builder for the schema it inserts.
  # This list may only shrink.
  @grandfathered [
    "test/media_centaur/acquisition/plans_test.exs",
    "test/media_centaur/acquisition/pursuits/commands/terminal_commands_test.exs",
    "test/media_centaur/acquisition/pursuits/download_identity_test.exs",
    "test/media_centaur/acquisition/pursuits/events_test.exs",
    "test/media_centaur/acquisition/pursuits/inbound_listener_test.exs",
    "test/media_centaur/acquisition/pursuits/throughput_test.exs",
    "test/media_centaur/acquisition/pursuits/watcher_test.exs",
    "test/media_centaur/acquisition/pursuits_test.exs",
    "test/media_centaur/acquisition/tracking_handoffs_test.exs",
    "test/media_centaur/library/movie_series_test.exs",
    "test/media_centaur/library/movie_test.exs",
    "test/media_centaur/library/playable_item_test.exs",
    "test/media_centaur/library/tv_series_test.exs",
    "test/media_centaur/library/type_resolver_test.exs",
    "test/media_centaur/library/views/browse_test.exs",
    "test/media_centaur/library/views/detail_test.exs",
    "test/media_centaur/library/views/search_test.exs",
    "test/media_centaur/library/watch_progress_test.exs",
    "test/media_centaur/maintenance_test.exs",
    "test/media_centaur/watch_history/event_test.exs",
    "test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs",
    "test/media_centaur_web/live/incoming_live_test.exs",
    "test/media_centaur_web/page_smoke_test.exs"
  ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_path?(filename) and not exempt?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_path?(filename) do
    String.starts_with?(filename, "test/") or String.contains?(filename, "/test/")
  end

  # The factory is where setup writes belong; the backlog is temporary.
  defp exempt?(filename) do
    String.contains?(filename, "test/support/") or
      Enum.any?(@grandfathered, &String.ends_with?(filename, &1))
  end

  defp traverse(
         {{:., meta, [{:__aliases__, _alias_meta, parts}, function]}, _call_meta, _args} = ast,
         issues,
         issue_meta
       ) do
    if List.last(parts) == :Repo and function in @write_functions do
      {ast, [issue_for(issue_meta, "Repo.#{function}", meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` builds test state inline. Use `MediaCentaur.TestFactory` — " <>
          "`create_*` to insert, or `force_attrs/2` / `backdate/3` / `force_state/2` " <>
          "to force a state the public API won't produce. Repo *reads* are fine.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
