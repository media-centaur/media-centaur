defmodule MediaCentaur.ContextMap.Rules.ForeignField do
  @moduledoc """
  R1 — each context keeps its own representation; it never adds a field
  to another context's table for its own need.

  Every mention of a field name is attributed to the mentioning file's
  context. A read is a dot access or a key in a pattern; a write is a key
  in an expression (an attrs map), or the field atom on a line that calls
  `cast(`, `put_change(` or `force_change(`. The schema's own file does
  not count. A field name declared by more than one schema counts only
  files that reference the owning schema module.

  Findings: `:owner_never_reads` (non-kernel schemas only) and one
  `:foreign_write` per non-owner context that writes the field.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Walk

  @write_calls ["cast(", "put_change(", "force_change("]

  @type site :: {module() | :web, module() | nil, String.t(), pos_integer(), :read | :write}
  @type usage :: %{
          reads: %{(module() | :web) => non_neg_integer()},
          writes: %{(module() | :web) => non_neg_integer()},
          sites: [site()]
        }

  @doc "Per `{schema_module, field}`: read and write counts by context, and every site."
  @spec usage([Schema.t()], [Source.t()]) :: %{{module(), atom()} => usage()}
  def usage(schemas, sources) do
    declared_by =
      for schema <- schemas, field <- schema.fields, reduce: %{} do
        acc -> Map.update(acc, field.name, [schema.module], &[schema.module | &1])
      end

    parsed = for source <- sources, source.context != nil, do: {source, Walk.mentions(source)}

    for schema <- schemas, field <- schema.fields, into: %{} do
      schema_file = schema_file(schema)

      sites =
        for {source, mentions} <- parsed,
            source.path != schema_file,
            distinctive?(declared_by, field.name) or
              MapSet.member?(source.references, schema.module),
            mention <- mentions,
            mention.atom == field.name,
            access <- [access(mention, source)],
            access != nil do
          {source.context, List.first(source.modules), source.path, mention.line, access}
        end

      {{schema.module, field.name},
       %{
         reads: count_by_context(sites, :read),
         writes: count_by_context(sites, :write),
         sites: Enum.sort(sites)
       }}
    end
  end

  @doc "Every R1 finding: `:owner_never_reads` and `:foreign_write`, sorted by verdict key."
  @spec findings([Schema.t()], [Source.t()]) :: [Finding.t()]
  def findings(schemas, sources) do
    usage = usage(schemas, sources)

    Enum.sort_by(
      for schema <- schemas,
          field <- schema.fields,
          finding <- field_findings(schema, field, usage[{schema.module, field.name}]) do
        finding
      end,
      &Finding.key/1
    )
  end

  defp field_findings(schema, field, field_usage) do
    never_read =
      if not Contexts.kernel?(schema.context) and Map.get(field_usage.reads, schema.context, 0) == 0 do
        [
          finding(schema, field, schema.context, nil, schema_file(schema), 1, %{
            kind: :owner_never_reads
          })
        ]
      else
        []
      end

    foreign_writes =
      for {context, module, path, line, :write} <- field_usage.sites,
          context != schema.context,
          uniq: true do
        {context, module, path, line}
      end
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map(fn {context, module, path, line} ->
        finding(schema, field, context, module, path, line, %{kind: :foreign_write})
      end)

    never_read ++ foreign_writes
  end

  defp count_by_context(sites, access) do
    sites |> Enum.filter(&(elem(&1, 4) == access)) |> Enum.frequencies_by(&elem(&1, 0))
  end

  defp access(%{kind: :dot}, _source), do: :read
  defp access(%{kind: :key, pattern?: true}, _source), do: :read
  defp access(%{kind: :key, pattern?: false}, _source), do: :write

  defp access(%{kind: :value, line: line}, source) do
    text = Enum.at(source.lines, line - 1, "")
    if Enum.any?(@write_calls, &String.contains?(text, &1)), do: :write
  end

  defp distinctive?(declared_by, name), do: length(Map.get(declared_by, name, [])) == 1

  defp schema_file(%Schema{module: module}),
    do: module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd()

  defp finding(schema, field, context, module, path, line, detail) do
    %Finding{
      rule: "R1",
      owner: schema.context,
      schema: schema.module,
      field: field.name,
      consumer: module,
      consumer_context: context,
      file: path,
      line: line,
      detail: detail
    }
  end
end
