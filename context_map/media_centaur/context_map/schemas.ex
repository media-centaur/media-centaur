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
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Schema

  @timestamps [:inserted_at, :updated_at]

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

  @doc "Reflects one Ecto schema module into a `Schema`."
  @spec from_module(module()) :: Schema.t()
  def from_module(module) do
    drop = module.__schema__(:primary_key) ++ module.__schema__(:virtual_fields) ++ @timestamps

    %Schema{
      module: module,
      context: Contexts.context_of(module),
      file: module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd(),
      table: module.__schema__(:source),
      fields: for(name <- module.__schema__(:fields), name not in drop, do: field(module, name)),
      associations:
        for(
          name <- module.__schema__(:associations),
          assoc = module.__schema__(:association, name),
          not match?(%Ecto.Association.HasThrough{}, assoc),
          do: association(assoc)
        )
    }
  end

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
