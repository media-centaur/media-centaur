defmodule MediaCentaur.Credo.Checks.NoSupervisorChildTogglingTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NoSupervisorChildToggling

  test "stopping a dynamic child is the normal way to end it" do
    ~S'''
    defmodule MediaCentaur.Something do
      def stop(pid), do: DynamicSupervisor.terminate_child(MediaCentaur.Something.DynamicSupervisor, pid)
    end
    '''
    |> to_source_file("lib/media_centaur/something.ex")
    |> run_check(NoSupervisorChildToggling)
    |> refute_issues()
  end

  test "Supervisor.terminate_child/2 in lib is reported" do
    ~S'''
    defmodule MediaCentaur.Something do
      def stop, do: Supervisor.terminate_child(__MODULE__, MediaCentaur.Something.Worker)
    end
    '''
    |> to_source_file("lib/media_centaur/something.ex")
    |> run_check(NoSupervisorChildToggling)
    |> assert_issue()
  end

  test "Supervisor.restart_child/2 in lib is reported" do
    ~S'''
    defmodule MediaCentaur.Something do
      def start, do: Supervisor.restart_child(__MODULE__, MediaCentaur.Something.Worker)
    end
    '''
    |> to_source_file("lib/media_centaur/something.ex")
    |> run_check(NoSupervisorChildToggling)
    |> assert_issue()
  end

  test "a test may drive a supervisor it started" do
    ~S'''
    defmodule MediaCentaur.SomethingTest do
      use MediaCentaur.Case, async: true

      test "restart" do
        :ok = Supervisor.terminate_child(sup, :worker)
      end
    end
    '''
    |> to_source_file("test/media_centaur/something_test.exs")
    |> run_check(NoSupervisorChildToggling)
    |> refute_issues()
  end
end
