defmodule MediaCentaur.ContextMap.Rules.CrossContextKey do
  @moduledoc """
  R4 — keys follow ownership and the dependency direction; R2 — keys into
  the shared kernel are references, not crossings.

  Associations resolve to their target schema; an association's key field
  is its foreign key for `belongs_to`, its name otherwise. A `<stem>_id` /
  `<stem>_ids` field without an association resolves to the table-backed
  schema whose module's last segment (underscored) equals the stem;
  embedded schemas are not key targets. A `<stem>_type` enum beside it
  resolves each value the same way. `tmdb_id`, `imdb_id`, `tvdb_id` and `tmdb_person_id` are
  external identity. A key the resolver cannot place is reported
  unresolved rather than guessed.
  """

  alias MediaCentaur.ContextMap.Context
  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schema

  @external [:tmdb_id, :imdb_id, :tvdb_id, :tmdb_person_id]

  @type kernel_read :: %{
          schema: module(),
          field: atom(),
          target: module() | :external,
          owner: module() | nil
        }

  @doc """
  Every key of `schemas`, split into R4 findings (a key into another
  non-kernel context, or an unresolved key) and kernel reads (a key into
  the shared kernel, or an external identifier). Keys within the owner's
  own context are neither.
  """
  @spec findings([Schema.t()], [Context.t()]) :: {[Finding.t()], [kernel_read()]}
  def findings(schemas, contexts) do
    deps = Map.new(contexts, &{&1.name, &1.deps})
    by_stem = stems(schemas)

    {findings, reads} =
      schemas
      |> Enum.flat_map(&keys(&1, by_stem))
      |> Enum.reduce({[], []}, fn key, {findings, reads} ->
        case classify(key, deps) do
          :same_context -> {findings, reads}
          {:kernel_read, read} -> {findings, [read | reads]}
          {:finding, finding} -> {[finding | findings], reads}
        end
      end)

    {Enum.sort_by(findings, &Finding.key/1),
     Enum.sort_by(reads, &{inspect(&1.schema), &1.field, inspect(&1.target)})}
  end

  # --- enumerate every key on a schema: {schema, field, target | :external | :unresolved} ---

  defp keys(%Schema{} = schema, by_stem) do
    assoc_fields = MapSet.new(schema.associations, &association_field/1)

    from_assocs =
      for assoc <- schema.associations, do: {schema, association_field(assoc), assoc.target}

    from_fields =
      for %{name: name} <- schema.fields,
          not MapSet.member?(assoc_fields, name),
          stem <- [stem(name)],
          stem != nil,
          key <- field_keys(schema, name, stem, by_stem),
          do: key

    from_assocs ++ from_fields
  end

  defp association_field(assoc), do: assoc.foreign_key || assoc.name

  defp field_keys(schema, name, stem, by_stem) do
    cond do
      name in @external ->
        [{schema, name, :external}]

      values = discriminator_values(schema, stem) ->
        Enum.uniq(for value <- values, do: {schema, name, resolve(Atom.to_string(value), by_stem)})

      true ->
        [{schema, name, resolve(stem, by_stem)}]
    end
  end

  # The values of the `<stem>_type` enum field, nil when there is none.
  # Compared as strings so no atom is created.
  defp discriminator_values(schema, stem) do
    discriminator = stem <> "_type"

    Enum.find_value(schema.fields, fn
      %{name: name, values: values} when is_list(values) ->
        if Atom.to_string(name) == discriminator, do: values

      _ ->
        nil
    end)
  end

  defp stem(name) do
    case Regex.run(~r/^(.+)_ids?$/, Atom.to_string(name)) do
      [_, stem] -> stem
      nil -> nil
    end
  end

  defp stems(schemas) do
    for schema <- schemas, schema.table != nil, reduce: %{} do
      acc ->
        Map.update(acc, module_stem(schema.module), [schema.module], &[schema.module | &1])
    end
  end

  defp module_stem(module), do: module |> Module.split() |> List.last() |> Macro.underscore()

  defp resolve(stem, by_stem) do
    case Map.get(by_stem, stem, []) do
      [target] -> target
      _ -> :unresolved
    end
  end

  # --- classify a key by where it points ---

  defp classify({schema, field, :external}, _deps),
    do: {:kernel_read, kernel_read(schema, field, :external)}

  defp classify({schema, field, :unresolved}, _deps),
    do: {:finding, finding(schema, field, %{unresolved: true})}

  defp classify({schema, field, target}, deps) do
    target_context = Contexts.context_of(target)

    cond do
      target_context == schema.context ->
        :same_context

      Contexts.kernel?(target_context) ->
        {:kernel_read, kernel_read(schema, field, target)}

      true ->
        in_deps? = target_context in Map.get(deps, schema.context, [])

        {:finding,
         finding(schema, field, %{target: target, target_context: target_context, in_deps: in_deps?})}
    end
  end

  defp kernel_read(schema, field, target),
    do: %{schema: schema.module, field: field, target: target, owner: schema.context}

  defp finding(schema, field, detail) do
    %Finding{
      rule: "R4",
      owner: schema.context,
      schema: schema.module,
      field: field,
      consumer: nil,
      consumer_context: Map.get(detail, :target_context),
      file: schema.file,
      line: 1,
      detail: detail
    }
  end
end
