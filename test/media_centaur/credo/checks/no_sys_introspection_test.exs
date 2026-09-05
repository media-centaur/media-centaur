defmodule MediaCentaur.Credo.Checks.NoSysIntrospectionTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NoSysIntrospection

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

  describe "GenServer messaging from tests" do
    test "GenServer.call in a test is reported" do
      ~S'''
      defmodule MyTest do
        use ExUnit.Case

        test "drives the server by message" do
          :ok = GenServer.call(MyServer, :sync)
        end
      end
      '''
      |> to_source_file("test/my_test.exs")
      |> run_check(NoSysIntrospection)
      |> assert_issue()
    end

    test "GenServer.cast in a test is reported" do
      ~S'''
      defmodule MyTest do
        use ExUnit.Case

        test "drives the server by message" do
          :ok = GenServer.cast(MyServer, {:record, 1})
        end
      end
      '''
      |> to_source_file("test/my_test.exs")
      |> run_check(NoSysIntrospection)
      |> assert_issue()
    end

    test "a __for_test__ seam in lib/ is where the message belongs" do
      ~S'''
      defmodule MyServer do
        def __sync_for_test__(server \\ __MODULE__), do: GenServer.call(server, :sync)
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
