defmodule MediaCentaur.ContextMap.Html do
  @moduledoc """
  Renders the document as one self-contained page: the context matrix,
  one panel per context with its schemas and fields, and the findings
  list. No external scripts or styles; filtering is a few lines of inline
  JS over `data-` attributes. Every value is HTML-escaped.

  The matrix shows only contexts that own a schema or take part in a
  finding; the rest are named in one line under it. A finding whose
  consumer context is unresolved counts in the `unresolved` column. A
  kernel read shades the cell from its owner to the context of its target
  schema (`MediaCentaur.<Name>`, the target's first two segments); reads
  of external identifiers have no column. Clicking a cell filters the
  findings list to that owner → consumer pair.
  """

  require EEx

  @template Path.join(__DIR__, "templates/context_map.html.eex")
  @external_resource @template

  EEx.function_from_file(:defp, :page, @template, [:assigns])

  @doc "The document (as built by `MediaCentaur.ContextMap.document/2`) as a complete HTML page."
  @spec render(map()) :: String.t()
  def render(document) do
    findings = document.findings
    matrix = matrix(findings)
    involved = matrix |> Map.keys() |> Enum.flat_map(&Tuple.to_list/1) |> MapSet.new()

    {contexts, empty_contexts} =
      Enum.split_with(document.contexts, &(&1.schemas != [] or &1.name in involved))

    pairs = Map.keys(matrix)

    page(%{
      document: document,
      contexts: contexts,
      empty_contexts: Enum.map(empty_contexts, & &1.name),
      consumers: sorted_unique(Enum.map(contexts, & &1.name) ++ Enum.map(pairs, &elem(&1, 1))),
      matrix: matrix,
      kernel_cells: kernel_cells(document.kernel_reads),
      findings_by_field: Enum.group_by(findings, &{&1.schema, &1.field}),
      sorted_findings: Enum.sort_by(findings, &{not is_nil(&1.verdict), &1.key}),
      owners: sorted_unique(Enum.map(pairs, &elem(&1, 0))),
      finding_consumers: sorted_unique(Enum.map(pairs, &elem(&1, 1)))
    })
  end

  defp h(value), do: value |> to_string() |> Plug.HTML.html_escape()

  # Matrix labels drop the prefix every context shares; data attributes keep full names.
  defp label(name), do: name |> String.replace_prefix("MediaCentaur.", "") |> h()

  # The matrix column a finding counts in.
  defp consumer_column(finding), do: finding.consumer_context || "unresolved"

  # A field chip names the consuming module when there is one, else its column.
  defp consumer_label(finding), do: finding.consumer || consumer_column(finding)

  defp cell_class(owner, consumer, kernel_count) do
    Enum.join(
      for({class, true} <- [{"diag", owner == consumer}, {"kernel", kernel_count != nil}], do: class),
      " "
    )
  end

  # A field's reads or writes, `%{context => count}`, as "context count, …".
  defp counts(by_context),
    do:
      Enum.map_join(Enum.sort(by_context), ", ", fn {context, count} -> "#{h(context)} #{h(count)}" end)

  defp sorted_unique(list), do: list |> Enum.uniq() |> Enum.sort()

  # {owner, consumer column} → %{rule => count}
  defp matrix(findings) do
    findings
    |> Enum.group_by(&{&1.owner, consumer_column(&1)}, & &1.rule)
    |> Map.new(fn {pair, rules} -> {pair, Enum.frequencies(rules)} end)
  end

  # {owner, target context} → kernel read count
  defp kernel_cells(kernel_reads) do
    Enum.frequencies(
      for read <- kernel_reads, read.target != "external" do
        {read.owner, read.target |> String.split(".") |> Enum.take(2) |> Enum.join(".")}
      end
    )
  end
end
