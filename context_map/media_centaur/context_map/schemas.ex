defmodule MediaCentaur.ContextMap.Schemas do
  @moduledoc """
  Every Ecto schema in the application via `__schema__/1` reflection.
  Persisted fields only: primary keys, timestamps and virtual fields are
  dropped. `Ecto.Enum` fields carry their value set; other fields carry
  `values: nil`. `has_many/has_one ... through:` associations are skipped:
  they are composed from direct associations already listed and have no
  target schema of their own.

  Associations carry `name` (the association name), `kind`, `target` (the
  related schema) and `foreign_key`: the owner-side key column for
  `belongs_to`, nil for every other kind.

  `file` is the schema's source path relative to the repository root the
  task runs from (Mix runs from the root, as `Sources` assumes).

  Fields and associations carry `line` and `declaration`: the line of
  their `field` / `belongs_to` / `has_one` / `has_many` / `many_to_many` /
  `embeds_one` / `embeds_many` call in `file`, and that line trimmed. The
  file is parsed once and the search covers the schema module's own body,
  not modules nested in it, so two schemas in one file keep apart. A
  `belongs_to` foreign-key field takes its association's declaration. A
  field with no declaration of its own (injected by a macro) has `line: 1`
  and `declaration: ""`. An inline embed (`embeds_one :name, Module do …
  end`) is located, but its block is not searched, so the generated
  embedded schema's own fields are not located.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Schema

  @timestamps [:inserted_at, :updated_at]
  @declaration_calls [:field, :belongs_to, :has_one, :has_many, :many_to_many, :embeds_one, :embeds_many]

  @doc "Every Ecto schema under `MediaCentaur`, sorted by module."
  @spec all() :: [Schema.t()]
  def all do
    {:ok, modules} = :application.get_key(:media_centaur, :modules)

    modules
    |> Enum.filter(&schema_module?/1)
    |> Enum.map(&from_module/1)
    |> Enum.sort_by(&inspect(&1.module))
  end

  @doc "Every enum value → the `{schema_module, field}` pairs declaring it, across all schemas."
  @spec value_owners([Schema.t()]) :: %{atom() => [{module(), atom()}]}
  def value_owners(schemas) do
    Map.new(
      for schema <- schemas,
          %{name: field, values: values} when is_list(values) <- schema.fields,
          value <- values,
          reduce: %{} do
        acc -> Map.update(acc, value, [{schema.module, field}], &[{schema.module, field} | &1])
      end,
      fn {value, owners} -> {value, Enum.sort(owners)} end
    )
  end

  defp schema_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
      match?(["MediaCentaur" | _], Module.split(module))
  end

  @doc """
  The source path of `module` relative to `root`. Raises `ArgumentError`
  when the module was compiled from outside `root`, rather than storing an
  absolute path.
  """
  @spec source_file(module(), String.t()) :: String.t()
  def source_file(module, root) do
    path = module.module_info(:compile)[:source] |> to_string() |> Path.relative_to(root)

    if Path.type(path) == :absolute do
      raise ArgumentError,
            "#{inspect(module)} was compiled from #{path}, outside the project root #{root}; " <>
              "run mix context_map from the repository root against a build compiled there"
    end

    path
  end

  @doc "Reflects one Ecto schema module into a `Schema`, reading its source file once for declarations."
  @spec from_module(module()) :: Schema.t()
  def from_module(module) do
    drop = module.__schema__(:primary_key) ++ module.__schema__(:virtual_fields) ++ @timestamps
    file = source_file(module, File.cwd!())
    declarations = declarations(module, File.read!(file))

    associations =
      for name <- module.__schema__(:associations),
          assoc = module.__schema__(:association, name),
          not match?(%Ecto.Association.HasThrough{}, assoc) do
        assoc |> association() |> declared(declarations[assoc.field])
      end

    foreign_key_owners =
      for %{kind: :belongs_to, foreign_key: key, name: name} <- associations,
          into: %{},
          do: {key, name}

    %Schema{
      module: module,
      context: Contexts.context_of(module),
      file: file,
      table: module.__schema__(:source),
      fields:
        for name <- module.__schema__(:fields), name not in drop do
          declaration = declarations[name] || declarations[foreign_key_owners[name]]
          module |> field(name) |> declared(declaration)
        end,
      associations: associations
    }
  end

  @doc """
  The declarations in `code` of `module`'s own body, by declared name:
  `{line, trimmed line}` for each `field`, `belongs_to`, `has_one`,
  `has_many`, `many_to_many`, `embeds_one` and `embeds_many` call. Modules
  nested in `module` are not searched; a module `code` does not define
  has none.
  """
  @spec declarations(module(), String.t()) :: %{atom() => {pos_integer(), String.t()}}
  def declarations(module, code) do
    lines = String.split(code, "\n")

    code
    |> Sourceror.parse_string!()
    |> module_body([], Module.split(module))
    |> case do
      nil -> %{}
      body -> body_declarations(body, lines)
    end
  end

  # The body of the `defmodule` whose full name, nesting included, is `target`.
  defp module_body({:defmodule, _, [{:__aliases__, _, parts}, [{_do, body}]]}, prefix, target) do
    name = prefix ++ Enum.map(parts, &Atom.to_string/1)

    cond do
      name == target -> body
      List.starts_with?(target, name) -> module_body(body, name, target)
      true -> nil
    end
  end

  defp module_body({_call, _meta, arguments}, prefix, target) when is_list(arguments),
    do: module_body(arguments, prefix, target)

  defp module_body(list, prefix, target) when is_list(list),
    do: Enum.find_value(list, &module_body(&1, prefix, target))

  defp module_body({left, right}, prefix, target),
    do: module_body(left, prefix, target) || module_body(right, prefix, target)

  defp module_body(_node, _prefix, _target), do: nil

  defp body_declarations(body, lines) do
    {_, found} =
      Macro.prewalk(body, %{}, fn
        {:defmodule, _, _}, acc ->
          {nil, acc}

        {call, meta, [{:__block__, _, [name]} | arguments]} = node, acc
        when call in @declaration_calls and is_atom(name) ->
          line = meta[:line]
          acc = Map.put_new(acc, name, {line, lines |> Enum.at(line - 1, "") |> String.trim()})
          if inline_embed?(call, arguments), do: {nil, acc}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp inline_embed?(call, arguments) when call in [:embeds_one, :embeds_many],
    do: Enum.any?(arguments, &do_block?/1)

  defp inline_embed?(_call, _arguments), do: false

  defp do_block?(keyword) when is_list(keyword),
    do: Enum.any?(keyword, &match?({{:__block__, _, [:do]}, _}, &1))

  defp do_block?(_argument), do: false

  defp declared(entry, {line, declaration}),
    do: Map.merge(entry, %{line: line, declaration: declaration})

  defp declared(entry, nil), do: Map.merge(entry, %{line: 1, declaration: ""})

  defp field(module, name) do
    case module.__schema__(:type, name) do
      {:parameterized, {Ecto.Enum, _}} ->
        %{name: name, type: "Ecto.Enum", values: Ecto.Enum.values(module, name)}

      type ->
        %{name: name, type: inspect(type), values: nil}
    end
  end

  defp association(%Ecto.Association.BelongsTo{field: field, owner_key: key, related: target}),
    do: %{name: field, kind: :belongs_to, target: target, foreign_key: key}

  defp association(%Ecto.Association.Has{field: field, cardinality: :one, related: target}),
    do: %{name: field, kind: :has_one, target: target, foreign_key: nil}

  defp association(%Ecto.Association.Has{field: field, cardinality: :many, related: target}),
    do: %{name: field, kind: :has_many, target: target, foreign_key: nil}

  defp association(%Ecto.Association.ManyToMany{field: field, related: target}),
    do: %{name: field, kind: :many_to_many, target: target, foreign_key: nil}
end
