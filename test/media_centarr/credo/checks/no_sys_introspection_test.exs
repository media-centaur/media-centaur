defmodule MediaCentarr.Credo.Checks.NoSysIntrospectionTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.NoSysIntrospection

  describe "clean code (negative cases)" do
    test "test using public API is allowed" do
      ~S'''
      defmodule MyTest do
        use ExUnit.Case

        test "via public API" do
          assert MyServer.count() == 0
          MyServer.add(:foo)
          assert MyServer.count() == 1
        end
      end
      '''
      |> to_source_file("test/my_test.exs")
      |> run_check(NoSysIntrospection)
      |> refute_issues()
    end

    test ":sys calls in lib/ are not flagged (only test/)" do
      ~S'''
      defmodule MyServer do
        def state(pid), do: :sys.get_state(pid)
      end
      '''
      |> to_source_file("lib/my_server.ex")
      |> run_check(NoSysIntrospection)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test ":sys.get_state in test is reported" do
      ~S'''
      defmodule MyTest do
        use ExUnit.Case

        test "peeks at internal state" do
          state = :sys.get_state(MyServer)
          assert state.count == 0
        end
      end
      '''
      |> to_source_file("test/my_test.exs")
      |> run_check(NoSysIntrospection)
      |> assert_issue()
    end

    test ":sys.replace_state in test is reported" do
      ~S'''
      defmodule MyTest do
        use ExUnit.Case

        test "rewrites state" do
          :sys.replace_state(MyServer, fn state -> %{state | count: 5} end)
        end
      end
      '''
      |> to_source_file("test/my_test.exs")
      |> run_check(NoSysIntrospection)
      |> assert_issue()
    end
  end
end
