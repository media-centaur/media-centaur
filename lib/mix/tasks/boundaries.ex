defmodule Mix.Tasks.Boundaries do
  @shortdoc "Check JS input system import boundaries"
  use Boundary, top_level?: true, check: [in: false, out: false]
  use Mix.Task

  @impl true
  def run(_) do
    {output, status} =
      System.cmd(
        "bunx",
        ["dependency-cruiser", "assets/js/input/", "--config", ".dependency-cruiser.cjs"],
        stderr_to_stdout: true
      )

    IO.puts(output)

    if status != 0 do
      Mix.raise("Import boundary violation detected")
    end
  end
end
