defmodule MediaCentaur.Credo.Checks.OwnedAsyncInWeb do
  use Credo.Check,
    id: "MC0019",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Web-layer modules (LiveViews, components) must not hang async work
      off a `Task.Supervisor` — not `start_child/2`, and not
      `async_nolink/2` or `async_stream_nolink/3` either. The `nolink`
      pair looks owned because the caller gets a `%Task{}` back and
      matches on its `ref`, but the task is still supervised globally:
      it survives the LiveView, and nothing in a test can await it.

      Such a task is **owned by nobody**: it is not linked to the
      LiveView, so it is not cancelled when the LiveView dies and not
      awaitable from a test. In the test suite these tasks orphan under
      the global supervisor and outlive their test — one stuck in an
      HTTP retry backoff turned the whole suite into a multi-minute
      hang (see `campaigns/test-suite-performance.md`). In production
      they leak past navigation and can write after the LiveView is
      gone.

      Use the lifecycle-bound alternative instead:

          # NOT allowed — orphaned, untestable, leaks past the LiveView
          Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
            result = expensive_load()
            send(self(), {:loaded, result})
          end)

          # Also NOT allowed — a ref to match on is not ownership, and the
          # hand-rolled {ref, result} / :DOWN pair reimplements handle_async
          task = Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn -> … end)

          # Allowed — owned by the LiveView, awaitable via render_async/1,
          # cancelled when the LiveView terminates
          start_async(socket, :load, fn -> expensive_load() end)
          # then handle_async(:load, {:ok, result}, socket)

      For work that must **outlive** the LiveView (a user-initiated
      grab or search whose result updates shared state), do not use a
      bare task either — enqueue an Oban job or call a supervised
      service. A fire-and-forget global task is never the right home.

      Source: ADR-049 (testing principles, Principle 2 — async work is
      owned, never orphaned).
      """
    ]

  # The owned-async rollout is complete — every web-layer LiveView now uses
  # `start_async` (view loads) or a context-layer function (must-outlive
  # work). The rule is fully enforced; this list MUST stay empty.
  @grandfathered []

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if web_path?(filename) and not grandfathered?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp web_path?(filename) do
    String.contains?(filename, "lib/media_centaur_web/")
  end

  defp grandfathered?(filename) do
    Enum.any?(@grandfathered, &String.ends_with?(filename, &1))
  end

  # Every `Task.Supervisor` spawn that hangs the task off a supervisor rather
  # than off the LiveView. The supervisor argument is not matched: under a
  # pipe (`MediaCentaur.TaskSupervisor |> Task.Supervisor.async_stream_nolink(…)`)
  # it is not the first argument of the call node, and a task on *any* global
  # supervisor is equally unowned by the view.
  @unowned_spawns [:start_child, :async_nolink, :async_stream_nolink]

  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Task, :Supervisor]}, fun]}, _, _} = ast,
         issues,
         issue_meta
       )
       when fun in @unowned_spawns do
    {ast, [issue_for(issue_meta, meta[:line], fun) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, fun) do
    format_issue(
      issue_meta,
      message:
        "`Task.Supervisor.#{fun}` in the web layer orphans the task — it is " <>
          "supervised globally, so it is not cancelled with the LiveView and not " <>
          "awaitable in tests. Use `start_async/3` (owned, awaitable) for view " <>
          "loads, or an Oban job / supervised service for work that must outlive the " <>
          "LiveView. See ADR-049.",
      trigger: "Task.Supervisor.#{fun}",
      line_no: line_no
    )
  end
end
