defmodule MediaCentaur.Credo.Checks.PlanDoorRegistered do
  use Credo.Check,
    id: "MC0037",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every function that creates an acquisition plan — a **door** — must
      be listed in `MediaCentaur.Acquisition.Plans.Doors.registry/0`.

      Acquisition has more doors than anyone remembers. *Release
      tracking* reads as one and is four separate code paths (manual-TV,
      manual-movie, sweep-TV, sweep-movie). When identity-by-id shipped,
      three were wired and the fourth was not, because the set of doors
      lived only in the author's head. The unattended movie door then
      built its plans from the title alone for five days, grabbing a
      different film with the same ASCII-folded name once a day.

      The compiler already guarantees a door is *correct*: `create_plan/2`
      takes a `TMDB.TitleIdentity` and has no clause for anything else, so
      a half-built identity does not compile. This check is the other
      half — it guarantees you *know the door exists*, by refusing a new
      one that has not announced itself.

      Doors are registered by module and function, not by line, so the
      registry does not churn when code moves. Each entry names what the
      door is for in a person's terms ("the automatic sweep, for a
      movie") — the thing a reader needs and a grep for `create_plan`
      cannot give them.
      """
    ]

  @creation_functions [:create_plan, :create_movie_plan, :create_series_plan, :create_tracking_plan]
  @registry_file "lib/media_centaur/acquisition/plans/doors.ex"

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      registered = registered_doors()
      module = module_name(source_file)

      source_file
      |> Credo.Code.ast()
      |> doors_in()
      |> Enum.reject(fn {function, _line} -> MapSet.member?(registered, {module, function}) end)
      |> Enum.map(fn {function, line} -> issue_for(issue_meta, module, function, line) end)
    else
      []
    end
  end

  # Only production code declares doors. The registry itself is exempt —
  # it names every door by definition — as is `Plans`, which owns the
  # shared constructors the doors call through. Tests exercise doors
  # rather than adding them.
  defp applies_to?(filename) do
    String.contains?(filename, "lib/") and
      String.ends_with?(filename, ".ex") and
      not String.ends_with?(filename, "plans/doors.ex") and
      not String.ends_with?(filename, "acquisition/plans.ex")
  end

  # Each plan-creating call, attributed to the function enclosing it.
  defp doors_in({:ok, ast}), do: doors_in(ast)

  defp doors_in(ast) do
    {_ast, doors} =
      Macro.prewalk(ast, [], fn
        {def_kind, _meta, [head | body]} = node, doors when def_kind in [:def, :defp] ->
          {node, calls_in(body, function_name(head)) ++ doors}

        node, doors ->
          {node, doors}
      end)

    Enum.uniq(doors)
  end

  defp calls_in(body, function_name) do
    {_ast, calls} =
      Macro.prewalk(body, [], fn
        {{:., _, [_module, called]}, meta, _args} = node, calls when called in @creation_functions ->
          {node, [{function_name, meta[:line]} | calls]}

        node, calls ->
          {node, calls}
      end)

    calls
  end

  defp function_name({:when, _meta, [head | _guards]}), do: function_name(head)
  defp function_name({name, _meta, _args}) when is_atom(name), do: name
  defp function_name(_head), do: nil

  # The file's `defmodule`, minus the app prefix the registry omits.
  defp module_name(source_file) do
    {_ast, name} =
      source_file
      |> Credo.Code.ast()
      |> Macro.prewalk(nil, fn
        {:defmodule, _meta, [{:__aliases__, _alias_meta, segments} | _rest]} = node, nil ->
          {node, segments |> Enum.map_join(".", &Atom.to_string/1)}

        node, found ->
          {node, found}
      end)

    String.replace_prefix(name || "", "MediaCentaur.", "")
  end

  # Read the registry rather than calling it, so the check carries no
  # compile-order dependency on the app being loaded.
  defp registered_doors do
    case File.read(@registry_file) do
      {:ok, contents} -> parse_registry(contents)
      {:error, _reason} -> MapSet.new()
    end
  end

  defp parse_registry(contents) do
    ~r/module:\s*([A-Za-z0-9_.]+),\s*function:\s*:([a-z_0-9!?]+)/
    |> Regex.scan(contents)
    |> MapSet.new(fn [_all, module, function] ->
      {String.replace_prefix(module, "MediaCentaur.", ""), String.to_atom(function)}
    end)
  end

  defp issue_for(issue_meta, module, function, line) do
    format_issue(issue_meta,
      message:
        "Unregistered plan door: #{module}.#{function}. Add it to " <>
          "MediaCentaur.Acquisition.Plans.Doors.registry/0 in this change — " <>
          "the set of doors must be discoverable, not remembered.",
      trigger: to_string(function),
      line_no: line
    )
  end
end
