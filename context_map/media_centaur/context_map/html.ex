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
    {contexts, empty_contexts} = Enum.split_with(document.contexts, &shown?(&1, document.findings))
    consumers = consumers(contexts, document.findings)

    page(%{
      document: document,
      contexts: contexts,
      empty_contexts: Enum.map(empty_contexts, & &1.name),
      consumers: consumers,
      matrix: matrix(contexts, document.findings, consumers),
      kernel_cells: kernel_cells(document.kernel_reads),
      owners: document.findings |> Enum.map(& &1.owner) |> Enum.uniq() |> Enum.sort(),
      finding_consumers: document.findings |> Enum.map(&consumer_column/1) |> Enum.uniq() |> Enum.sort()
    })
  end

  defp h(value), do: value |> to_string() |> Plug.HTML.html_escape()

  # Matrix labels drop the prefix every context shares; data attributes keep full names.
  defp label(name), do: name |> String.replace_prefix("MediaCentaur.", "") |> h()

  defp consumer_column(finding), do: finding.consumer_context || "unresolved"

  defp shown?(context, findings) do
    context.schemas != [] or
      Enum.any?(findings, &(&1.owner == context.name or &1.consumer_context == context.name))
  end

  defp consumers(contexts, findings) do
    (Enum.map(contexts, & &1.name) ++ Enum.map(findings, &consumer_column/1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # owner → consumer → %{rule => count}
  defp matrix(contexts, findings, consumers) do
    for context <- contexts, into: %{} do
      owned = Enum.filter(findings, &(&1.owner == context.name))

      row =
        for consumer <- consumers, into: %{} do
          counts =
            owned
            |> Enum.filter(&(consumer_column(&1) == consumer))
            |> Enum.frequencies_by(& &1.rule)

          {consumer, counts}
        end

      {context.name, row}
    end
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
