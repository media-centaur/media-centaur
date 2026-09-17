defmodule Mix.Tasks.Boundaries do
  @shortdoc "Check JS import boundaries and reachability"
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @impl true
  def run(_) do
    {output, status} =
      System.cmd(
        "bunx",
        ["dependency-cruiser", "assets/js/", "--config", ".dependency-cruiser.cjs"],
        stderr_to_stdout: true
      )

    IO.puts(output)

    if status != 0 do
      Mix.raise("Import boundary violation detected")
    end
  end
end
