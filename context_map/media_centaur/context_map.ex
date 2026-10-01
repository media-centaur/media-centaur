defmodule MediaCentaur.ContextMap do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The context map: every Ecto schema by owning bounded context, and every
  crossing of a context boundary at the data level. Dev/test only — the
  `context_map/` directory is compiled by `elixirc_paths/1` for `:dev` and
  `:test`, like `credo_checks/`, and nothing under `lib/` references it.

  Design: `docs/superpowers/specs/2026-09-30-context-map-design.md`.
  Entry point: `mix context_map`.
  """

  alias MediaCentaur.ContextMap.Contexts
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Report
  alias MediaCentaur.ContextMap.Rules
  alias MediaCentaur.ContextMap.Schemas
  alias MediaCentaur.ContextMap.Sources
  alias MediaCentaur.ContextMap.Surfaces

  @doc """
  Runs every reader and rule once: the contexts, schemas, sources, field
  usage, kernel reads, and the findings with their surfaces joined, sorted
  by verdict key then line. Nothing in it depends on time or machine.
  """
  @spec analyse() :: %{
          contexts: [MediaCentaur.ContextMap.Context.t()],
          schemas: [MediaCentaur.ContextMap.Schema.t()],
          sources: [MediaCentaur.ContextMap.Source.t()],
          usage: map(),
          kernel_reads: [map()],
          findings: [Finding.t()]
        }
  def analyse do
    contexts = Contexts.all()
    schemas = Schemas.all()
    sources = Sources.all()
    surfaces = Surfaces.index(sources)
    usage = Rules.ForeignField.usage(schemas, sources)

    {key_findings, kernel_reads} = Rules.CrossContextKey.findings(schemas, contexts)

    findings =
      (Rules.Reinterpretation.findings(schemas, sources) ++
         key_findings ++ Rules.ForeignField.findings(schemas, usage))
      |> Enum.map(&%{&1 | surfaces: Map.get(surfaces, &1.consumer, [])})
      |> Enum.sort_by(&{Finding.key(&1), &1.line})

    %{
      contexts: contexts,
      schemas: schemas,
      sources: sources,
      usage: usage,
      kernel_reads: kernel_reads,
      findings: findings
    }
  end

  @doc """
  Encodes an `analyse/0` result as the document map ready for
  `Jason.encode!/2`, joining findings with `verdicts` (see
  `Report.read_verdicts/1`).
  """
  @spec document(map(), %{String.t() => map()}) :: map()
  def document(analysis, verdicts) do
    %{
      contexts: Enum.map(analysis.contexts, &encode_context(&1, analysis.schemas, analysis.usage)),
      kernel_reads: Enum.map(analysis.kernel_reads, &encode_kernel_read/1),
      findings: Report.encode_findings(analysis.findings, verdicts)
    }
  end

  defp encode_kernel_read(read) do
    %{
      owner: Report.name(read.owner),
      schema: Report.name(read.schema),
      field: Report.name(read.field),
      target: Report.name(read.target)
    }
  end

  defp encode_context(context, schemas, usage) do
    %{
      name: Report.name(context.name),
      kernel: context.kernel?,
      deps: Enum.map(context.deps, &Report.name/1),
      exports: Enum.map(context.exports, &Report.name/1),
      schemas: for(schema <- schemas, schema.context == context.name, do: encode_schema(schema, usage))
    }
  end

  defp encode_schema(schema, usage) do
    %{
      module: Report.name(schema.module),
      file: schema.file,
      table: schema.table,
      fields: Enum.map(schema.fields, &encode_field(&1, usage[{schema.module, &1.name}])),
      associations: Enum.map(schema.associations, &encode_association/1)
    }
  end

  defp encode_field(field, use) do
    %{
      name: Report.name(field.name),
      type: field.type,
      values: field.values && Enum.map(field.values, &Report.name/1),
      reads: encode_counts(use.reads),
      writes: encode_counts(use.writes)
    }
  end

  defp encode_counts(counts),
    do: Map.new(counts, fn {context, count} -> {Report.name(context), count} end)

  defp encode_association(association) do
    %{
      name: Report.name(association.name),
      kind: Report.name(association.kind),
      target: Report.name(association.target),
      foreign_key: Report.name(association.foreign_key)
    }
  end
end
