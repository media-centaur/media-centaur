defmodule MediaCentaur.Credo.Checks.OneModulePerFileTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.OneModulePerFile

  describe "clean code (negative cases)" do
    test "a single module in a lib file is allowed" do
      ~S'''
      defmodule MediaCentaur.Profile.Suites.ComingUpSuite do
        def run, do: :ok
      end
      '''
      |> to_source_file("lib/media_centaur/profile/suites/coming_up_suite.ex")
      |> run_check(OneModulePerFile)
      |> refute_issues()
    end

    test "a module nested inside the file's module is allowed" do
      ~S'''
      defmodule MediaCentaur.Library.Events do
        defmodule EntitiesChanged do
          defstruct [:ids]
        end

        defmodule EntityRemoved do
          defstruct [:id]
        end
      end
      '''
      |> to_source_file("lib/media_centaur/library/events.ex")
      |> run_check(OneModulePerFile)
      |> refute_issues()
    end

    test "colocated stub modules in a test file are allowed" do
      ~S'''
      defmodule MediaCentaur.IntegrationHealthTest.OkVerifier do
        def verify(_), do: :ok
      end

      defmodule MediaCentaur.IntegrationHealthTest do
        use ExUnit.Case
      end
      '''
      |> to_source_file("test/media_centaur/integration_health_test.exs")
      |> run_check(OneModulePerFile)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "two sibling modules in one lib file are reported" do
      ~S'''
      defmodule MediaCentaur.Profile.Suites.ComingUpSuite do
        def run, do: :ok
      end

      defmodule MediaCentaur.Profile.Suites.ComingUpRefreshSuite do
        def run, do: :ok
      end
      '''
      |> to_source_file("lib/media_centaur/profile/suites/coming_up_suite.ex")
      |> run_check(OneModulePerFile)
      |> assert_issue()
    end

    test "three modules in one lib file report two issues" do
      ~S'''
      defmodule MediaCentaur.A do
      end

      defmodule MediaCentaur.B do
      end

      defmodule MediaCentaur.C do
      end
      '''
      |> to_source_file("lib/media_centaur/a.ex")
      |> run_check(OneModulePerFile)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end
  end
end
