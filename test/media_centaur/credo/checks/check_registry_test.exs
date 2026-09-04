defmodule MediaCentaur.Credo.Checks.CheckRegistryTest do
  @moduledoc """
  The custom-check registry itself is a contract: an `MCNNNN` id is how
  every doc, ADR, plan and `credo:disable` comment cites a rule. An id
  shared by two checks makes every one of those citations ambiguous.
  """
  use ExUnit.Case, async: true

  @checks_dir Path.expand("../../../../credo_checks", __DIR__)

  # Only files that `use Credo.Check` are checks. `event_chokepoint.ex` is a
  # shared AST matcher three checks call into; it carries no id by design.
  defp declared_ids do
    @checks_dir
    |> Path.join("*.ex")
    |> Path.wildcard()
    |> Enum.map(fn path -> {Path.basename(path), File.read!(path)} end)
    |> Enum.filter(fn {_file, source} -> source =~ "use Credo.Check" end)
    |> Enum.map(fn {file, source} ->
      case Regex.run(~r/id:\s+"(MC\d{4})"/, source, capture: :all_but_first) do
        [id] -> {file, id}
        nil -> {file, nil}
      end
    end)
  end

  test "every custom check declares an id" do
    assert Enum.reject(declared_ids(), fn {_file, id} -> id end) == []
  end

  test "no two custom checks share an id" do
    duplicates =
      declared_ids()
      |> Enum.group_by(fn {_file, id} -> id end, fn {file, _id} -> file end)
      |> Enum.filter(fn {_id, files} -> length(files) > 1 end)
      |> Map.new()

    assert duplicates == %{}
  end
end
