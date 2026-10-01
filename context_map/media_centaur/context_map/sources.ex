defmodule MediaCentaur.ContextMap.Sources do
  @moduledoc """
  Parses every `.ex` under `lib/media_centaur` and `lib/media_centaur_web`
  with Sourceror, so each node carries its line. `lib/mix` and
  `priv/repo/migrations` are not read: migrations are the one place
  literals are legitimately written.

  Aliases are resolved per file (`alias A.B`, `alias A.{B, C}`,
  `alias A.B, as: C`), not per scope — a stated limit of the map.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Source

  @roots ["lib/media_centaur", "lib/media_centaur_web"]

  @doc "Every source file under the read roots, sorted by path."
  @spec all() :: [Source.t()]
  def all do
    @roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.sort()
    |> Enum.map(&parse(&1, File.read!(&1)))
  end

  @doc "Parses `code` as the file at `path`."
  @spec parse(String.t(), String.t()) :: Source.t()
  def parse(path, code) do
    ast = Sourceror.parse_string!(code)
    modules = defined_modules(ast)

    %Source{
      path: path,
      modules: modules,
      context: context(modules),
      references: references(ast, aliases(ast)),
      live_view?: live_view?(ast),
      ast: ast,
      lines: String.split(code, "\n")
    }
  end

  defp context([]), do: nil
  defp context([first | _]), do: Contexts.context_of(first)

  defp defined_modules(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc -> {node, [module(parts) | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(found)
  end

  defp aliases(ast) do
    {_, found} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
          {node, Enum.reduce(children, acc, &put_child_alias(&1, &2, base))}

        {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), module(parts))}

        {:alias, _, [{:__aliases__, _, parts}, [{{:__block__, _, [:as]}, {:__aliases__, _, [as]}}]]} =
            node,
        acc ->
          {node, Map.put(acc, as, module(parts))}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp put_child_alias({:__aliases__, _, child}, acc, base),
    do: Map.put(acc, List.last(child), module(base ++ child))

  defp references(ast, aliases) do
    {_, found} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:__aliases__, _, [head | rest] = parts} = node, acc when is_atom(head) ->
          resolved =
            if Map.has_key?(aliases, head), do: module([aliases[head] | rest]), else: module(parts)

          {node, MapSet.put(acc, resolved)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp live_view?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:use, _, [{:__aliases__, _, [:MediaCentaurWeb]}, {:__block__, _, [:live_view]}]} = node, _ ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Module names written in the parsed source need not exist as loaded
  # modules (a reference to an external or not-yet-compiled module), so
  # `Module.safe_concat/1` would raise. The inputs are this repo's source
  # files, a bounded set of names.
  defp module(parts) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(parts)
  end
end
