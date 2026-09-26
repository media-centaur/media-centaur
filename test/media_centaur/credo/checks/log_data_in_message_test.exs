defmodule MediaCentaur.Credo.Checks.LogDataInMessageTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.LogDataInMessage

  describe "clean code (negative cases)" do
    test "data interpolated into the message is allowed" do
      ~S'''
      defmodule MediaCentaur.Sample do
        def run(reason), do: Log.warning(:system, "snapshot ignored — #{inspect(reason)}")
      end
      '''
      |> to_source_file()
      |> run_check(LogDataInMessage)
      |> refute_issues()
    end

    test "mc_incident: :skip is allowed" do
      ~S'''
      defmodule MediaCentaur.Sample do
        def run, do: Log.warning(:acquisition, "client unreachable", mc_incident: :skip)
      end
      '''
      |> to_source_file()
      |> run_check(LogDataInMessage)
      |> refute_issues()
    end

    test "a non-literal keyword list is left alone" do
      ~S'''
      defmodule MediaCentaur.Sample do
        def run(metadata), do: Log.warning(:system, "dynamic", metadata)
      end
      '''
      |> to_source_file()
      |> run_check(LogDataInMessage)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "data passed as logger metadata is reported" do
      ~S'''
      defmodule MediaCentaur.Sample do
        def run(reason), do: Log.warning(:system, "snapshot ignored", reason: inspect(reason))
      end
      '''
      |> to_source_file()
      |> run_check(LogDataInMessage)
      |> assert_issue(fn issue -> assert issue.trigger == "reason" end)
    end

    test "the fully qualified macro is checked, key by key" do
      ~S'''
      defmodule MediaCentaur.Sample do
        def run(path), do: MediaCentaur.Log.info(:system, "wrote", path: path, mc_incident: :skip)
      end
      '''
      |> to_source_file()
      |> run_check(LogDataInMessage)
      |> assert_issue(fn issue -> assert issue.trigger == "path" end)
    end
  end
end
