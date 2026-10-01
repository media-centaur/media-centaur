defmodule Mix.Tasks.ContextMapTest do
  use MediaCentaur.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.ContextMap

  @moduletag :tmp_dir

  test "writes the JSON document to the path given", %{tmp_dir: tmp_dir} do
    json_path = Path.join(tmp_dir, "context-map.json")
    capture_io(fn -> ContextMap.run(["--json", json_path]) end)

    assert {:ok, %{"contexts" => _, "findings" => _, "kernel_reads" => _}} =
             json_path |> File.read!() |> Jason.decode()
  end

  test "unexpected arguments raise a Mix error naming them" do
    assert_raise Mix.Error, ~r/unexpected arguments: \["stray"\]/, fn ->
      ContextMap.run(["stray"])
    end
  end

  test "--check fails when a finding has no verdict", %{tmp_dir: tmp_dir} do
    verdicts = Path.join(tmp_dir, "verdicts.json")
    File.write!(verdicts, "[]\n")

    assert_raise Mix.Error, ~r/unverdicted/, fn ->
      capture_io(fn ->
        ContextMap.run([
          "--check",
          "--verdicts",
          verdicts,
          "--json",
          Path.join(tmp_dir, "m.json")
        ])
      end)
    end
  end

  test "--html writes a page containing every finding key", %{tmp_dir: tmp_dir} do
    json_path = Path.join(tmp_dir, "context-map.json")
    html_path = Path.join(tmp_dir, "context-map.html")
    capture_io(fn -> ContextMap.run(["--json", json_path, "--html", html_path]) end)

    %{"findings" => findings} = json_path |> File.read!() |> Jason.decode!()
    html = File.read!(html_path)
    assert Enum.all?(findings, &String.contains?(html, &1["key"]))
  end

  # The analysis reads `lib/` relative to the working directory, and the
  # working directory is VM-wide, so this runs in the checkout rather than
  # changing directory; `tmp/` is gitignored.
  test "--page writes tmp/context-map.html", %{tmp_dir: tmp_dir} do
    page_path = "tmp/context-map.html"
    capture_io(fn -> ContextMap.run(["--json", Path.join(tmp_dir, "m.json"), "--page"]) end)

    assert page_path |> File.read!() |> String.contains?("<title>Context map</title>")
  end
end
