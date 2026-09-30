defmodule MediaCentaur.Credo.Checks.ObanUniqueStatesDeclaredTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ObanUniqueStatesDeclared

  describe "clean code (negative cases)" do
    test "a worker without unique is allowed" do
      ~S'''
      defmodule Sample.Worker do
        use Oban.Worker, queue: :maintenance, max_attempts: 3
      end
      '''
      |> to_source_file("lib/sample/worker.ex")
      |> run_check(ObanUniqueStatesDeclared)
      |> refute_issues()
    end

    test "unique that names its states is allowed" do
      ~S'''
      defmodule Sample.Worker do
        use Oban.Worker,
          queue: :acquisition,
          unique: [period: :infinity, keys: [:plan_id], states: [:available, :scheduled, :retryable]]
      end
      '''
      |> to_source_file("lib/sample/worker.ex")
      |> run_check(ObanUniqueStatesDeclared)
      |> refute_issues()
    end

    test "a named state group is allowed" do
      ~S'''
      defmodule Sample.Worker do
        use Oban.Worker, queue: :images, unique: [period: 60, keys: [:entity_id], states: :successful]
      end
      '''
      |> to_source_file("lib/sample/worker.ex")
      |> run_check(ObanUniqueStatesDeclared)
      |> refute_issues()
    end
  end

  describe "unique without states" do
    test "is reported" do
      ~S'''
      defmodule Sample.Worker do
        use Oban.Worker, queue: :images, unique: [period: 60, keys: [:entity_id]]
      end
      '''
      |> to_source_file("lib/sample/worker.ex")
      |> run_check(ObanUniqueStatesDeclared)
      |> assert_issue(fn issue -> assert issue.message =~ "states:" end)
    end

    test "is reported across a multi-line use" do
      ~S'''
      defmodule Sample.Worker do
        use Oban.Worker,
          queue: :self_update,
          unique: [period: 120]
      end
      '''
      |> to_source_file("lib/sample/worker.ex")
      |> run_check(ObanUniqueStatesDeclared)
      |> assert_issue()
    end
  end
end
