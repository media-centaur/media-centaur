defmodule MediaCentaur.ContextMap.Rules.ForeignField do
  @moduledoc """
  R1 — each context keeps its own representation; it never adds a field
  to another context's table for its own need.

  Every mention of a field name is attributed to the mentioning file's
  context. A read is a dot access, a key in a pattern, a keyword key in an
  expression (`where: [rung: ^x]`, `get_by(S, rung: x)`), or the field
  atom on a line that calls `Map.` / `Keyword.` `get`, `fetch`, `fetch!`,
  `has_key?`, `take` or `pop`. A write is a key of a map or struct literal
  in an expression (an attrs map), or the field atom on a line that calls
  `cast(`, `put_change(` or `force_change(` (a bare call or
  `Changeset.cast(`; `broadcast(`, `GenServer.cast(` and the like are
  not). The schema's own file does not count.

  A field name is distinctive when exactly one schema declares it and no
  `defstruct` outside that schema's file declares it. A field name that is
  not distinctive counts only files that reference the owning schema
  module.

  Findings: `:owner_never_reads` (non-kernel schemas only), pointing at the
  field's declaration, and one `:foreign_write` per non-owner context that
  writes the field, at its first write site with that line as the excerpt.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Walk

  @write_call ~r/(?<![\w.])(cast|put_change|force_change)\(|Changeset\.cast\(/
  @read_call ~r/\b(Map|Keyword)\.(get|fetch|fetch!|has_key\?|take|pop)\(/

  @type site ::
          {module() | :web, module() | nil, String.t(), pos_integer(), :read | :write, String.t()}
  @type usage :: %{
          reads: %{(module() | :web) => non_neg_integer()},
          writes: %{(module() | :web) => non_neg_integer()},
          sites: [site()]
        }

  @doc "Per `{schema_module, field}`: read and write counts by context, and every site with its trimmed line."
  @spec usage([Schema.t()], [Source.t()]) :: %{{module(), atom()} => usage()}
  def usage(schemas, sources) do
    declared_by =
      for schema <- schemas, field <- schema.fields, reduce: %{} do
        acc -> Map.update(acc, field.name, [schema.module], &[schema.module | &1])
      end

    struct_declared_in =
      for source <- sources, key <- source.struct_keys, reduce: %{} do
        acc -> Map.update(acc, key, [source.path], &[source.path | &1])
      end

    parsed = for source <- sources, source.context != nil, do: {source, Walk.mentions(source)}

    for schema <- schemas, field <- schema.fields, into: %{} do
      distinctive? = distinctive?(declared_by, struct_declared_in, schema, field.name)

      sites =
        for {source, mentions} <- parsed,
            source.path != schema.file,
            distinctive? or MapSet.member?(source.references, schema.module),
            mention <- mentions,
            mention.atom == field.name,
            access <- [access(mention, source)],
            access != nil do
          {source.context, List.first(source.modules), source.path, mention.line, access,
           source |> Source.line(mention.line) |> String.trim()}
        end

      {{schema.module, field.name},
       %{
         reads: count_by_context(sites, :read),
         writes: count_by_context(sites, :write),
         sites: Enum.sort(sites)
       }}
    end
  end

  @doc """
  Every R1 finding — `:owner_never_reads` and `:foreign_write` — from the
  `usage/2` table of `schemas`, sorted by verdict key.
  """
  @spec findings([Schema.t()], %{{module(), atom()} => usage()}) :: [Finding.t()]
  def findings(schemas, usage) do
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
        declaration = %{
          context: schema.context,
          module: nil,
          file: schema.file,
          line: field.line,
          excerpt: field.declaration
        }

        [finding(schema, field, declaration, %{kind: :owner_never_reads})]
      else
        []
      end

    foreign_writes =
      for {context, module, path, line, :write, excerpt} <- field_usage.sites,
          context != schema.context do
        %{context: context, module: module, file: path, line: line, excerpt: excerpt}
      end
      |> Enum.uniq_by(& &1.context)
      |> Enum.map(&finding(schema, field, &1, %{kind: :foreign_write}))

    never_read ++ foreign_writes
  end

  defp count_by_context(sites, access) do
    sites |> Enum.filter(&(elem(&1, 4) == access)) |> Enum.frequencies_by(&elem(&1, 0))
  end

  defp access(%{kind: :dot}, _source), do: :read
  defp access(%{kind: :key, pattern?: true}, _source), do: :read
  defp access(%{kind: :key, map?: true}, _source), do: :write
  defp access(%{kind: :key}, _source), do: :read

  defp access(%{kind: :value, line: line}, source) do
    text = Source.line(source, line)

    cond do
      Regex.match?(@write_call, text) -> :write
      Regex.match?(@read_call, text) -> :read
      true -> nil
    end
  end

  # Declared by exactly one schema and by no `defstruct` outside that
  # schema's own file.
  defp distinctive?(declared_by, struct_declared_in, schema, name) do
    length(Map.get(declared_by, name, [])) == 1 and
      Enum.all?(Map.get(struct_declared_in, name, []), &(&1 == schema.file))
  end

  defp finding(schema, field, site, detail) do
    %Finding{
      rule: "R1",
      owner: schema.context,
      schema: schema.module,
      field: field.name,
      consumer: site.module,
      consumer_context: site.context,
      file: site.file,
      line: site.line,
      excerpt: site.excerpt,
      detail: detail
    }
  end
end
