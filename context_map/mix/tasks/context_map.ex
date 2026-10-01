defmodule Mix.Tasks.ContextMap do
  @shortdoc "Generate the context map (schemas by context, boundary crossings)"
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @moduledoc """
  Generates `docs/context-map/context-map.json`, or the path given with
  `--json PATH`.

      mix context_map
      mix context_map --json tmp/context-map.json
  """

  alias MediaCentaur.ContextMap.Report

  @requirements ["app.config"]

  @default_json "docs/context-map/context-map.json"
  @verdicts_path "docs/context-map/verdicts.json"

  @impl Mix.Task
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: [json: :string])
    json_path = Keyword.get(opts, :json, @default_json)

    document = MediaCentaur.ContextMap.build(Report.read_verdicts(@verdicts_path))
    File.mkdir_p!(Path.dirname(json_path))
    File.write!(json_path, Jason.encode!(document, pretty: true) <> "\n")
    Mix.shell().info("context map: #{length(document.findings)} findings → #{json_path}")
  end
end
