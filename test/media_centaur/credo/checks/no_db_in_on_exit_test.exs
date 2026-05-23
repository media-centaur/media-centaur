defmodule MediaCentaur.Credo.Checks.NoDbInOnExitTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NoDbInOnExit

  describe "clean code (negative cases)" do
    test "on_exit with no DB writes is allowed" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn -> File.rm_rf!("/tmp/x") end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> refute_issues()
    end

    test "on_exit with :persistent_term operations is allowed" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> refute_issues()
    end

    test "on_exit with Sandbox.stop_owner is allowed (intentional teardown)" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> refute_issues()
    end

    test "Config.update outside on_exit is allowed (in test body)" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          Config.update(:exclude_dirs, [])
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> refute_issues()
    end

    test "non-test paths are not analysed" do
      ~S'''
      defmodule MediaCentaur.SomeModule do
        def some_function do
          on_exit(fn -> Config.update(:x, :y) end)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/some_module.ex")
      |> run_check(NoDbInOnExit)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "Config.update inside on_exit is reported" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn -> Config.update(:exclude_dirs, []) end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> assert_issue()
    end

    test "MediaCentaur.Config.update inside on_exit is reported (qualified call)" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn -> MediaCentaur.Config.update(:k, :v) end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> assert_issue()
    end

    test "Settings.find_or_create_entry inside on_exit is reported" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn ->
            Settings.find_or_create_entry(%{key: "x", value: "y"})
          end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> assert_issue()
    end

    test "Repo.insert! inside on_exit is reported" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn -> Repo.insert!(%Thing{}) end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> assert_issue()
    end

    test "Config.update nested inside an on_exit `do ... end` block is reported" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          on_exit(fn ->
            :persistent_term.put(:x, :y)
            Config.update(:k, :v)
            File.rm_rf!("/tmp/x")
          end)
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(NoDbInOnExit)
      |> assert_issue()
    end
  end
end
