defmodule MediaCentaur.Credo.Checks.TestCaseTemplateTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.TestCaseTemplate

  describe "clean code" do
    test "a test module states its ownership through the root template" do
      """
      defmodule SomeTest do
        use MediaCentaur.Case, async: true
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(TestCaseTemplate)
      |> refute_issues()
    end

    test "DataCase and ConnCase with an explicit async are fine" do
      """
      defmodule SomeTest do
        use MediaCentaur.DataCase, async: false
      end
      defmodule OtherTest do
        use MediaCentaurWeb.ConnCase, async: false
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(TestCaseTemplate)
      |> refute_issues()
    end

    test "Credo.Test.Case is the one foreign template allowed" do
      """
      defmodule SomeCheckTest do
        use Credo.Test.Case, async: true
      end
      """
      |> to_source_file("test/media_centaur/credo/checks/some_check_test.exs")
      |> run_check(TestCaseTemplate)
      |> refute_issues()
    end

    test "a case template under test/support may use ExUnit directly" do
      """
      defmodule MediaCentaur.Case do
        use ExUnit.CaseTemplate
      end
      """
      |> to_source_file("test/support/case.ex")
      |> run_check(TestCaseTemplate)
      |> refute_issues()
    end
  end

  describe "violations" do
    test "a bare use ExUnit.Case is not checked out" do
      """
      defmodule SomeTest do
        use ExUnit.Case, async: false
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(TestCaseTemplate)
      |> assert_issue(fn issue ->
        assert issue.trigger == "ExUnit.Case"
        assert issue.message =~ "MediaCentaur.Case"
      end)
    end

    test "a template used without async: leaves ownership implicit" do
      """
      defmodule SomeTest do
        use MediaCentaur.Case
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(TestCaseTemplate)
      |> assert_issue(fn issue ->
        assert issue.trigger == "MediaCentaur.Case"
        assert issue.message =~ "async:"
      end)
    end

    test "DataCase without async: is flagged too" do
      """
      defmodule SomeTest do
        use MediaCentaur.DataCase
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(TestCaseTemplate)
      |> assert_issue(fn issue -> assert issue.trigger == "MediaCentaur.DataCase" end)
    end
  end
end
