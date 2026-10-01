defmodule MediaCentaur.ContextMap.Html do
  @moduledoc """
  Renders the document as one self-contained page: the context matrix,
  one panel per context with its schemas and fields, and the findings
  list. No external scripts or styles; filtering is a few lines of inline
  JS over `data-` attributes. Every value is HTML-escaped.

  A finding whose consumer context is unresolved counts in the
  `unresolved` matrix column.
  """

  require EEx

  @template Path.join(__DIR__, "templates/context_map.html.eex")
  @external_resource @template

  EEx.function_from_file(:defp, :page, @template, [:assigns])

  @doc "The document (as built by `MediaCentaur.ContextMap.document/2`) as a complete HTML page."
  @spec render(map()) :: String.t()
  def render(document) do
    consumers = consumers(document)
    matrix = matrix(document, consumers)
    page(%{document: document, consumers: consumers, matrix: matrix})
  end

  defp h(value), do: value |> to_string() |> Plug.HTML.html_escape()

  # Matrix labels drop the prefix every context shares; data attributes keep full names.
  defp label(name), do: name |> String.replace_prefix("MediaCentaur.", "") |> h()

  defp consumer_column(finding), do: finding.consumer_context || "unresolved"

  defp consumers(document) do
    (Enum.map(document.contexts, & &1.name) ++ Enum.map(document.findings, &consumer_column/1) ++ ["web"])
    |> Enum.uniq()
    |> Enum.sort()
  end

  # owner → consumer → %{rule => count}
  defp matrix(document, consumers) do
    for context <- document.contexts, into: %{} do
      owned = Enum.filter(document.findings, &(&1.owner == context.name))

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
end
