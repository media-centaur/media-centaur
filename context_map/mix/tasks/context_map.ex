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

  `--page` also writes the self-contained page to `tmp/context-map.html`
  (gitignored); `--html PATH` writes it to PATH instead. Without either,
  no page is written. `--check` fails when a
  finding has no verdict or a verdict has no finding. `--verdicts PATH`
  reads verdicts from PATH instead of `docs/context-map/verdicts.json`.
  """

  alias MediaCentaur.ContextMap
  alias MediaCentaur.ContextMap.Html
  alias MediaCentaur.ContextMap.Report

  @requirements ["app.config"]

  @default_json "docs/context-map/context-map.json"
  @default_verdicts "docs/context-map/verdicts.json"
  @page_path "tmp/context-map.html"

  @impl Mix.Task
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args,
        strict: [json: :string, html: :string, page: :boolean, check: :boolean, verdicts: :string]
      )

    if rest != [], do: Mix.raise("unexpected arguments: #{inspect(rest)}")
    json_path = Keyword.get(opts, :json, @default_json)
    verdicts = Report.read_verdicts(Keyword.get(opts, :verdicts, @default_verdicts))

    analysis = ContextMap.analyse()
    document = ContextMap.document(analysis, verdicts)
    write(json_path, Jason.encode!(document, pretty: true) <> "\n")
    Mix.shell().info("context map: #{length(document.findings)} findings → #{json_path}")

    case html_path(opts) do
      nil ->
        :ok

      html_path ->
        write(html_path, Html.render(document))
        Mix.shell().info("context map: html → #{html_path}")
    end

    if opts[:check], do: check(analysis.findings, verdicts)
  end

  defp html_path(opts), do: opts[:html] || (opts[:page] && @page_path) || nil

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
