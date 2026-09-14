defmodule MediaCentaur.Settings.Preferences.PlanningModeTest do
  @moduledoc """
  The default planning mode: what the Download button on a title the
  library does not own does by default. Two modes, one default; every
  malformed row reads as the default so a bad value can never turn on
  unattended commits.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Preferences.PlanningMode

  describe "value/0" do
    test "is :manually_select_release when no entry exists" do
      assert Settings.get_by_key(PlanningMode.setting_key()) == nil
      assert PlanningMode.value() == :manually_select_release
    end

    test "reads a stored auto_select_best_release" do
      store(%{"mode" => "auto_select_best_release"})
      assert PlanningMode.value() == :auto_select_best_release
    end

    test "reads a stored manually_select_release" do
      store(%{"mode" => "manually_select_release"})
      assert PlanningMode.value() == :manually_select_release
    end

    test "an unknown mode string is the default" do
      store(%{"mode" => "grab_everything"})
      assert PlanningMode.value() == :manually_select_release
    end

    test "a value shaped unexpectedly is the default" do
      store(%{"enabled" => true})
      assert PlanningMode.value() == :manually_select_release
    end
  end

  describe "set/1" do
    test "persists the mode under the key" do
      PlanningMode.set(:auto_select_best_release)
      assert PlanningMode.value() == :auto_select_best_release

      PlanningMode.set(:manually_select_release)
      assert PlanningMode.value() == :manually_select_release
    end

    test "rejects anything but a mode" do
      # Built at runtime: the type checker already rejects an unknown literal.
      unknown = String.to_atom("grab")
      assert_raise FunctionClauseError, fn -> PlanningMode.set(unknown) end
    end
  end

  describe "modes/0" do
    test "lists both modes, the default first" do
      assert PlanningMode.modes() == [:manually_select_release, :auto_select_best_release]
    end
  end

  describe "other/1" do
    test "is the one alternative" do
      assert PlanningMode.other(:manually_select_release) == :auto_select_best_release
      assert PlanningMode.other(:auto_select_best_release) == :manually_select_release
    end
  end

  describe "approval_policy/1" do
    test "auto-select commits alone; manual select parks for review" do
      assert PlanningMode.approval_policy(:auto_select_best_release) == "automatic"
      assert PlanningMode.approval_policy(:manually_select_release) == "review"
    end
  end

  defp store(value) do
    Settings.find_or_create_entry!(%{key: PlanningMode.setting_key(), value: value})
  end
end
