defmodule MediaCentarr.Credo.Checks.StorybookCoverageTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.StorybookCoverage

  # =============================================================
  # SCOPE
  # =============================================================

  describe "scope" do
    test "ignores files outside lib/media_centarr_web/components/" do
      """
      defmodule MediaCentarrWeb.SomeOtherThing do
        attr :name, :string, required: true

        def thing(assigns) do
          ~H"<div></div>"
        end
      end
      """
      |> to_source_file("lib/media_centarr_web/some_other_thing.ex")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end

    test "ignores files under components/ that have no attr declarations" do
      """
      defmodule MediaCentarrWeb.Components.Detail.Logic do
        @moduledoc "pure helpers"
        def truncate(string, n), do: String.slice(string, 0, n)
      end
      """
      |> to_source_file("lib/media_centarr_web/components/detail/logic.ex")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end
  end

  # =============================================================
  # V1 — COVERAGE
  # =============================================================

  describe "v1 coverage — story-file detection" do
    test "passes when a corresponding story file exists" do
      # The check looks for storybook/sample/sample.story.exs
      # We simulate this by stubbing File.exists?/1 via the params keyword.
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage,
        story_paths: ["storybook/sample/sample.story.exs"]
      )
      |> refute_issues()
    end

    test "errors when no story exists and no @storybook_status declared" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.category == :design
        assert issue.message =~ ~r/no story/i
      end)
    end

    test "passes when @storybook_status is :skip with a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :skip
        @storybook_reason "Sticky LiveView state"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> refute_issues()
    end

    test "passes when @storybook_status is :static_example with a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :static_example
        @storybook_reason "Depends on TMDB context"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> refute_issues()
    end

    test "warns (low priority) when @storybook_status is :pending with a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :pending
        @storybook_reason "Phase 4"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        # priority drops below default for warnings
        assert issue.priority < 0
        # :pending is a non-blocking warning — it must not contribute to
        # the credo exit status, otherwise mix precommit fails on pending
        # components even though they're explicitly opt-in deferred.
        assert issue.exit_status == 0
      end)
    end

    test "errors when @storybook_status is :skip without a reason" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :skip

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/@storybook_reason/
      end)
    end

    test "errors when @storybook_status is an unknown value" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        @storybook_status :nonsense
        @storybook_reason "Whatever"

        attr :label, :string, required: true

        def sample(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(StorybookCoverage, story_paths: [])
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/unknown.*status/i
      end)
    end
  end

  # =============================================================
  # V1 — CROSS-CUTTING STORY DIRECTORIES
  # =============================================================
  #
  # The component-to-story match is by basename, so a story can live in any
  # subdirectory of `storybook/` and still cover the component. These tests
  # exercise the matching logic by passing a representative `story_paths`
  # override — the same code path the production wildcard scan flows through.

  describe "v1 coverage — cross-cutting story directories" do
    test "covers a component when its story lives in a cross-cutting area (storybook/composites/)" do
      """
      defmodule MediaCentarrWeb.Components.ModalShell do
        attr :id, :string, required: true

        def modal_shell(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/modal_shell.ex")
      |> run_check(StorybookCoverage,
        story_paths: [
          "storybook/composites/modal_shell.story.exs",
          "storybook/core_components/button.story.exs"
        ]
      )
      |> refute_issues()
    end

    test "covers a component when its story sits at the conventional path" do
      """
      defmodule MediaCentarrWeb.CoreComponents do
        attr :label, :string, required: true

        def button(assigns), do: ~H"<button></button>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/core_components.ex")
      |> run_check(StorybookCoverage,
        story_paths: [
          "storybook/core_components/button.story.exs",
          "storybook/composites/modal_shell.story.exs"
        ]
      )
      |> refute_issues()
    end

    test "errors when no path in the wildcard list matches the component's basename" do
      """
      defmodule MediaCentarrWeb.Components.Orphan do
        attr :label, :string, required: true

        def orphan(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/orphan.ex")
      |> run_check(StorybookCoverage,
        story_paths: [
          "storybook/composites/modal_shell.story.exs",
          "storybook/core_components/button.story.exs",
          "storybook/foundations/colors.story.exs"
        ]
      )
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/no story/i
        assert issue.message =~ ":orphan"
      end)
    end
  end

  # =============================================================
  # V2 — STORY SHAPE
  # =============================================================

  describe "v2 story shape — namespace" do
    test "errors when story module is not under MediaCentarrWeb.Storybook.*" do
      """
      defmodule Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :function

        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/MediaCentarrWeb\.Storybook\./
      end)
    end

    test "passes when story module is under MediaCentarrWeb.Storybook.*" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :function

        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end
  end

  describe "v2 story shape — required callbacks for component stories" do
    test "errors when a :component story does not define function/0" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def render_source, do: :function
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/function\/0/
      end)
    end

    test "errors when a :component story uses render_source :module" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :module
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~r/render_source.*:function/
      end)
    end

    test "passes when a :component story has render_source :function" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def render_source, do: :function
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end

    test "passes when a :component story omits render_source (uses default)" do
      """
      defmodule MediaCentarrWeb.Storybook.CoreComponents.Button do
        use PhoenixStorybook.Story, :component

        def function, do: &MediaCentarrWeb.CoreComponents.button/1
        def variations, do: []
      end
      """
      |> to_source_file("storybook/core_components/button.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end

    test "ignores :page stories — they don't need function/0 or render_source" do
      """
      defmodule MediaCentarrWeb.Storybook.Foundations.Colors do
        use PhoenixStorybook.Story, :page

        def render(assigns), do: ~H"<div></div>"
      end
      """
      |> to_source_file("storybook/foundations/colors.story.exs")
      |> run_check(StorybookCoverage)
      |> refute_issues()
    end
  end
end
