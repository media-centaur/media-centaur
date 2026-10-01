defmodule Mix.Tasks.ContextMapTest do
  use MediaCentaur.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  test "writes the JSON document to the path given", %{tmp_dir: tmp_dir} do
    json_path = Path.join(tmp_dir, "context-map.json")
    capture_io(fn -> Mix.Tasks.ContextMap.run(["--json", json_path]) end)

    assert {:ok, %{"contexts" => _, "findings" => _, "kernel_reads" => _}} =
             json_path |> File.read!() |> Jason.decode()
  end

  test "unexpected arguments raise a Mix error naming them" do
    assert_raise Mix.Error, ~r/unexpected arguments: \["stray"\]/, fn ->
      Mix.Tasks.ContextMap.run(["stray"])
    end
  end
end
