defmodule MediaCentarr.Credo.Checks.PredicateNamingTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.PredicateNaming

  describe "clean code (negative cases)" do
    test "predicate ending in ? is allowed" do
      """
      defmodule Sample do
        def user?(cookie), do: cookie != nil
        defp has_attachment?(mail), do: mail.attachments != []
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> refute_issues()
    end

    test "defmacro may use is_ prefix" do
      """
      defmodule Sample do
        defmacro is_user(cookie) do
          quote do: unquote(cookie) != nil
        end
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> refute_issues()
    end

    test "defguard may use is_ prefix" do
      """
      defmodule Sample do
        defguard is_user_id(value) when is_integer(value) and value > 0
        defguardp is_positive(n) when is_integer(n) and n > 0
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> refute_issues()
    end

    test "non-predicate functions are ignored" do
      """
      defmodule Sample do
        def fetch_user(id), do: id
        defp build_response(data), do: data
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "def starting with is_ is reported" do
      """
      defmodule Sample do
        def is_user(cookie), do: cookie != nil
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> assert_issue()
    end

    test "defp starting with is_ is reported" do
      """
      defmodule Sample do
        defp is_admin(user), do: user.admin
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> assert_issue()
    end

    test "def ending in ? AND starting with is_ is reported" do
      """
      defmodule Sample do
        def is_user?(cookie), do: cookie != nil
      end
      """
      |> to_source_file()
      |> run_check(PredicateNaming)
      |> assert_issue()
    end
  end
end
