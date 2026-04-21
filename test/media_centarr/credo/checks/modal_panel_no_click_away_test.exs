defmodule MediaCentarr.Credo.Checks.ModalPanelNoClickAwayTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.ModalPanelNoClickAway

  describe "clean code (negative cases)" do
    test "backdrop-click pattern is allowed" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def modal(assigns) do
          ~H"""
          <div class="modal-backdrop" phx-click={@on_close}>
            <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
              content
            </div>
          </div>
          """
        end
      end
      '''
      |> to_source_file("lib/my_component.ex")
      |> run_check(ModalPanelNoClickAway)
      |> refute_issues()
    end

    test "phx-click-away on non-modal elements is allowed" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def dropdown(assigns) do
          ~H"""
          <div class="sort-dropdown" phx-click-away="close_sort">
            menu items
          </div>
          """
        end
      end
      '''
      |> to_source_file("lib/my_component.ex")
      |> run_check(ModalPanelNoClickAway)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "phx-click-away on a modal-panel is reported" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def modal(assigns) do
          ~H"""
          <div class="modal-backdrop">
            <div class="modal-panel" phx-click-away={@on_close}>
              content
            </div>
          </div>
          """
        end
      end
      '''
      |> to_source_file("lib/my_component.ex")
      |> run_check(ModalPanelNoClickAway)
      |> assert_issue()
    end

    test "phx-click-away on a modal-panel-sm variant is reported" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def modal(assigns) do
          ~H"""
          <div class="modal-backdrop">
            <div class="modal-panel modal-panel-sm p-6" phx-click-away="delete_cancel">
              content
            </div>
          </div>
          """
        end
      end
      '''
      |> to_source_file("lib/my_component.ex")
      |> run_check(ModalPanelNoClickAway)
      |> assert_issue()
    end
  end
end
