defmodule MediaCentarr.Credo.Checks.NoAbbreviatedNamesTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.NoAbbreviatedNames

  describe "clean code (negative cases)" do
    test "fully-spelled parameter names are allowed" do
      """
      defmodule Sample do
        def process(file, movie, episode, season, result), do: {file, movie, episode, season, result}
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> refute_issues()
    end

    test "universal idioms are exempt" do
      """
      defmodule Sample do
        def lookup(id, pid, ref) do
          fn acc, msg -> {id, pid, ref, acc, msg} end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> refute_issues()
    end

    test "underscore-prefixed unused variables are allowed" do
      """
      defmodule Sample do
        def callback(_wf, _e), do: :ok
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "abbreviated parameter `wf` is reported" do
      """
      defmodule Sample do
        def process(wf), do: wf
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issue()
    end

    test "abbreviated parameter `e` is reported" do
      """
      defmodule Sample do
        def process(e), do: e.id
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issue()
    end

    test "abbreviated parameter `ep` is reported" do
      """
      defmodule Sample do
        def process(ep), do: ep
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issue()
    end

    test "multiple abbreviated parameters report multiple issues" do
      """
      defmodule Sample do
        def process(wf, e, ep), do: {wf, e, ep}
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issues(fn issues -> assert length(issues) >= 3 end)
    end

    test "abbreviated binding in an anonymous function closure is reported" do
      """
      defmodule Sample do
        def process(list), do: Enum.map(list, fn e -> e.id end)
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issue()
    end

    test "abbreviated binding in a rescue clause is reported" do
      """
      defmodule Sample do
        def process do
          :ok
        rescue
          e -> reraise e, __STACKTRACE__
        end
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issue()
    end

    test "abbreviated binding in a destructured map pattern (closure) is reported" do
      """
      defmodule Sample do
        def process(list), do: Enum.map(list, fn %{state: s} -> s end)
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> assert_issue()
    end
  end

  describe "closures and rescue — negative cases" do
    test "underscore-prefixed closure bindings are allowed" do
      """
      defmodule Sample do
        def process(list), do: Enum.map(list, fn _e -> :ok end)
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> refute_issues()
    end

    test "idiomatic closure bindings (acc, msg) are allowed" do
      """
      defmodule Sample do
        def process(list) do
          Enum.reduce(list, [], fn msg, acc -> [msg | acc] end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> refute_issues()
    end

    test "spelled-out closure bindings are allowed" do
      """
      defmodule Sample do
        def process(list), do: Enum.map(list, fn file -> file.path end)
      end
      """
      |> to_source_file()
      |> run_check(NoAbbreviatedNames)
      |> refute_issues()
    end
  end
end
