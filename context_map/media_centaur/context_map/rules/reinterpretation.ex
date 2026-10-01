defmodule MediaCentaur.ContextMap.Rules.Reinterpretation do
  @moduledoc """
  R3 — a context never interprets another context's values.

  For every `Ecto.Enum` field of a non-kernel schema, each bare literal of
  one of its values in a file outside the owning context is a finding.
  *Anchored* when the line names the field or the file references the
  owning schema module; otherwise reported only when that value is
  declared by exactly one schema field in the whole application, so a
  vocabulary shared by many schemas does not flood the map.

  A value declared by schemas in two or more contexts is shared vocabulary
  and has no owner; R3 does not report it. A value declared by several
  schemas of one context still belongs to that context.
  Files outside every context (`context: nil`) are not read.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Schemas
  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Walk

  @doc "Every R3 finding of `sources` against the enum fields of `schemas`."
  @spec findings([Schema.t()], [Source.t()]) :: [Finding.t()]
  def findings(schemas, sources) do
    owners = Schemas.value_owners(schemas)
    shared = shared_values(schemas, owners)

    enum_fields =
      for schema <- schemas,
          not Contexts.kernel?(schema.context),
          %{values: values} = field when is_list(values) <- schema.fields,
          do: {schema, field}

    findings =
      for %Source{context: context} = source when not is_nil(context) <- sources,
          mention <- Walk.mentions(source),
          mention.kind == :value,
          {schema, field} <- enum_fields,
          schema.context != context,
          mention.atom in field.values,
          not MapSet.member?(shared, mention.atom),
          anchored? <- [anchored?(source, mention, schema, field)],
          anchored? or length(owners[mention.atom]) == 1 do
        %Finding{
          rule: "R3",
          owner: schema.context,
          schema: schema.module,
          field: field.name,
          value: mention.atom,
          consumer: List.first(source.modules),
          consumer_context: context,
          anchored?: anchored?,
          file: source.path,
          line: mention.line,
          excerpt: source |> Source.line(mention.line) |> String.trim()
        }
      end

    findings
    |> Enum.uniq_by(&{Finding.key(&1), &1.line})
    |> Enum.sort_by(&{Finding.key(&1), &1.line})
  end

  # Values whose declaring schemas span two or more contexts.
  defp shared_values(schemas, owners) do
    context_of = Map.new(schemas, &{&1.module, &1.context})

    for {value, declared_by} <- owners,
        declared_by |> Enum.map(fn {module, _field} -> context_of[module] end) |> Enum.uniq() |> length() >=
          2,
        into: MapSet.new(),
        do: value
  end

  defp anchored?(source, mention, schema, field) do
    line_text = Source.line(source, mention.line)

    String.contains?(line_text, Atom.to_string(field.name)) or
      MapSet.member?(source.references, schema.module)
  end
end
