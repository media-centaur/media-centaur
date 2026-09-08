defmodule MediaCentaur.Credo.Checks.GlobalStateWritesCheckedOut do
  use Credo.Check,
    id: "MC0036",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A write to global state happens inside a checked-out test.

      `MediaCentaur.GlobalStateSandbox` checks the machine out for one
      `async: false` test at a time and puts it back afterwards. Two places
      are outside that:

        * an `async: true` module — concurrent tests share the machine, so a
          write lands underneath every peer and whichever test reads it next
          fails at some seeds and not others;
        * a `setup_all` block — it runs once, before any test is checked out,
          so the first test's checkout finds the machine off the baseline and
          restores it out from under the module.

          # NOT preferred — in a module with `async: true`, or in setup_all
          :persistent_term.put({MediaCentaur.Thing, :state}, value)
          Application.put_env(:media_centaur, :environment, :prod)
          Config.update(:exclude_dirs, dirs)
          UpdateChecker.cache_result(result)
          Supervisor.start_child(MediaCentaur.Supervisor, Some.Listener)

          # preferred
          use MediaCentaur.Case, async: false
          setup do
            Application.put_env(:media_centaur, :environment, :prod)
          end

      Reads are fine. The writers this check knows are the ones the suite
      has been bitten by, including context functions that write a
      `:persistent_term` cache; extend the list when a new one bites. The
      runtime check is the authority — a write this list misses still fails
      the first sync test's checkout, naming the async phase.

      Source: `campaigns/test-suite-determinism.md`.
      """
    ]

  @writes [
    {:persistent_term, :put},
    {:persistent_term, :erase},
    {[:Application], :put_env},
    {[:Application], :delete_env},
    {[:Config], :update},
    {[:Config], :put_media_dirs},
    {[:Req, :Test], :set_req_test_to_shared},
    {[:System], :put_env},
    {[:System], :delete_env},
    {[:UpdateChecker], :cache_result},
    {[:UpdateChecker], :clear_cache},
    {[:Capabilities], :save_test_result},
    {[:Capabilities], :clear_test_result},
    {[:Watcher, :Supervisor], :start_watchers},
    {[:Supervisor], :start_child}
  ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      if async?(source_file) do
        Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
      else
        Credo.Code.prewalk(source_file, &traverse_setup_all(&1, &2, issue_meta))
      end
    else
      []
    end
  end

  defp test_file?(filename), do: String.starts_with?(filename, "test/") and String.ends_with?(filename, "_test.exs")

  defp async?(source_file) do
    Credo.Code.prewalk(source_file, fn
      {:use, _, [{:__aliases__, _, _}, opts]} = ast, acc when is_list(opts) ->
        {ast, acc or Keyword.get(opts, :async) == true}

      ast, acc ->
        {ast, acc}
    end, false)
  end

  # In a sync module only `setup_all` is outside the checkout.
  defp traverse_setup_all({:setup_all, _meta, _args} = ast, issues, issue_meta) do
    {ast, Credo.Code.prewalk(ast, &traverse(&1, &2, issue_meta), issues)}
  end

  defp traverse_setup_all(ast, issues, _issue_meta), do: {ast, issues}

  defp traverse({{:., _, [target, function]}, meta, _args} = ast, issues, issue_meta) do
    case write(target, function) do
      nil -> {ast, issues}
      trigger -> {ast, [issue_for(issue_meta, trigger, meta[:line]) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp write(:persistent_term, function) do
    if {:persistent_term, function} in @writes, do: ":persistent_term.#{function}"
  end

  defp write({:__aliases__, _, aliases}, function) do
    Enum.find_value(@writes, fn
      {suffix, ^function} when is_list(suffix) ->
        if List.starts_with?(Enum.reverse(aliases), Enum.reverse(suffix)), do: Enum.join(aliases, ".") <> ".#{function}"

      _other ->
        nil
    end)
  end

  defp write(_target, _function), do: nil

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` writes global state outside a checked-out test — in an `async: true` module or in " <>
          "`setup_all`. Make the module `async: false` and write it in `setup`, so the sandbox restores it.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
