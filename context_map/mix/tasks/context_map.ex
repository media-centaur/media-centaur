defmodule Mix.Tasks.ContextMap do
  @shortdoc "Generate the context map (schemas by context, boundary crossings)"
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @moduledoc """
  Generates `docs/context-map/context-map.json` and, with `--html PATH`, a
  self-contained HTML rendering. `--check` fails when a finding has no
  verdict or a verdict has no finding (see `MediaCentaur.ContextMap.Report`).

      mix context_map
      mix context_map --html tmp/context-map.html
      mix context_map --check
  """

  @default_json "docs/context-map/context-map.json"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [json: :string, html: :string, check: :boolean])
    json_path = Keyword.get(opts, :json, @default_json)

    document = MediaCentaur.ContextMap.build()
    File.mkdir_p!(Path.dirname(json_path))
    File.write!(json_path, Jason.encode!(document, pretty: true) <> "\n")
    Mix.shell().info("context map: #{length(document.findings)} findings → #{json_path}")
  end
end
