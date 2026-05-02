defmodule MediaCentarr.Credo.Checks.RawBadgeClassTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.RawBadgeClass

  describe "clean code (negative cases)" do
    test "<.badge> component usage is allowed" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <.badge>{@count}</.badge>
          <.badge variant="type">Movie</.badge>
          <.badge variant="success">Completed</.badge>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawBadgeClass)
      |> refute_issues()
    end

    test "the badge component file itself is allowed to write `badge` literally" do
      ~S'''
      defmodule MediaCentarrWeb.CoreComponents do
        use Phoenix.Component

        def badge(assigns) do
          assigns = assign(assigns, :class, ["badge", "badge-sm"])

          ~H"""
          <span class={@class}>{render_slot(@inner_block)}</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/core_components.ex")
      |> run_check(RawBadgeClass)
      |> refute_issues()
    end

    test "custom CSS classes ending in -badge are allowed (no standalone badge token)" do
      ~S'''
      defmodule MediaCentarrWeb.ConsoleComponents do
        use Phoenix.Component

        def render(assigns) do
          ~H"""
          <span class="console-component-badge">x</span>
          <span class="my-badge text-error">y</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/console_components.ex")
      |> run_check(RawBadgeClass)
      |> refute_issues()
    end

    test "plain colored text (UIDR-002 status reasons) is allowed" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span class="text-error">Failed</span>
          <span class="text-warning">Partial match</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawBadgeClass)
      |> refute_issues()
    end

    test "files outside lib/media_centarr_web/ are not scanned" do
      ~S'''
      defmodule MediaCentarr.NotATemplate do
        @moduledoc "badge badge-info"
        def html_string, do: ~s(<span class="badge badge-info">x</span>)
      end
      '''
      |> to_source_file("lib/media_centarr/not_a_template.ex")
      |> run_check(RawBadgeClass)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "raw badge class in a LiveView render is reported" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span class="badge badge-sm">{@count}</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawBadgeClass)
      |> assert_issue()
    end

    test "raw badge-only class is reported" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span class="badge">x</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawBadgeClass)
      |> assert_issue()
    end

    test "raw badge in a class={[\"...\"]} list expression is reported" do
      ~S'''
      defmodule MediaCentarrWeb.ActivityComponent do
        use Phoenix.Component

        def render(assigns) do
          ~H"""
          <span class={["badge badge-sm", origin_class(@grab)]}>x</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/acquisition_live/activity.ex")
      |> run_check(RawBadgeClass)
      |> assert_issue()
    end

    test "raw badge with leading utility classes is reported" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span class="badge badge-sm badge-ghost ml-1">x3</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawBadgeClass)
      |> assert_issue()
    end

    test "two violations on separate lines produce two issues" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span class="badge badge-info">A</span>
          <span class="badge badge-success">B</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawBadgeClass)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end
  end
end
