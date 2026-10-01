defmodule Mix.Tasks.ContextMap do
  @shortdoc "Generate the context map (schemas by context, boundary crossings)"
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @moduledoc """
  Generates `docs/context-map/context-map.json`, or the path given with
  `--json PATH`.

      mix context_map
      mix context_map --json tmp/context-map.json
      mix context_map --page
      mix context_map --html path/to/context-map.html
      mix context_map --check
      mix context_map --list

  `--page` also writes the self-contained page to `tmp/context-map.html`
  (gitignored); `--html PATH` writes it to PATH instead. Without either,
  no page is written. `--verdicts PATH` reads verdicts from PATH instead
  of `docs/context-map/verdicts.json`.

  Query modes answer a question and write nothing unless an output is
  named explicitly with `--json`, `--html` or `--page`:

    * `--check` fails when a finding has no verdict or a verdict has no
      finding.
    * `--list` prints one `path:line: RULE schema.field[ = value] — summary`
      line per site, sorted by path then line, for an editor's jump list.
  """

  alias MediaCentaur.ContextMap
  alias MediaCentaur.ContextMap.Html
  alias MediaCentaur.ContextMap.Report

  @requirements ["app.config"]

  @default_json "docs/context-map/context-map.json"
  @default_verdicts "docs/context-map/verdicts.json"
  @page_path "tmp/context-map.html"

  @query_modes [:list, :check]

  @impl Mix.Task
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args,
        strict: [
          json: :string,
          html: :string,
          page: :boolean,
          check: :boolean,
          list: :boolean,
          verdicts: :string
        ]
      )

    if rest != [], do: Mix.raise("unexpected arguments: #{inspect(rest)}")
    verdicts = Report.read_verdicts(Keyword.get(opts, :verdicts, @default_verdicts))

    analysis = ContextMap.analyse()
    document = ContextMap.document(analysis, verdicts)
    write_json(document, json_path(opts))
    write_html(document, html_path(opts))
    if opts[:list], do: list(document.findings)
    if opts[:check], do: check(analysis.findings, verdicts)
  end

  defp json_path(opts) do
    cond do
      opts[:json] -> opts[:json]
      Enum.any?(@query_modes, &opts[&1]) -> nil
      true -> @default_json
    end
  end

  defp html_path(opts) do
    cond do
      opts[:html] -> opts[:html]
      opts[:page] -> @page_path
      true -> nil
    end
  end

  defp write_json(_document, nil), do: :ok

  defp write_json(document, path) do
    write(path, Report.to_json(document) <> "\n")
    Mix.shell().info("context map: #{length(document.findings)} findings → #{path}")
  end

  defp write_html(_document, nil), do: :ok

  defp write_html(document, path) do
    write(path, Html.render(document))
    Mix.shell().info("context map: html → #{path}")
  end

  defp list(findings), do: for(line <- Report.list_lines(findings), do: Mix.shell().info(line))

  defp write(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp check(findings, verdicts) do
    case Report.check(findings, verdicts) do
      :ok ->
        Mix.shell().info("context map: every finding has a verdict")

      {:error, %{unverdicted: unverdicted, stale: stale}} ->
        Mix.raise("""
        context map check failed
          unverdicted: #{inspect(unverdicted, pretty: true)}
          stale: #{inspect(stale, pretty: true)}\
        """)
    end
  end
end
