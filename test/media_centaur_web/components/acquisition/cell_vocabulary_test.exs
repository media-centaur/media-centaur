defmodule MediaCentaurWeb.Components.Acquisition.CellVocabularyTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Acquisition.CellVocabulary

  # The two renderers (plan board, pursuit card/modal) must map their own state
  # vocabularies onto the same shared states — this table test is the forcing
  # function that keeps them from drifting (UIDR-014). It asserts on the
  # input-state → treatment mapping, not on rendered DOM.

  @states [:searching, :claimed, :claimed_fused, :landed, :gap, :excluded]

  describe "from_plan_state/2" do
    test "an assigned cell inside a capsule fuses" do
      assert CellVocabulary.from_plan_state(:assigned, true) == :claimed_fused
    end

    test "an assigned cell outside a capsule is claimed" do
      assert CellVocabulary.from_plan_state(:assigned, false) == :claimed
    end

    test "maps the remaining plan states onto the shared vocabulary" do
      assert CellVocabulary.from_plan_state(:searching, false) == :searching
      assert CellVocabulary.from_plan_state(:unfound, false) == :gap
      assert CellVocabulary.from_plan_state(:excluded, false) == :excluded
    end
  end

  describe "from_unit_state/1" do
    test "maps pursuit unit states onto the shared vocabulary" do
      assert CellVocabulary.from_unit_state("satisfied") == :landed
      assert CellVocabulary.from_unit_state("active") == :claimed
      assert CellVocabulary.from_unit_state("exhausted") == :gap
      assert CellVocabulary.from_unit_state("cancelled") == :gap
    end

    test "an unknown unit state falls back to a gap" do
      assert CellVocabulary.from_unit_state("anything-else") == :gap
    end
  end

  describe "treatments" do
    test "every shared state has a non-empty full-cell treatment" do
      for state <- @states do
        treatment = CellVocabulary.cell_treatment(state)
        assert is_binary(treatment) and treatment != ""
      end
    end

    test "every shared state has a non-empty segment treatment (with a fallback)" do
      for state <- @states do
        treatment = CellVocabulary.segment_treatment(state)
        assert is_binary(treatment) and treatment != ""
      end
    end
  end

  describe "below-preference state (UIDR-029)" do
    test "plan below_preference maps onto its own vocabulary state" do
      assert CellVocabulary.from_plan_state(:below_preference, false) == :below_preference
      assert CellVocabulary.from_plan_state(:below_preference, true) == :below_preference
    end

    test "treatments exist for both renderers" do
      assert CellVocabulary.cell_treatment(:below_preference) =~ "border-info"
      assert CellVocabulary.segment_treatment(:below_preference) =~ "bg-info"
    end
  end

end
