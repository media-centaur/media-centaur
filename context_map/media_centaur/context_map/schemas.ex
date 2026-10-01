defmodule MediaCentaur.ContextMap.Schemas do
  @moduledoc """
  Every Ecto schema in the application via `__schema__/1` reflection.
  Persisted fields only: primary keys, timestamps and virtual fields are
  dropped. `Ecto.Enum` fields carry their value set; other fields carry
  `values: nil`. `has_many/has_one ... through:` associations are skipped:
  they are composed from direct associations already listed and have no
  target schema of their own.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Schema

  @timestamps [:inserted_at, :updated_at]

  @spec all() :: [Schema.t()]
  def all do
    {:ok, modules} = :application.get_key(:media_centaur, :modules)

    modules
    |> Enum.filter(&schema_module?/1)
    |> Enum.map(&from_module/1)
    |> Enum.sort_by(&inspect(&1.module))
  end

  @spec fetch!(module()) :: Schema.t()
  def fetch!(module), do: from_module(module)

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
      String.starts_with?(inspect(module), "MediaCentaur")
  end

  defp from_module(module) do
    drop = module.__schema__(:primary_key) ++ module.__schema__(:virtual_fields) ++ @timestamps

    %Schema{
      module: module,
      context: Contexts.context_of(module),
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
    do: %{field: key, kind: :belongs_to, target: target, name: field}

  defp association(%Ecto.Association.Has{field: field, cardinality: :one, related: target}),
    do: %{field: field, kind: :has_one, target: target, name: field}

  defp association(%Ecto.Association.Has{field: field, cardinality: :many, related: target}),
    do: %{field: field, kind: :has_many, target: target, name: field}

  defp association(%Ecto.Association.ManyToMany{field: field, related: target}),
    do: %{field: field, kind: :many_to_many, target: target, name: field}
end
