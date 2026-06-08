defmodule MediaCentaur.Credo.Checks.ModalBackdropViaComponentTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ModalBackdropViaComponent

  describe "clean code (negative cases)" do
    test "modal-backdrop inside the modal seam is allowed" do
      ~S'''
      defmodule MediaCentaurWeb.Components.Modal do
        use Phoenix.Component

        def modal(assigns) do
          ~H"""
          <div class="modal-backdrop">
            <div class="modal-panel">content</div>
          </div>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/modal.ex")
      |> run_check(ModalBackdropViaComponent)
      |> refute_issues()
    end

    test "a component with no modal-backdrop is allowed" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def card(assigns) do
          ~H"""
          <div class="glass-surface">content</div>
          """
        end
      end
      '''
      |> to_source_file("lib/my_component.ex")
      |> run_check(ModalBackdropViaComponent)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "modal-backdrop outside the seam is reported" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def modal(assigns) do
          ~H"""
          <div class="modal-backdrop">
            <div class="modal-panel">content</div>
          </div>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/my_modal.ex")
      |> run_check(ModalBackdropViaComponent)
      |> assert_issue()
    end
  end
end
