defmodule MediaCentaur.Credo.Checks.DeviceNeutralConfirmCopyTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.DeviceNeutralConfirmCopy

  test "an armed label that says press is allowed" do
    ~S'''
    defmodule MediaCentaurWeb.SomeLive do
      def render(assigns) do
        ~H"""
        <.armed_button event="remove" armed={@armed} armed_label="Press again to remove">Remove</.armed_button>
        """
      end
    end
    '''
    |> to_source_file("lib/media_centaur_web/live/some_live.ex")
    |> run_check(DeviceNeutralConfirmCopy)
    |> refute_issues()
  end

  test "an armed label that tells a remote or gamepad user to click is reported" do
    ~S'''
    defmodule MediaCentaurWeb.SomeLive do
      def render(assigns) do
        ~H"""
        <.armed_button event="remove" armed={@armed} armed_label="Click again to remove">Remove</.armed_button>
        """
      end
    end
    '''
    |> to_source_file("lib/media_centaur_web/live/some_live.ex")
    |> run_check(DeviceNeutralConfirmCopy)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "lowercase pointer wording in a confirm string is reported" do
    ~S'''
    defmodule MediaCentaurWeb.SomeLive do
      def label(true), do: "click to confirm"
    end
    '''
    |> to_source_file("lib/media_centaur_web/live/some_live.ex")
    |> run_check(DeviceNeutralConfirmCopy)
    |> assert_issue()
  end

  test "code outside the web layer is not checked" do
    ~S'''
    defmodule MediaCentaur.Something do
      def label, do: "Click again to remove"
    end
    '''
    |> to_source_file("lib/media_centaur/something.ex")
    |> run_check(DeviceNeutralConfirmCopy)
    |> refute_issues()
  end
end
