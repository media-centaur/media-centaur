defmodule MediaCentarr.Credo.Checks.OwnedAsyncInWeb do
  use Credo.Check,
    id: "MC0019",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Web-layer modules (LiveViews, components) must not spawn
      fire-and-forget work via
      `Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, …)`.

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
          Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
            result = expensive_load()
            send(self(), {:loaded, result})
          end)

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

  # LiveViews that still spawn fire-and-forget tasks. This list IS the
  # owned-async rollout backlog — it shrinks to empty as each LiveView
  # converts to `start_async` / a durable home, at which point the rule
  # is fully enforced. Do NOT add to it.
  @grandfathered [
    "lib/media_centarr_web/live/acquisition_live.ex",
    "lib/media_centarr_web/live/entity_modal.ex",
    "lib/media_centarr_web/live/settings_live.ex"
  ]

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
    String.contains?(filename, "lib/media_centarr_web/")
  end

  defp grandfathered?(filename) do
    Enum.any?(@grandfathered, &String.ends_with?(filename, &1))
  end

  # `Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, …)`
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Task, :Supervisor]}, :start_child]}, _,
          [{:__aliases__, _, [:MediaCentarr, :TaskSupervisor]} | _]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Fire-and-forget `Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, …)` " <>
          "in the web layer orphans the task — it is not cancelled with the LiveView " <>
          "and not awaitable in tests. Use `start_async/3` (owned, awaitable) for view " <>
          "loads, or an Oban job / supervised service for work that must outlive the " <>
          "LiveView. See ADR-049.",
      trigger: "Task.Supervisor.start_child",
      line_no: line_no
    )
  end
end
