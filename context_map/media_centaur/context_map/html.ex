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
  findings to that owner → consumer pair.

  Findings are grouped by concept (`{rule, schema, field, value}`, the
  concept key), then by consumer (the verdict key), then by site, each site
  with its excerpt. Concepts with an unverdicted finding come first. Filters
  act on sites; a consumer or concept with no visible site is hidden.

  A verdict supplied by the concept key (`verdict_key` equal to the
  concept key) shows once on the concept as its concept verdict; a consumer
  with its own exact verdict shows it, marked as overriding the concept
  verdict when the concept has one.
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
      concepts: concepts(findings),
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

  # What a consumer group is, in words: the consuming module, or for R1 and
  # R4 the kind of crossing.
  defp consumer_heading(%{rule: "R4", detail: %{unresolved: true}}), do: "unresolved key"

  defp consumer_heading(%{rule: "R4", detail: %{target: target} = detail}),
    do: "keys into #{target}#{if detail[:in_deps] == false, do: " (not in deps)"}"

  defp consumer_heading(%{rule: "R1", detail: %{kind: "owner_never_reads"}}),
    do: "never read by its owner"

  defp consumer_heading(%{rule: "R1", detail: %{kind: "foreign_write"}} = finding),
    do: "written from #{consumer_label(finding)}"

  defp consumer_heading(finding), do: consumer_label(finding)

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(count, noun), do: "#{count} #{noun}s"

  # concept key → consumers (by verdict key) → sites (by file, line). Each
  # group keeps one `representative` finding for the facts its members share;
  # a concept's `verdict` is a member whose verdict came from the concept key.
  defp concepts(findings) do
    findings
    |> Enum.group_by(& &1.concept_key)
    |> Enum.map(fn {concept_key, members} ->
      consumers =
        members
        |> Enum.group_by(& &1.key)
        |> Enum.map(fn {key, sites} ->
          %{key: key, representative: hd(sites), sites: Enum.sort_by(sites, &{&1.file, &1.line})}
        end)
        |> Enum.sort_by(& &1.key)

      %{
        key: concept_key,
        representative: hd(members),
        consumers: consumers,
        verdict: Enum.find(members, &(&1.verdict_key == concept_key)),
        site_count: length(members),
        unverdicted?: Enum.any?(members, &is_nil(&1.verdict))
      }
    end)
    |> Enum.sort_by(&{not &1.unverdicted?, &1.key})
  end

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
