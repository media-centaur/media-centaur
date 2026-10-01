defmodule MediaCentaur.ContextMap.Rules.Reinterpretation do
  @moduledoc """
  R3 — a context never interprets another context's values.

  For every `Ecto.Enum` field of a non-kernel schema, each bare literal of
  one of its values in a file outside the owning context is a finding.
  *Anchored* when the line names the field or the file references the
  owning schema module; otherwise reported only when that value is
  declared by exactly one schema field in the whole application, so a
  vocabulary shared by many schemas (`:movie`) does not flood the map.
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

    enum_fields =
      for schema <- schemas,
          not Contexts.kernel?(schema.context),
          %{values: values} = field when is_list(values) <- schema.fields,
          do: {schema, field}

    Enum.uniq_by(
      for %Source{context: context} = source when not is_nil(context) <- sources,
          mention <- Walk.mentions(source),
          mention.kind == :value,
          {schema, field} <- enum_fields,
          schema.context != context,
          mention.atom in field.values,
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
          line: mention.line
        }
      end,
      &{Finding.key(&1), &1.line}
    )
  end

  defp anchored?(source, mention, schema, field) do
    line_text = Enum.at(source.lines, mention.line - 1, "")

    String.contains?(line_text, Atom.to_string(field.name)) or
      MapSet.member?(source.references, schema.module)
  end
end
