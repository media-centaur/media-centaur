defmodule MediaCentaur.Credo.Checks.NoMarkupSubstringAssertion do
  use Credo.Check,
    id: "MC0024",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Don't assert on HTML attributes by substring-matching the rendered
      string. Use the LiveViewTest element API, which parses the document.

          # NOT preferred
          assert html =~ "phx-click=\\"retry_search\\""
          refute html =~ "data-nav-zone=\\"zone-tabs\\""

          # preferred
          assert has_element?(view, "[phx-click='retry_search']")
          refute has_element?(view, "[data-nav-zone='zone-tabs']")

      `=~` on markup is weaker than it looks. It matches anywhere in the
      document, so it passes when the attribute lands on the wrong element;
      it is blind to nesting; and it breaks on attribute reordering or a
      switch between single and double quotes — none of which change the
      page. `has_element?/2` says what you actually mean.

      **Asserting on user-visible copy is fine and stays fine** —
      `assert html =~ "Connect a download client"` is a legitimate
      assertion about what the user reads. This check only fires on
      *attribute-shaped* literals: a `data-`/`phx-` attribute name, or a
      `class=`/`id=` attribute. Strings that merely resemble markup —
      redaction placeholders like `<path>`, query fragments like `rid=7`,
      words containing `data-` like `metadata-activity` — are left alone.

      Test files only.

      Source: the 2026-08 audit-remediation campaign, Stage 4 (campaign
      retired; see git history).
      """
    ]

  # `data-`/`phx-` attribute names must start a word, so `metadata-activity`
  # does not count; `class=`/`id=` must be followed by a quote, so `rid=7`
  # and prose containing "id=" do not either.
  @markup ~r/(?:^|[^a-z])(?:data|phx)-[a-z0-9-]+|(?:^|[^a-z])(?:class|id)=\\?["']/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_path?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_path?(filename) do
    String.starts_with?(filename, "test/") or String.contains?(filename, "/test/")
  end

  defp traverse({:=~, meta, [_subject, literal]} = ast, issues, issue_meta) when is_binary(literal) do
    if Regex.match?(@markup, literal) do
      {ast, [issue_for(issue_meta, literal, meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, literal, line_no) do
    format_issue(
      issue_meta,
      message:
        "`=~ #{inspect(literal)}` substring-matches markup. Use " <>
          "`has_element?(view, selector)` — it parses the document, so it can't " <>
          "match the wrong element or break on attribute order. Asserting on " <>
          "user-visible copy with `=~` is still fine.",
      trigger: literal,
      line_no: line_no
    )
  end
end
