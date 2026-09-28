defmodule MediaCentaur.Credo.Checks.TextInputDebouncedTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.TextInputDebounced

  @path "lib/media_centaur_web/components/some_component.ex"

  defp check(heex) do
    """
    defmodule MediaCentaurWeb.SomeComponent do
      use Phoenix.Component

      def thing(assigns) do
        ~H\"\"\"
    #{heex}
        \"\"\"
      end
    end
    """
    |> to_source_file(@path)
    |> run_check(TextInputDebounced)
  end

  describe "violations" do
    test "a text input inside a phx-change form with no debounce" do
      assert_issue(
        check(~S"""
        <form phx-change="filter">
          <input type="text" name="q" value={@q} />
        </form>
        """)
      )
    end

    test "an input with no type (text) inside a phx-change form" do
      assert_issue(
        check(~S"""
        <form phx-change="filter"><input name="q" /></form>
        """)
      )
    end

    test "a textarea inside a phx-change form" do
      assert_issue(
        check(~S"""
        <form phx-change="set_body">
          <textarea name="value">{@body}</textarea>
        </form>
        """)
      )
    end

    test "a debounce on the form does not count: LiveView reads it from the input" do
      assert_issue(
        check(~S"""
        <form phx-change="set_title" phx-debounce="300">
          <input type="text" name="value" />
        </form>
        """)
      )
    end

    test "a range input with its own phx-change" do
      assert_issue(
        check(~S"""
        <input type="range" name="size" phx-change="resize" />
        """)
      )
    end

    test "a text input with phx-keyup" do
      assert_issue(
        check(~S"""
        <input type="search" name="q" phx-keyup="search" />
        """)
      )
    end

    test "the input components are checked like the element they render" do
      assert_issues(
        check(~S"""
        <form phx-change="validate">
          <.settings_input name="item" value={@value} />
          <.input type="text" field={@form[:name]} />
        </form>
        """),
        fn issues -> assert length(issues) == 2 end
      )
    end

    test "a multi-line tag whose attribute expression contains a pipe" do
      assert_issue(
        check(~S"""
        <form phx-change="filter">
          <input
            type="text"
            name="q"
            phx-focus={JS.add_class("active") |> JS.focus()}
          />
        </form>
        """)
      )
    end
  end

  describe "clean code" do
    test "a debounced text input" do
      refute_issues(
        check(~S"""
        <form phx-change="filter">
          <input type="text" name="q" phx-debounce="300" />
        </form>
        """)
      )
    end

    test "blur and throttle count as rate limits" do
      refute_issues(
        check(~S"""
        <form phx-change="save">
          <input type="text" name="a" phx-debounce="blur" />
          <textarea name="b" phx-throttle="500"></textarea>
        </form>
        """)
      )
    end

    test "discrete controls need no debounce" do
      refute_issues(
        check(~S"""
        <form phx-change="pick">
          <input type="checkbox" name="on" />
          <input type="radio" name="kind" value="a" />
          <input type="hidden" name="id" value="1" />
          <select name="type"><option>a</option></select>
        </form>
        """)
      )
    end

    test "a text input outside any phx-change context" do
      refute_issues(
        check(~S"""
        <form phx-submit="save">
          <input type="text" name="q" />
        </form>
        <input type="text" name="free" />
        """)
      )
    end

    test "a form closes its context" do
      refute_issues(
        check(~S"""
        <form phx-change="filter"><input type="text" name="q" phx-debounce="200" /></form>
        <form phx-submit="save"><input type="text" name="other" /></form>
        """)
      )
    end

    test "files outside the web layer are not checked" do
      """
      defmodule MediaCentaur.Something do
        def doc, do: ~s(<form phx-change="x"><input type="text" /></form>)
      end
      """
      |> to_source_file("lib/media_centaur/something.ex")
      |> run_check(TextInputDebounced)
      |> refute_issues()
    end
  end
end
