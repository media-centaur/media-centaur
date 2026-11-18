defmodule MediaCentaur.Credo.Checks.ApiOnlyConsumes do
  use Credo.Check,
    id: "MC0046",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      The Local API (`MediaCentaurWeb.Api.*`) is a leaf. It consumes the
      app's services, and nothing depends on it.

      Nothing references it. No module outside the namespace may name a
      module inside it, except the router, which mounts it. Logic another
      surface needs belongs in a context or service that both call.

      It only consumes. An API module may not reach the database, publish
      events, or own a job or process: `Repo`, `Ecto`, `Phoenix.PubSub`,
      `Topics`, `Oban`, `GenServer`, `Agent`, `Supervisor`, `Task` and
      `:ets` are refused. It calls a context's public functions instead.

      The `MediaCentaurWeb` Boundary cannot state this, because the API
      and the rest of the web layer are one boundary. ADR-085.
      """
    ]

  @namespace [:MediaCentaurWeb, :Api]
  @router "lib/media_centaur_web/router.ex"

  @refused [
    [:MediaCentaur, :Repo],
    [:MediaCentaur, :Topics],
    [:Ecto],
    [:Phoenix, :PubSub],
    [:Oban],
    [:GenServer],
    [:Agent],
    [:Supervisor],
    [:Task]
  ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    cond do
      not String.contains?(filename, "lib/media_centaur") -> []
      String.ends_with?(filename, @router) -> []
      defines_api_module?(source_file) -> issues(source_file, params, &refused?/1, :consumes)
      true -> issues(source_file, params, &api?/1, :referenced)
    end
  end

  defp defines_api_module?(source_file) do
    Credo.Code.prewalk(source_file, &find_definition/2, false)
  end

  defp find_definition({:defmodule, _, [{:__aliases__, _, name} | _]} = ast, found?) do
    {ast, found? or api?(name)}
  end

  defp find_definition(ast, found?), do: {ast, found?}

  defp issues(source_file, params, matches?, rule) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, matches?, rule))
  end

  # alias Base.{One, Two.Three}
  defp traverse(
         {{:., meta, [{:__aliases__, _, base}, :{}]}, _, children} = ast,
         issues,
         issue_meta,
         matches?,
         rule
       ) do
    found =
      for {:__aliases__, _, child} <- children, name = base ++ child, matches?.(name) do
        issue_for(issue_meta, name, meta[:line], rule)
      end

    {ast, found ++ issues}
  end

  defp traverse({:__aliases__, meta, name} = ast, issues, issue_meta, matches?, rule) do
    if matches?.(name),
      do: {ast, [issue_for(issue_meta, name, meta[:line], rule) | issues]},
      else: {ast, issues}
  end

  defp traverse({:., meta, [:ets, _function]} = ast, issues, issue_meta, _matches?, :consumes) do
    {ast, [issue_for(issue_meta, [:ets], meta[:line], :consumes) | issues]}
  end

  defp traverse(ast, issues, _issue_meta, _matches?, _rule), do: {ast, issues}

  defp api?(name), do: List.starts_with?(name, @namespace)
  defp refused?(name), do: Enum.any?(@refused, &List.starts_with?(name, &1))

  defp issue_for(issue_meta, name, line_no, :referenced) do
    format_issue(issue_meta,
      message: "Only the router may reference the Local API. Move what you need into a context (ADR-085).",
      trigger: Enum.join(name, "."),
      line_no: line_no
    )
  end

  defp issue_for(issue_meta, name, line_no, :consumes) do
    format_issue(issue_meta,
      message: "The Local API only consumes: call a context's public function instead (ADR-085).",
      trigger: Enum.join(name, "."),
      line_no: line_no
    )
  end
end
